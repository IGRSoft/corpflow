#!/usr/bin/env bats
# Contract tests for skills/self-improvement/scripts/detect-user-changes.sh
# Contracts (from source):
#   Requires DIFF_OUT and LOG_OUT env vars (missing -> exit 1 via :?).
#   With an explicit SHA hint resolves to that baseline.
#   Emits per-file TSV (path\tadded\tremoved) to stdout from a single diff of the
#   baseline against the working tree (which already covers staged + unstaged).
#   Writes full unified diff to $DIFF_OUT.
#   Writes run log header (with baseline SHA line) to $LOG_OUT.
#   Exit code 0 on success; 1 on git/env error; 2 on unresolvable baseline.
#   Excludes .context/logs/** and skills/self-improvement/** from the diff surface.
#
# The counts and the hunk body are asserted, not merely the presence of a
# filename: `assert_output --partial "file.txt"` passed for any TSV row about
# that path — including 0 added / 0 removed — and `[ -f "$DIFF_OUT" ]` passed for
# an empty file, so the diff surface itself was never checked.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/self-improvement/scripts/detect-user-changes.sh"

setup() {
  WD="$(mk_git_fixture --branch main \
        --file 'file.txt:one\ntwo\nthree\n' \
        --file 'keep.txt:untouched\n' \
        --commit 'init')"
  DIFF_OUT="$WD/diff.patch"
  LOG_OUT="$WD/run.log"
  export DIFF_OUT LOG_OUT
  BASE_SHA="$(git -C "$WD" rev-parse HEAD)"
}

# --- happy path -----------------------------------------------------------
@test "happy: committed edits produce exact added/removed counts per file" {
  # two lines added, one removed, in one committed change.
  printf 'one\ntwo-edited\nthree\nfour\nfive\n' > "$WD/file.txt"
  git -C "$WD" -c user.name=t -c user.email=t@t commit -qam "user: edit"
  run_script_env --cwd "$WD" --env "DIFF_OUT=$DIFF_OUT" --env "LOG_OUT=$LOG_OUT" \
    -- "$SCRIPT" "$BASE_SHA"
  assert_success
  # path <TAB> added <TAB> removed — 3 added (two-edited, four, five), 1 removed.
  assert_output "$(printf 'file.txt\t3\t1')"
  refute_output --partial "keep.txt"
}

@test "an uncommitted edit is tallied exactly once" {
  # R4-DV2: `git diff "$BASELINE"` already diffs the baseline against the WORKING
  # TREE, so it covers uncommitted edits. A second bare `git diff` used to be
  # unioned on top, reporting this single 1-line insertion as 2 added.
  printf 'one\ntwo\nthree\nfour\n' > "$WD/file.txt"
  run_script_env --cwd "$WD" --env "DIFF_OUT=$DIFF_OUT" --env "LOG_OUT=$LOG_OUT" \
    -- "$SCRIPT" "$BASE_SHA"
  assert_success
  assert_output "$(printf 'file.txt\t1\t0')"
}

@test "an uncommitted edit appears once in DIFF_OUT, not as a repeated hunk" {
  # The double-diff also duplicated the PATCH body, not just the counts — a
  # separate observable, so a regression in either half is caught on its own.
  printf 'one\ntwo\nthree\nfour\n' > "$WD/file.txt"
  run_script_env --cwd "$WD" --env "DIFF_OUT=$DIFF_OUT" --env "LOG_OUT=$LOG_OUT" \
    -- "$SCRIPT" "$BASE_SHA"
  assert_success
  run grep -c '^diff --git a/file.txt b/file.txt' "$DIFF_OUT"
  assert_output "1"
  run grep -c '^+four$' "$DIFF_OUT"
  assert_output "1"
}

@test "a staged-but-uncommitted edit is also tallied exactly once" {
  # Staging is the case where the two diffs used to disagree rather than merely
  # duplicate; `git diff <baseline>` still covers it, a bare `git diff` does not.
  printf 'one\ntwo\nthree\nfour\n' > "$WD/file.txt"
  git -C "$WD" add file.txt
  run_script_env --cwd "$WD" --env "DIFF_OUT=$DIFF_OUT" --env "LOG_OUT=$LOG_OUT" \
    -- "$SCRIPT" "$BASE_SHA"
  assert_success
  assert_output "$(printf 'file.txt\t1\t0')"
}

@test "happy: DIFF_OUT carries the actual unified hunk, not just a header" {
  printf 'one\ntwo-edited\nthree\n' > "$WD/file.txt"
  git -C "$WD" -c user.name=t -c user.email=t@t commit -qam "user: edit"
  run_script_env --cwd "$WD" --env "DIFF_OUT=$DIFF_OUT" --env "LOG_OUT=$LOG_OUT" \
    -- "$SCRIPT" "$BASE_SHA"
  assert_success
  [ -s "$DIFF_OUT" ]
  run cat "$DIFF_OUT"
  assert_output --partial "diff --git a/file.txt b/file.txt"
  assert_output --partial "@@"
  assert_output --partial "-two"
  assert_output --partial "+two-edited"
  # An untouched file must not appear in the diff surface at all.
  refute_output --partial "keep.txt"
}

@test "edge: excluded paths are absent from both the TSV and the diff" {
  mkdir -p "$WD/.context/logs" "$WD/skills/self-improvement"
  printf 'noise\n' > "$WD/.context/logs/audit.jsonl"
  printf 'noise\n' > "$WD/skills/self-improvement/notes.md"
  printf 'one\ntwo\nthree\nfour\n' > "$WD/file.txt"
  run_script_env --cwd "$WD" --env "DIFF_OUT=$DIFF_OUT" --env "LOG_OUT=$LOG_OUT" \
    -- "$SCRIPT" "$BASE_SHA"
  assert_success
  refute_output --partial ".context/logs"
  refute_output --partial "skills/self-improvement"
  # The un-excluded edit is still reported, so the exclusion is not a blanket no-op.
  assert_output --partial "file.txt"
  run cat "$DIFF_OUT"
  refute_output --partial "audit.jsonl"
}

@test "edge: no changes since the baseline yields an empty table and empty diff" {
  run_script_env --cwd "$WD" --env "DIFF_OUT=$DIFF_OUT" --env "LOG_OUT=$LOG_OUT" \
    -- "$SCRIPT" "$BASE_SHA"
  assert_success
  assert_output ""
  [ -f "$DIFF_OUT" ]
  [ ! -s "$DIFF_OUT" ]
}

@test "edge: log header includes both baseline SHA and generation timestamp" {
  run_script_env --cwd "$WD" --env "DIFF_OUT=$DIFF_OUT" --env "LOG_OUT=$LOG_OUT" \
    -- "$SCRIPT" "$BASE_SHA"
  assert_success
  run grep "Baseline SHA:" "$LOG_OUT"
  assert_output --partial "$BASE_SHA"
  run grep "Generated:" "$LOG_OUT"
  assert_output --regexp '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z'
  run grep "Head:" "$LOG_OUT"
  assert_output --partial "$(git -C "$WD" rev-parse HEAD)"
}

# --- failure / exit-code --------------------------------------------------
@test "failure: missing DIFF_OUT exits 1 (env-var guard)" {
  run_script_env --cwd "$WD" --unset DIFF_OUT --env "LOG_OUT=$LOG_OUT" \
    --separate-stderr -- "$SCRIPT" "$BASE_SHA"
  assert_failure
  [[ "$stderr" == *"DIFF_OUT"* ]]
}

@test "failure: missing LOG_OUT exits 1 (env-var guard)" {
  run_script_env --cwd "$WD" --unset LOG_OUT --env "DIFF_OUT=$DIFF_OUT" \
    --separate-stderr -- "$SCRIPT" "$BASE_SHA"
  assert_failure
  [[ "$stderr" == *"LOG_OUT"* ]]
}
