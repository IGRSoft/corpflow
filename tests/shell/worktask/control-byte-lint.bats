#!/usr/bin/env bats
# control-byte-lint.sh — the control-byte CLI: explicit paths, the staged index scan and
# the self-test. Staged cases run in a throwaway repository; raw bytes are printf-generated.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

CLI="skills/worktask/scripts/control-byte-lint.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  cd "$WD"
}

seed_repo() {
  git init -q .
  git config user.email a@b.c
  git config user.name t
  printf 'base\n' > base.md
  git add base.md
  git commit -q -m base
}

lint() {
  run bash "$PLUGIN_ROOT/$CLI" "$@"
}

# --- path mode ---------------------------------------------------------------

@test "--self-test prints OK" {
  lint --self-test
  assert_success
  assert_output "control-byte-lint: self-test OK"
}

@test "paths: a hit prints path:offset:hex and exits 1" {
  printf 'ok\nx\033\n' > hit.md
  lint hit.md
  assert_failure 1
  assert_line "hit.md:4:0x1B"
  assert_output --partial "control bytes in 1 file(s)"
}

@test "paths: clean text and a non-text extension pass" {
  printf 'clean\ttext\r\n' > clean.md
  printf 'x\033y' > art.png
  lint clean.md art.png
  assert_success
  assert_output ""
}

@test "paths: -- lets a dash-led path through" {
  printf '\000' > -dash.md
  lint -- -dash.md
  assert_failure 1
  assert_line -- "-dash.md:0:0x00"
}

@test "paths: a missing text path exits 2" {
  lint missing.md
  assert_failure 2
  assert_output --partial "cannot scan missing.md"
}

@test "usage: no arguments and an unknown option exit 2" {
  lint
  assert_failure 2
  lint --bogus
  assert_failure 2
  assert_output --partial "unknown option: --bogus"
}

@test "the CLI refuses to run when the library is unreachable" {
  mkdir -p "$WD/scripts"
  cp "$PLUGIN_ROOT/$CLI" "$WD/scripts/control-byte-lint.sh"
  printf 'x\n' > a.md
  run bash "$WD/scripts/control-byte-lint.sh" a.md
  assert_failure 2
  assert_output --partial "control-byte-lib.sh unreachable"
}

# --- staged mode --------------------------------------------------------------

@test "staged: a staged control byte is reported with its offset" {
  seed_repo
  printf 'a\033b\n' > s.md
  git add s.md
  lint --staged
  assert_failure 1
  assert_line "s.md:1:0x1B"
}

@test "staged: a clean index passes" {
  seed_repo
  printf 'clean\n' > s.md
  git add s.md
  lint --staged
  assert_success
}

# bash 4+ leaves a value-less local unset, so a loop that never runs must not read one.
@test "staged: an empty index exits 0 and prints nothing" {
  seed_repo
  printf 'unstaged\000\n' >> base.md
  lint --staged
  assert_success
  assert_output ""
}

@test "staged: the index bytes decide, not the worktree, in both directions" {
  seed_repo
  printf 'clean\n' > s.md
  git add s.md
  printf 'dirty\000\n' > s.md
  lint --staged
  assert_success

  printf 'dirty\000\n' > t.md
  git add t.md
  printf 'clean\n' > t.md
  lint --staged
  assert_failure 1
  assert_line "t.md:5:0x00"
}

@test "staged: paths holding a space or a newline are reported whole" {
  seed_repo
  printf '\033' > 'sp ace.md'
  printf 'x\000' > "$(printf 'new\nline.md')"
  git add -A
  lint --staged
  assert_failure 1
  assert_line "sp ace.md:0:0x1B"
  assert_output --partial "$(printf 'new\nline.md:1:0x00')"
}

@test "staged: a deleted file is not scanned" {
  seed_repo
  printf 'x\033\n' > gone.md
  git add gone.md
  git commit -q -m gone
  git rm -q gone.md
  lint --staged
  assert_success
}

@test "staged: gitlinks and symlinks are skipped by mode" {
  seed_repo
  local blob head
  head="$(git rev-parse HEAD)"
  blob="$(printf 'x\001y' | git hash-object -w --stdin)"
  git update-index --add --cacheinfo "160000,$head,sub.md"
  git update-index --add --cacheinfo "120000,$blob,link.md"
  lint --staged
  assert_success
}

@test "staged: a path declared binary or -text is skipped" {
  seed_repo
  printf '*.txt binary\nansi.md -text\n' > .gitattributes
  printf 'x\033\n' > fixture.txt
  printf 'x\033\n' > ansi.md
  git add .gitattributes fixture.txt ansi.md
  lint --staged
  assert_success
}

@test "staged: an unmerged path exits 2 naming it" {
  seed_repo
  printf 'one\n' > c.md
  git add c.md
  git commit -q -m c
  git checkout -q -b other
  printf 'two\n' > c.md
  git commit -q -am other
  git checkout -q -
  printf 'three\n' > c.md
  git commit -q -am main
  git merge -q other > /dev/null 2>&1 || true
  lint --staged
  assert_failure 2
  assert_output --partial "unmerged path c.md"
}

@test "staged: outside a git repository exits 2" {
  run env GIT_CEILING_DIRECTORIES="$(dirname "$WD")" bash "$PLUGIN_ROOT/$CLI" --staged
  assert_failure 2
  assert_output --partial "not a git repository"
}
