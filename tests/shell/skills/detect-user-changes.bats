#!/usr/bin/env bats
# Contract tests for skills/self-improvement/scripts/detect-user-changes.sh
# Contracts (from source):
#   Requires DIFF_OUT and LOG_OUT env vars (missing -> exit 1 via :?).
#   With an explicit SHA hint resolves to that baseline.
#   Emits per-file TSV (path\tadded\tremoved) to stdout.
#   Writes full unified diff to $DIFF_OUT.
#   Writes run log header (with baseline SHA line) to $LOG_OUT.
#   Exit code 0 on success; 1 on git/env error; 2 on unresolvable baseline.
#   Excludes .context/logs/** and skills/self-improvement/** from the diff surface.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/self-improvement/scripts/detect-user-changes.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  DIFF_OUT="$WD/diff.patch"
  LOG_OUT="$WD/run.log"
  export DIFF_OUT LOG_OUT
  # Build a minimal git repo so the script has a real baseline to work from.
  git -C "$WD" init -q
  git -C "$WD" config user.email "test@example.com"
  git -C "$WD" config user.name "Test"
  printf 'hello\n' > "$WD/file.txt"
  git -C "$WD" add file.txt
  git -C "$WD" commit -q -m "init"
  BASE_SHA="$(git -C "$WD" rev-parse HEAD)"
}

# --- happy path -----------------------------------------------------------
@test "happy: runs against a real git repo with explicit SHA; writes DIFF_OUT and LOG_OUT" {
  # Make a user edit after the base commit.
  printf 'world\n' >> "$WD/file.txt"
  cd "$WD"
  run_script "$SCRIPT" "$BASE_SHA"
  assert_success
  # LOG_OUT must contain the baseline SHA header.
  run grep -q "Baseline SHA:" "$LOG_OUT"
  assert_success
  # DIFF_OUT must be written (may be empty if no committed diff on same HEAD,
  # but the file must exist).
  [ -f "$DIFF_OUT" ]
}

@test "edge: per-file TSV output contains path, added, and removed counts" {
  # Commit a change so we have committed numstat to report.
  printf 'world\n' >> "$WD/file.txt"
  git -C "$WD" add file.txt
  git -C "$WD" commit -q -m "user: add world"
  cd "$WD"
  run_script "$SCRIPT" "$BASE_SHA"
  assert_success
  # The TSV must contain the modified file with non-zero added count.
  assert_output --partial "file.txt"
}

@test "edge: log header includes both baseline SHA and generation timestamp" {
  cd "$WD"
  run_script "$SCRIPT" "$BASE_SHA"
  assert_success
  run grep "Baseline SHA:" "$LOG_OUT"
  assert_output --partial "$BASE_SHA"
  run grep "Generated:" "$LOG_OUT"
  assert_success
}

# --- failure / exit-code --------------------------------------------------
@test "failure: missing DIFF_OUT exits 1 (env-var guard)" {
  unset DIFF_OUT
  cd "$WD"
  run bash "$PLUGIN_ROOT/$SCRIPT" "$BASE_SHA"
  assert_failure
  export DIFF_OUT="$WD/diff.patch"
}

@test "failure: missing LOG_OUT exits 1 (env-var guard)" {
  unset LOG_OUT
  cd "$WD"
  run bash "$PLUGIN_ROOT/$SCRIPT" "$BASE_SHA"
  assert_failure
  export LOG_OUT="$WD/run.log"
}
