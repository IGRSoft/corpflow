#!/usr/bin/env bats
# Contract tests for skills/megatask/scripts/resolve-pbxproj-membership.sh
#
# The failure this script exists to prevent is silent: dropping one side of a
# membershipExceptions conflict unregisters test files, and the build stays
# green while those tests never run again. So the refusal paths are tested as
# first-class behaviour, and every refusal asserts the file is byte-identical
# afterwards — not merely that the exit code was non-zero.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/megatask/scripts/resolve-pbxproj-membership.sh"

# Writes $1 with a membershipExceptions list whose conflict sides are $2 / $3.
_fixture_conflict() {
  local path="$1" ours="$2" theirs="$3"
  {
    printf '\t\tmembershipExceptions = (\n'
    printf '<<<<<<< HEAD\n'
    printf '%b' "$ours"
    printf '=======\n'
    printf '%b' "$theirs"
    printf '>>>>>>> feature/x\n'
    printf '\t\t);\n'
  } > "$path"
}

_sum() { cksum < "$1"; }

@test "happy: both sides survive as a sorted union with no markers left" {
  local wd f
  wd="$(mk_tmpworkdir)"
  f="$wd/project.pbxproj"
  _fixture_conflict "$f" '\t\t\tZeta.swift,\n\t\t\tBeta.swift,\n' '\t\t\tAlpha.swift,\n'

  run_script "$SCRIPT" --file "$f"
  assert_success

  refute_output --partial "<<<<<<<"
  run cat "$f"
  refute_output --partial "<<<<<<<"
  refute_output --partial ">>>>>>>"
  # Sorted, not merely concatenated in side order.
  run sed -n '2,4p' "$f"
  assert_output "$(printf '\t\t\tAlpha.swift,\n\t\t\tBeta.swift,\n\t\t\tZeta.swift,')"
  # The list structure around the conflict is preserved.
  run sed -n '5p' "$f"
  assert_output "$(printf '\t\t);')"
}

@test "happy: an entry present on both sides appears exactly once" {
  local wd f
  wd="$(mk_tmpworkdir)"
  f="$wd/project.pbxproj"
  _fixture_conflict "$f" '\t\t\tShared.swift,\n\t\t\tBeta.swift,\n' \
                          '\t\t\tAlpha.swift,\n\t\t\tShared.swift,\n'

  run_script "$SCRIPT" --file "$f"
  assert_success

  run grep -c 'Shared.swift' "$f"
  assert_output "1"
  run grep -c 'swift,' "$f"
  assert_output "3"
}

@test "edge: --dry-run prints the resolved result and writes nothing" {
  local wd f before
  wd="$(mk_tmpworkdir)"
  f="$wd/project.pbxproj"
  _fixture_conflict "$f" '\t\t\tBeta.swift,\n' '\t\t\tAlpha.swift,\n'
  before="$(_sum "$f")"

  run_script "$SCRIPT" --file "$f" --dry-run
  assert_success
  assert_output --partial "Alpha.swift,"
  assert_output --partial "Beta.swift,"

  [ "$(_sum "$f")" = "$before" ]
  run grep -c '<<<<<<<' "$f"
  assert_output "1"
}

@test "edge: --file=value parsing is equivalent to --file value" {
  local wd f
  wd="$(mk_tmpworkdir)"
  f="$wd/project.pbxproj"
  _fixture_conflict "$f" '\t\t\tBeta.swift,\n' '\t\t\tAlpha.swift,\n'

  run_script "$SCRIPT" "--file=$f"
  assert_success
  run grep -c '<<<<<<<' "$f"
  assert_output "0"
}

@test "edge: a file with no conflict is a 0-exit no-op" {
  local wd f before
  wd="$(mk_tmpworkdir)"
  f="$wd/project.pbxproj"
  printf '\t\tmembershipExceptions = (\n\t\t\tAlpha.swift,\n\t\t);\n' > "$f"
  before="$(_sum "$f")"

  run_script "$SCRIPT" --file "$f"
  assert_success
  assert_output --partial "no conflict found"
  [ "$(_sum "$f")" = "$before" ]
}

@test "failure: a conflict outside membershipExceptions refuses, file untouched" {
  local wd f before
  wd="$(mk_tmpworkdir)"
  f="$wd/project.pbxproj"
  printf '\t\tbuildSettings = {\n<<<<<<< HEAD\n\t\t\tSWIFT_VERSION = 6.0;\n=======\n\t\t\tSWIFT_VERSION = 5.9;\n>>>>>>> feature/x\n\t\t};\n' > "$f"
  before="$(_sum "$f")"

  run_script "$SCRIPT" --file "$f"
  assert_failure 1
  assert_output --partial "refusing: conflict outside membershipExceptions"
  [ "$(_sum "$f")" = "$before" ]
}

@test "failure: an out-of-class conflict anywhere refuses the whole file" {
  local wd f before
  wd="$(mk_tmpworkdir)"
  f="$wd/project.pbxproj"
  {
    printf '\t\tmembershipExceptions = (\n<<<<<<< HEAD\n\t\t\tBeta.swift,\n=======\n\t\t\tAlpha.swift,\n>>>>>>> feature/x\n\t\t);\n'
    printf '\t\tbuildSettings = {\n<<<<<<< HEAD\n\t\t\tA = 1;\n=======\n\t\t\tA = 2;\n>>>>>>> feature/x\n\t\t};\n'
  } > "$f"
  before="$(_sum "$f")"

  run_script "$SCRIPT" --file "$f"
  assert_failure 1
  # All-or-nothing: the in-class conflict is NOT resolved either.
  [ "$(_sum "$f")" = "$before" ]
  run grep -c '<<<<<<<' "$f"
  assert_output "2"
}

@test "edge: the target file's permission bits survive the write" {
  local wd f mode
  wd="$(mk_tmpworkdir)"
  f="$wd/project.pbxproj"
  _fixture_conflict "$f" '\t\t\tBeta.swift,\n' '\t\t\tAlpha.swift,\n'
  # A distinctive mode: asserting 644 would pass on a umask-022 box even with
  # the mode-preserving step deleted.
  chmod 640 "$f"

  run_script "$SCRIPT" --file "$f"
  assert_success

  # Attached format, as in the script: GNU's separated `-f` is --file-system and
  # would print a filesystem block on stdout while exiting 1.
  mode="$(stat -f%Lp "$f" 2> /dev/null || stat -c%a "$f" 2> /dev/null || echo '?')"
  [ "$mode" = "640" ]
}

@test "failure: a single-line list does not latch the in-class state on" {
  local wd f before
  wd="$(mk_tmpworkdir)"
  f="$wd/project.pbxproj"
  # An empty membershipExceptions opens and closes on one line; a conflict in
  # the unrelated children list after it must still be out of class.
  printf '\t\tmembershipExceptions = ( );\n\t\tchildren = (\n<<<<<<< HEAD\n\t\t\tBeta.swift,\n=======\n\t\t\tAlpha.swift,\n>>>>>>> feature/x\n\t\t);\n' > "$f"
  before="$(_sum "$f")"

  run_script "$SCRIPT" --file "$f"
  assert_failure 1
  assert_output --partial "refusing: conflict outside membershipExceptions"
  [ "$(_sum "$f")" = "$before" ]
}

@test "edge: a refusal leaves no temp files behind" {
  local wd f pre post
  wd="$(mk_tmpworkdir)"
  f="$wd/project.pbxproj"
  printf '\t\tbuildSettings = {\n<<<<<<< HEAD\n\t\t\tA = 1;\n=======\n\t\t\tA = 2;\n>>>>>>> feature/x\n\t\t};\n' > "$f"

  pre="$(find "$wd" -name 'resolve-pbxproj-*' | wc -l | tr -d ' ')"
  TMPDIR="$wd" run_script "$SCRIPT" --file "$f"
  assert_failure 1
  post="$(find "$wd" -name 'resolve-pbxproj-*' | wc -l | tr -d ' ')"
  [ "$pre" = "$post" ]
}

@test "failure: nested markers refuse, file byte-identical" {
  local wd f before
  wd="$(mk_tmpworkdir)"
  f="$wd/project.pbxproj"
  printf '\t\tmembershipExceptions = (\n<<<<<<< HEAD\n\t\t\tBeta.swift,\n<<<<<<< HEAD\n\t\t\tGamma.swift,\n=======\n\t\t\tAlpha.swift,\n>>>>>>> feature/x\n\t\t);\n' > "$f"
  before="$(_sum "$f")"

  run_script "$SCRIPT" --file "$f"
  assert_failure 1
  assert_output --partial "refusing: nested conflict start"
  [ "$(_sum "$f")" = "$before" ]
}

@test "failure: a diff3 base section refuses rather than resurrecting a deletion" {
  local wd f before
  wd="$(mk_tmpworkdir)"
  f="$wd/project.pbxproj"
  printf '\t\tmembershipExceptions = (\n<<<<<<< HEAD\n\t\t\tBeta.swift,\n||||||| base\n\t\t\tGamma.swift,\n=======\n\t\t\tAlpha.swift,\n>>>>>>> feature/x\n\t\t);\n' > "$f"
  before="$(_sum "$f")"

  run_script "$SCRIPT" --file "$f"
  assert_failure 1
  assert_output --partial "refusing: diff3 base section present"
  [ "$(_sum "$f")" = "$before" ]
}

@test "failure: a non-entry line inside a side refuses, file byte-identical" {
  local wd f before
  wd="$(mk_tmpworkdir)"
  f="$wd/project.pbxproj"
  _fixture_conflict "$f" '\t\t\t/* added by #12 */\n\t\t\tBeta.swift,\n' '\t\t\tAlpha.swift,\n'
  before="$(_sum "$f")"

  run_script "$SCRIPT" --file "$f"
  assert_failure 1
  assert_output --partial "refusing: non-entry line in conflict side"
  [ "$(_sum "$f")" = "$before" ]
}

@test "failure: missing --file exits 1" {
  run_script "$SCRIPT"
  assert_failure 1
  assert_output --partial "--file <path> is required"
}

@test "failure: an unreadable path exits 1 without a refusal prefix" {
  local wd
  wd="$(mk_tmpworkdir)"
  run_script "$SCRIPT" --file "$wd/absent.pbxproj"
  assert_failure 1
  assert_output --partial "--file not found"
  refute_output --partial "refusing:"
}

@test "contract: --self-test passes (smoke)" {
  run_script "$SCRIPT" --self-test
  assert_success
  assert_output --partial "self-test OK"
}
