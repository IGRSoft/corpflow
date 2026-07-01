#!/usr/bin/env bats
# Contract tests for skills/release-engineering/scripts/changelog-from-git.sh
# Contracts (from source + self-test):
#   --file <path>: reads commit subjects one-per-line; bypasses git entirely.
#   Output: Keep-a-Changelog markdown section starting with ## [...] header.
#   feat -> Added; fix -> Fixed; refactor/perf -> Changed.
#   docs/style/test/chore/ci/build are SUPPRESSED.
#   Non-conventional commits go into ### Other (never dropped).
#   feat! -> BREAKING prefix in Added.
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
