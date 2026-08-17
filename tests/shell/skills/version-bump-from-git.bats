#!/usr/bin/env bats
# Contract tests for skills/release-engineering/scripts/version-bump-from-git.sh
# Contracts (from source + self-test):
#   stdout is exactly one of major|minor|patch|none; nothing else.
#   Aggregation is highest-severity-wins across the whole range.
#   Breaking is detected from the header `!` AND from a BREAKING CHANGE footer,
#   independently of commit type (fix!, chore + footer both -> major).
#   `none` is a success (exit 0), distinct from a usage error (exit 1).
#   --file: NUL-separated whole messages, or one subject per line without NUL.
#   --explain writes the breakdown to stderr, leaving stdout a single token.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/release-engineering/scripts/version-bump-from-git.sh"
CHANGELOG="skills/release-engineering/scripts/changelog-from-git.sh"
LIB="skills/release-engineering/scripts/conventional-commits-lib.sh"

# Writes the subjects to a line-per-record file and prints its path.
_subjects_file() {
  local wd
  wd="$(mk_tmpworkdir)"
  printf '%s\n' "$@" > "$wd/subjects.txt"
  printf '%s\n' "$wd/subjects.txt"
}

# --- aggregation ----------------------------------------------------------
@test "aggregate: 3x fix + 1x feat resolves to minor, not patch" {
  local f
  f="$(_subjects_file 'fix: one' 'fix: two' 'feat: add thing' 'fix: three')"
  run_script "$SCRIPT" --file "$f"
  assert_success
  assert_output "minor"
}

@test "aggregate: a fix-only range is patch" {
  local f
  f="$(_subjects_file 'fix: one' 'fix: two')"
  run_script "$SCRIPT" --file "$f"
  assert_success
  assert_output "patch"
}

@test "aggregate: refactor and perf are patch" {
  local f
  f="$(_subjects_file 'refactor: tidy' 'perf: cache results')"
  run_script "$SCRIPT" --file "$f"
  assert_success
  assert_output "patch"
}

@test "aggregate: order does not matter — feat last or feat first is minor" {
  local a b
  a="$(_subjects_file 'feat: add thing' 'fix: one')"
  b="$(_subjects_file 'fix: one' 'feat: add thing')"
  run_script "$SCRIPT" --file "$a"
  assert_success
  assert_output "minor"
  run_script "$SCRIPT" --file "$b"
  assert_success
  assert_output "minor"
}

# --- breaking-change detection, both forms, any type ----------------------
@test "breaking: header ! on feat is major" {
  local f
  f="$(_subjects_file 'fix: one' 'feat!: drop v1 endpoints')"
  run_script "$SCRIPT" --file "$f"
  assert_success
  assert_output "major"
}

@test "breaking: header ! on fix is major — the rule is not keyed off feat" {
  local f
  f="$(_subjects_file 'fix!: change the return type')"
  run_script "$SCRIPT" --file "$f"
  assert_success
  assert_output "major"
}

@test "breaking: a BREAKING CHANGE footer alone is major" {
  local wd
  wd="$(mk_tmpworkdir)"
  printf 'feat: rework auth\n\nBREAKING CHANGE: callers must migrate.\n\0' \
    > "$wd/records.bin"
  run_script "$SCRIPT" --file "$wd/records.bin"
  assert_success
  assert_output "major"
}

@test "breaking: a footer on a silent type still escalates to major" {
  local wd
  wd="$(mk_tmpworkdir)"
  printf 'chore: retire the shim\n\nBREAKING CHANGE: callers must migrate.\n\0' \
    > "$wd/records.bin"
  run_script "$SCRIPT" --file "$wd/records.bin"
  assert_success
  assert_output "major"
}

@test "breaking: the hyphenated BREAKING-CHANGE spelling is accepted" {
  local wd
  wd="$(mk_tmpworkdir)"
  printf 'fix: tidy up\n\nBREAKING-CHANGE: signature moved.\n\0' > "$wd/records.bin"
  run_script "$SCRIPT" --file "$wd/records.bin"
  assert_success
  assert_output "major"
}

@test "breaking: lowercase prose is not a footer" {
  local wd
  wd="$(mk_tmpworkdir)"
  printf 'feat: add thing\n\nbut this is a breaking change: not really\n\0' \
    > "$wd/records.bin"
  run_script "$SCRIPT" --file "$wd/records.bin"
  assert_success
  assert_output "minor"
}

# --- the no-bump verdict --------------------------------------------------
@test "none: a silent-type-only range succeeds with none, not an error" {
  local f
  f="$(_subjects_file 'docs: readme' 'chore: deps' 'test: coverage' 'ci: pipeline')"
  run_script "$SCRIPT" --file "$f"
  assert_success
  assert_output "none"
}

@test "none: non-conventional commits alone do not bump" {
  local f
  f="$(_subjects_file "Merge branch 'main'" 'wip')"
  run_script "$SCRIPT" --file "$f"
  assert_success
  assert_output "none"
}

# --- git range mode -------------------------------------------------------
_range_repo() {
  mk_git_fixture --branch main \
    --file 'a.txt:1\n' --commit 'chore: scaffold' \
    --file 'b.txt:1\n' --commit 'fix: resolve crash on empty input' \
    --file 'c.txt:1\n' --commit 'docs: update README' \
    --file 'd.txt:1\n' --commit 'feat(api): add endpoint'
}

@test "git range: an empty range is none" {
  local repo
  repo="$(_range_repo)"
  run_script_env --cwd "$repo" -- "$SCRIPT" "HEAD..HEAD"
  assert_success
  assert_output "none"
}

@test "git range: a single-commit range reports that commit's bump" {
  local repo base
  repo="$(_range_repo)"
  base="$(git -C "$repo" rev-parse HEAD~1)"
  run_script_env --cwd "$repo" -- "$SCRIPT" "${base}..HEAD"
  assert_success
  assert_output "minor"
}

@test "git range: a multi-commit range aggregates to the highest severity" {
  local repo base
  repo="$(_range_repo)"
  base="$(git -C "$repo" rev-parse HEAD~3)"
  run_script_env --cwd "$repo" -- "$SCRIPT" "${base}..HEAD"
  assert_success
  assert_output "minor"
}

@test "git range: a footer in a real commit body is seen" {
  local repo base
  repo="$(mk_git_fixture --branch main \
        --file 'a.txt:1\n' --commit 'chore: scaffold' \
        --file 'b.txt:1\n' --commit 'fix: tidy' \
        --file 'c.txt:1\n' --commit $'chore: retire shim\n\nBREAKING CHANGE: migrate.')"
  base="$(git -C "$repo" rev-parse HEAD~2)"
  run_script_env --cwd "$repo" -- "$SCRIPT" "${base}..HEAD"
  assert_success
  assert_output "major"
}

@test "git range: --repo targets a repo outside the cwd" {
  local repo base
  repo="$(_range_repo)"
  base="$(git -C "$repo" rev-parse HEAD~3)"
  run_script "$SCRIPT" "${base}..HEAD" --repo "$repo"
  assert_success
  assert_output "minor"
}

# --- agreement with the changelog generator -------------------------------
# Risk 2 from the plan: if the two scripts disagree about what counts as
# breaking, the release ships a MAJOR whose notes never mention the break.
@test "agreement: every commit the bump calls breaking is marked BREAKING in the changelog" {
  local repo base
  repo="$(mk_git_fixture --branch main \
        --file 'a.txt:1\n' --commit 'chore: scaffold' \
        --file 'b.txt:1\n' --commit 'fix: tidy' \
        --file 'c.txt:1\n' --commit $'chore: retire shim\n\nBREAKING CHANGE: migrate.')"
  base="$(git -C "$repo" rev-parse HEAD~2)"

  run_script_env --cwd "$repo" -- "$SCRIPT" "${base}..HEAD"
  assert_success
  assert_output "major"

  run_script_env --cwd "$repo" -- "$CHANGELOG" "${base}..HEAD"
  assert_success
  assert_output --partial "BREAKING"
  assert_output --partial "retire shim"
}

# --- --explain ------------------------------------------------------------
@test "explain: the breakdown goes to stderr and stdout stays one token" {
  local f
  f="$(_subjects_file 'fix: one' 'feat: add thing')"
  run_script_env --separate-stderr -- "$SCRIPT" --file "$f" --explain
  assert_success
  assert_output "minor"
  [[ "$stderr" == *"add thing"* ]]
  [[ "$stderr" == *"minor"* ]]
}

# --- failure / exit-code --------------------------------------------------
@test "failure: no --file and no git range exits 1" {
  run_script "$SCRIPT"
  assert_failure 1
}

@test "failure: --file pointing to a non-existent file exits 1" {
  run_script "$SCRIPT" --file "/tmp/does-not-exist-xy12"
  assert_failure 1
}

@test "failure: a range with unsafe characters is rejected" {
  run_script "$SCRIPT" 'v1.0.0..HEAD; rm -rf /'
  assert_failure 1
}

# --- shared library units -------------------------------------------------
@test "lib: cc_bump_max keeps the more severe of two bumps" {
  run_script_env --source "$LIB" -- cc_bump_max patch minor
  assert_success
  assert_output "minor"
  run_script_env --source "$LIB" -- cc_bump_max major patch
  assert_success
  assert_output "major"
  run_script_env --source "$LIB" -- cc_bump_max none patch
  assert_success
  assert_output "patch"
}

@test "lib: an unknown bump token never wins the aggregation" {
  run_script_env --source "$LIB" -- cc_bump_max patch bogus
  assert_success
  assert_output "patch"
}

@test "lib: a breaking commit of a silent type is never suppressed" {
  run_script_env --source "$LIB" -- cc_classify_section chore 0
  assert_success
  assert_output ""
  run_script_env --source "$LIB" -- cc_classify_section chore 1
  assert_success
  assert_output "Changed"
}

# --- self-test smoke (NON-counting) ---------------------------------------
@test "contract: --self-test passes (smoke)" {
  run_script "$SCRIPT" --self-test
  assert_success
  assert_output --partial "PASS"
}
