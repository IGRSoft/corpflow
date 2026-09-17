#!/usr/bin/env bats
# Contract tests for skills/worktask/scripts/ledger-digest.sh.
# Contracts (from header):
#   - stdout is exactly six `key: value` lines, this order: ledger, run_index,
#     ready, in_progress, blocked, open_blocking_questions — never JSON.
#   - the first line is always the literal `ledger: .context/state.json`,
#     regardless of the --state path actually read.
#   - ready/in_progress/blocked render `none` when their category is empty.
#   - open_blocking_questions counts blocks_next_stage==true entries whose
#     status is anything but "resolved" (a missing status counts as open).
#   - exit 3 on a missing or unparseable ledger; exit 2 on a usage error.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/scripts/ledger-digest.sh"

setup() {
  WD="$(mk_tmpworkdir)"
}

@test "happy: mixed ledger renders ready/in_progress/blocked in this order" {
  cat > "$WD/ledger-mixed.json" <<'EOF'
{
  "run_index": 2,
  "tasks": {
    "PL0": { "status": "completed" },
    "DV0": { "status": "pending", "blocked_by": ["PL0"] },
    "DV1": { "status": "pending", "blocked_by": ["PL0", "DV0"] },
    "DR0": { "status": "in_progress" },
    "QA0": { "status": "blocked" }
  },
  "facts": { "open_questions": [] }
}
EOF
  run_script_env --separate-stderr -- "$SCRIPT" --state "$WD/ledger-mixed.json"
  assert_success
  [ "$status" -eq 0 ]
  local expected
  expected=$'ledger: .context/state.json\nrun_index: 2\nready: DV0\nin_progress: DR0\nblocked: QA0\nopen_blocking_questions: 0'
  assert_equal "$output" "$expected"
  assert_equal "$stderr" ""
}

@test "happy: every category empty renders 'none', not a blank value" {
  cat > "$WD/ledger-empty.json" <<'EOF'
{
  "run_index": 0,
  "tasks": { "PL0": { "status": "completed" } },
  "facts": { "open_questions": [] }
}
EOF
  run_script_env --separate-stderr -- "$SCRIPT" --state "$WD/ledger-empty.json"
  assert_success
  local expected
  expected=$'ledger: .context/state.json\nrun_index: 0\nready: none\nin_progress: none\nblocked: none\nopen_blocking_questions: 0'
  assert_equal "$output" "$expected"
}

@test "happy: open_blocking_questions counts open+missing status, excludes resolved and non-blocking" {
  cat > "$WD/ledger-obq.json" <<'EOF'
{
  "run_index": 1,
  "tasks": { "PL0": { "status": "completed" } },
  "facts": {
    "open_questions": [
      { "id": "sw-PL0-1", "blocks_next_stage": true, "status": "open" },
      { "id": "sw-PL0-2", "blocks_next_stage": true },
      { "id": "sw-PL0-3", "blocks_next_stage": true, "status": "resolved" },
      { "id": "sw-PL0-4", "blocks_next_stage": false, "status": "open" }
    ]
  }
}
EOF
  run_script_env --separate-stderr -- "$SCRIPT" --state "$WD/ledger-obq.json"
  assert_success
  assert_line "open_blocking_questions: 2"
}

@test "failure: a missing ledger path exits 3 with a stderr message and no stdout" {
  run_script_env --separate-stderr -- "$SCRIPT" --state "$WD/does-not-exist.json"
  assert_failure 3
  assert_output ""
  [ -n "$stderr" ]
}

@test "failure: an unparseable ledger exits 3" {
  printf 'not json at all {' > "$WD/ledger-bad.json"
  run_script_env --separate-stderr -- "$SCRIPT" --state "$WD/ledger-bad.json"
  assert_failure 3
  assert_output ""
}

@test "usage: an unknown flag exits 2" {
  run_script_env --separate-stderr -- "$SCRIPT" --bogus
  assert_failure 2
}

@test "usage: --state with no value exits 2" {
  run_script_env --separate-stderr -- "$SCRIPT" --state
  assert_failure 2
}

@test "the first line stays the literal pointer even when --state reads elsewhere" {
  mkdir -p "$WD/elsewhere/nested"
  cat > "$WD/elsewhere/nested/other-ledger.json" <<'EOF'
{
  "run_index": 5,
  "tasks": {},
  "facts": { "open_questions": [] }
}
EOF
  run_script_env --separate-stderr -- "$SCRIPT" --state "$WD/elsewhere/nested/other-ledger.json"
  assert_success
  [ "${lines[0]}" = "ledger: .context/state.json" ]
}
