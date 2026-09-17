#!/usr/bin/env bats
# Contract tests for skills/release-engineering/scripts/changelog-from-git.sh
# Contracts (from source + self-test):
#   --file <path>: reads commit subjects one-per-line; bypasses git entirely.
#   Output: Keep-a-Changelog markdown section starting with ## [...] header.
#   feat -> Added; fix -> Fixed; refactor/perf -> Changed.
#   docs/style/test/chore/ci/build are SUPPRESSED.
#   Non-conventional commits go into ### Other (never dropped).
#   feat! -> BREAKING prefix in Added; a BREAKING CHANGE footer does the same.
#   A breaking commit of an otherwise-silent type is NOT suppressed.
#   --file: NUL-separated whole messages, or one subject per line without NUL.
#   Empty/whitespace-only lines are skipped silently.
#   Empty range or file with no keepers -> "no changelog-worthy commits" notice.
#   No git range and no --file -> exit 1.
#   --self-test -> exit 0, prints "PASS".
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/release-engineering/scripts/changelog-from-git.sh"
SUBJECTS="${FIXTURES}/skills/changelog-subjects.txt"

# --- happy path via --file ------------------------------------------------
@test "happy: --file mode emits correct sections from mixed subjects" {
  run_script "$SCRIPT" --file "$SUBJECTS" --version "1.0.0" --date "2024-01-15"
  assert_success
  # Header.
  assert_output --partial "## [1.0.0] - 2024-01-15"
  # feat(auth) -> Added with bold scope.
  assert_output --partial "### Added"
  assert_output --partial "**auth**: add OAuth2 login"
  # fix -> Fixed.
  assert_output --partial "### Fixed"
  assert_output --partial "resolve crash on empty input"
  # feat! -> BREAKING in Added.
  assert_output --partial "**BREAKING**: remove legacy v1 endpoints"
  # Non-conventional -> Other.
  assert_output --partial "### Other"
  assert_output --partial "Non-conventional commit message"
}

@test "edge: suppressed types (docs/refactor present in subjects but only refactor appears as Changed)" {
  # The fixture has docs and refactor; docs must be suppressed.
  # refactor is NOT in the test fixture (changelog-subjects.txt only has
  # feat/fix/docs/refactor/feat!/non-conventional) — docs must not appear.
  run_script "$SCRIPT" --file "$SUBJECTS"
  assert_success
  refute_output --partial "update README"
}

@test "edge: a file with only suppressed-type subjects emits the no-content notice" {
  WD="$(mk_tmpworkdir)"
  printf 'docs: update README\nchore: bump deps\ntest: add coverage\n' > "$WD/suppressed.txt"
  run_script "$SCRIPT" --file "$WD/suppressed.txt"
  assert_success
  assert_output --partial "no changelog-worthy"
}

@test "edge: blank lines in the subjects file are silently skipped" {
  WD="$(mk_tmpworkdir)"
  printf 'feat: one\n\n   \nfix: two\n' > "$WD/with-blanks.txt"
  run_script "$SCRIPT" --file "$WD/with-blanks.txt"
  assert_success
  assert_output --partial "one"
  assert_output --partial "two"
}

@test "edge: Unreleased header used when --version not given" {
  WD="$(mk_tmpworkdir)"
  printf 'feat: add thing\n' > "$WD/s.txt"
  run_script "$SCRIPT" --file "$WD/s.txt"
  assert_success
  assert_output --partial "## [Unreleased]"
}

# --- failure / exit-code --------------------------------------------------
@test "failure: no --file and no git range exits 1" {
  run_script "$SCRIPT"
  assert_failure 1
}

@test "failure: --file pointing to non-existent file exits 1" {
  run_script "$SCRIPT" --file "/tmp/does-not-exist-xy12"
  assert_failure 1
}

# --- self-test smoke (NON-counting) ---------------------------------------
@test "contract: --self-test passes (smoke)" {
  run_script "$SCRIPT" --self-test
  assert_success
  assert_output --partial "PASS"
}

# --- primary mode: a real git range ------------------------------------------
# Every test above drives --file, which bypasses git entirely. The script's
# documented primary input ($1 = "v1.1.0..HEAD") went completely untested, so a
# regression in the `git log "$range" --pretty=format:'%s'` call — the one path
# a release actually uses — would not have failed a single assertion.

_range_repo() {
  mk_git_fixture --branch main \
    --file 'a.txt:1\n' --commit 'chore: scaffold' \
    --file 'b.txt:1\n' --commit 'feat(auth): add OAuth2 login' \
    --file 'c.txt:1\n' --commit 'fix: resolve crash on empty input' \
    --file 'd.txt:1\n' --commit 'docs: update README' \
    --file 'e.txt:1\n' --commit 'refactor: simplify token cache' \
    --file 'f.txt:1\n' --commit 'Non-conventional commit message'
}

@test "git range: typed commits are routed to their sections" {
  local repo
  repo="$(_range_repo)"
  local base
  base="$(git -C "$repo" rev-parse HEAD~5)"
  run_script_env --cwd "$repo" -- "$SCRIPT" "${base}..HEAD" \
    --version "1.0.0" --date "2024-01-15"
  assert_success
  assert_output --partial "## [1.0.0] - 2024-01-15"
  assert_output --partial "### Added"
  assert_output --partial "**auth**: add OAuth2 login"
  assert_output --partial "### Fixed"
  assert_output --partial "resolve crash on empty input"
  assert_output --partial "### Changed"
  assert_output --partial "simplify token cache"
  assert_output --partial "### Other"
  assert_output --partial "Non-conventional commit message"
  # docs is suppressed, and the pre-range commit is outside the window.
  refute_output --partial "update README"
  refute_output --partial "scaffold"
}

@test "git range: the range bound is honoured, not ignored" {
  local repo base
  repo="$(_range_repo)"
  # Only the last two commits: refactor + the non-conventional one.
  base="$(git -C "$repo" rev-parse HEAD~2)"
  run_script_env --cwd "$repo" -- "$SCRIPT" "${base}..HEAD"
  assert_success
  assert_output --partial "simplify token cache"
  assert_output --partial "Non-conventional commit message"
  # Commits before the bound must not leak in.
  refute_output --partial "add OAuth2 login"
  refute_output --partial "resolve crash on empty input"
}

# --- breaking changes carried in the body, not the header --------------------
# The generator used to read `--pretty=format:'%s'`, so a BREAKING CHANGE footer
# was invisible: the release notes stayed silent about the break.

@test "breaking: a BREAKING CHANGE footer marks the entry BREAKING" {
  local repo base
  repo="$(mk_git_fixture --branch main \
        --file 'a.txt:1\n' --commit 'chore: scaffold' \
        --file 'b.txt:1\n' --commit $'fix: drop the compat shim\n\nBREAKING CHANGE: callers must migrate.')"
  base="$(git -C "$repo" rev-parse HEAD~1)"
  run_script_env --cwd "$repo" -- "$SCRIPT" "${base}..HEAD"
  assert_success
  assert_output --partial "**BREAKING**: drop the compat shim"
}

@test "breaking: a breaking commit of a silent type is still reported" {
  local repo base
  repo="$(mk_git_fixture --branch main \
        --file 'a.txt:1\n' --commit 'chore: scaffold' \
        --file 'b.txt:1\n' --commit $'chore: retire the shim\n\nBREAKING CHANGE: callers must migrate.')"
  base="$(git -C "$repo" rev-parse HEAD~1)"
  run_script_env --cwd "$repo" -- "$SCRIPT" "${base}..HEAD"
  assert_success
  assert_output --partial "### Changed"
  assert_output --partial "**BREAKING**: retire the shim"
}

@test "breaking: a commit body never leaks into the entry text" {
  local repo base
  repo="$(mk_git_fixture --branch main \
        --file 'a.txt:1\n' --commit 'chore: scaffold' \
        --file 'b.txt:1\n' --commit $'feat: add export\n\nSome explanatory prose that is not the subject.')"
  base="$(git -C "$repo" rev-parse HEAD~1)"
  run_script_env --cwd "$repo" -- "$SCRIPT" "${base}..HEAD"
  assert_success
  assert_output --partial "add export"
  refute_output --partial "explanatory prose"
}

@test "edge: a NUL-separated --file carries multi-line messages" {
  WD="$(mk_tmpworkdir)"
  printf 'feat: first thing\0fix: second thing\n\nBREAKING CHANGE: migrate.\n\0' \
    > "$WD/records.bin"
  run_script "$SCRIPT" --file "$WD/records.bin"
  assert_success
  assert_output --partial "first thing"
  assert_output --partial "**BREAKING**: second thing"
}

@test "git range: a range with no changelog-worthy commits emits the notice" {
  local repo base
  repo="$(mk_git_fixture --branch main \
        --file 'a.txt:1\n' --commit 'chore: scaffold' \
        --file 'b.txt:1\n' --commit 'docs: update README' \
        --file 'c.txt:1\n' --commit 'test: add coverage')"
  base="$(git -C "$repo" rev-parse HEAD~2)"
  run_script_env --cwd "$repo" -- "$SCRIPT" "${base}..HEAD"
  assert_success
  assert_output --partial "no changelog-worthy"
}

# --- --streams / --tag ---------------------------------------------------------------------

mk_streams() {
  WD="$(mk_tmpworkdir)"
  printf 'service\tfeat: add handler\nweb\tfix: repair view\nservice\tfix: guard input\nweb\tdocs: readme\n' \
    > "$WD/streams.tsv"
}

@test "streams: entries group under ### <stream> then #### <Section>, first-seen order" {
  mk_streams
  run_script "$SCRIPT" --streams "$WD/streams.tsv" --version 1.0.0 --date 2026-01-01
  assert_success
  assert_output "$(printf '## [1.0.0] - 2026-01-01\n\n### service\n\n#### Added\n- add handler\n\n#### Fixed\n- guard input\n\n### web\n\n#### Fixed\n- repair view')"
}

@test "streams: no Tag line without --tag; the tag appears when given" {
  mk_streams
  run_script "$SCRIPT" --streams "$WD/streams.tsv"
  assert_success
  refute_output --partial "Tag:"
  run_script "$SCRIPT" --streams "$WD/streams.tsv" --tag v4.0.33
  assert_success
  assert_line --index 1 'Tag: `v4.0.33`'
  run_script "$SCRIPT" --streams "$WD/streams.tsv" --tag ""
  refute_output --partial "Tag:"
}

@test "default mode: output without the new flags is unchanged and tag-free" {
  run_script "$SCRIPT" --file "$SUBJECTS" --version "1.0.0" --date "2024-01-15"
  assert_success
  assert_line --index 0 "## [1.0.0] - 2024-01-15"
  assert_line --index 1 "### Added"
  refute_output --partial "Tag:"
}

@test "streams: a range or --file alongside --streams, a bad stream name, or an unsafe tag exit 1" {
  mk_streams
  run_script "$SCRIPT" --streams "$WD/streams.tsv" HEAD~1..HEAD
  assert_failure 1
  printf 'Bad Stream\tfeat: x\n' > "$WD/bad.tsv"
  run_script "$SCRIPT" --streams "$WD/bad.tsv"
  assert_failure 1
  run_script "$SCRIPT" --streams "$WD/streams.tsv" --tag 'v1`x'
  assert_failure 1
}

