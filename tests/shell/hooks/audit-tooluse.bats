#!/usr/bin/env bats
# Tests for hooks/audit-tooluse.sh (DV0c) — PostToolUse → audit.jsonl writer
# emitting a `tool_invoked` row keyed "<session>:<tool_use_id>".
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="hooks/audit-tooluse.sh"
PAYLOAD="${FIXTURES}/hooks/audit-tooluse.payload.json"

setup() {
  WD="$(mk_tmpworkdir)"
}

@test "happy: writes tool_invoked row with tool, duration, effort, dedupe_key" {
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" < "$PAYLOAD"
  assert_success
  run jq -e '
    .action == "tool_invoked"
    and .subject == "Write"
    and .metadata.kind == "tool"
    and .metadata.duration_ms == 42
    and .metadata.effort == "medium"
    and (.metadata.dedupe_key == "sess_fix:toolu_fix")
  ' "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "edge: --kind override and absent ids fall back to placeholders" {
  # Pin CLAUDE_EFFORT OFF so the placeholder is deterministic regardless of ambient env:
  # the script falls back .effort.level // env.CLAUDE_EFFORT // "unknown", so with no
  # .effort in the payload and CLAUDE_EFFORT unset the placeholder is "unknown".
  run env -u CLAUDE_EFFORT CLAUDE_PROJECT_DIR="$WD" \
    bash "$PLUGIN_ROOT/$SCRIPT" --kind mcp <<< '{"tool_name":"X"}'
  assert_success
  run jq -e '
    .metadata.kind == "mcp"
    and .metadata.duration_ms == 0
    and .metadata.effort == "unknown"
    and (.metadata.dedupe_key == "nosession:notoolid")
  ' "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "ledger: a state-patch status call is audited with task_id and status" {
  # The stage-transition trail resume depends on: this Bash call is the ONLY signal
  # that a stage advanced.
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< '{"tool_name":"Bash","tool_input":{"command":"bash skills/worktask/scripts/state-patch.sh --task-status DV1 in_progress"},"tool_use_id":"t1","duration_ms":10,"session_id":"s1","effort":{"level":"high"}}'
  assert_success
  run jq -e '.subject == "state-patch" and .metadata.task_id == "DV1"
             and .metadata.status == "in_progress"' "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "ledger: an ordinary Bash call writes NO row" {
  # Widening the matcher to all of Bash must not turn the audit log into shell noise.
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< '{"tool_name":"Bash","tool_input":{"command":"ls -la"},"tool_use_id":"t2","duration_ms":5,"session_id":"s1"}'
  assert_success
  [ ! -s "$WD/.context/logs/audit.jsonl" ]
}

@test "ledger: a non-status state-patch call still audits, without task fields" {
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< '{"tool_name":"Bash","tool_input":{"command":"bash skills/worktask/scripts/state-patch.sh --task-create QA0 --metadata {}"},"tool_use_id":"t4","duration_ms":9,"session_id":"s1"}'
  assert_success
  run jq -e '.subject == "state-patch" and (.metadata | has("task_id") | not)' \
    "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "failure: malformed JSON exits 0 and writes no row" {
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< 'xxx'
  assert_success
  [ ! -s "$WD/.context/logs/audit.jsonl" ]
}

@test "contract: --self-test passes (smoke, NON-counting)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "self-test OK"
}
