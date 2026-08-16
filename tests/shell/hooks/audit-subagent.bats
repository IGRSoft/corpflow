#!/usr/bin/env bats
# Tests for hooks/audit-subagent.sh (DV0c) — SubagentStop → audit.jsonl writer
# emitting a `subagent_stopped` row with dedupe_key "<session>:<agent>:stop".
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="hooks/audit-subagent.sh"
PAYLOAD="${FIXTURES}/hooks/audit-subagent.payload.json"

setup() {
  WD="$(mk_tmpworkdir)"
}

@test "happy: writes subagent_stopped row with duration + dedupe keys" {
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" < "$PAYLOAD"
  assert_success
  run jq -e '
    .action == "subagent_stopped"
    and .subject == "corpflow:developer"
    and .metadata.duration_ms == 12345
    and .metadata.parent_agent_id == "agt_parent"
    and (.metadata.dedupe_key == "sess_fix:agt_dv:stop")
  ' "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "edge: non-numeric duration_ms coerces to 0; absent ids fall back" {
  run env CLAUDE_PROJECT_DIR="$WD" \
    bash "$PLUGIN_ROOT/$SCRIPT" <<< '{"agent_type":"corpflow:y","duration_ms":"oops"}'
  assert_success
  run jq -e '
    .metadata.duration_ms == 0
    and (.metadata.dedupe_key == "nosession:noagent:stop")
    and .metadata.parent_agent_id == "none"
  ' "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "happy: stage is stamped from CLAUDE_TASK_METADATA_STAGE" {
  run env CLAUDE_PROJECT_DIR="$WD" CLAUDE_TASK_METADATA_STAGE=DV \
    bash "$PLUGIN_ROOT/$SCRIPT" < "$PAYLOAD"
  assert_success
  run jq -e '.metadata.stage == "DV" and .metadata.agent_id == "agt_dv"' \
    "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "edge: empty agent_type falls back to CLAUDE_SUBAGENT_TYPE, qualifier intact" {
  # The runtime sends "" (not null) for plugin agents, so `// "unknown"` alone
  # left the row anonymous and the report could not name who ran.
  run env CLAUDE_PROJECT_DIR="$WD" CLAUDE_SUBAGENT_TYPE="apple-developer:ios-developer" \
    bash "$PLUGIN_ROOT/$SCRIPT" <<< '{"agent_type":"","agent_id":"a1","session_id":"s1"}'
  assert_success
  run jq -e '.subject == "apple-developer:ios-developer"' "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "edge: empty agent_type with no env fallback yields unknown, not empty" {
  run env CLAUDE_PROJECT_DIR="$WD" -u CLAUDE_SUBAGENT_TYPE -u CLAUDE_TASK_METADATA_STAGE \
    bash "$PLUGIN_ROOT/$SCRIPT" <<< '{"agent_type":"","agent_id":"a1","session_id":"s1"}'
  assert_success
  run jq -e '.subject == "unknown" and .metadata.stage == "unknown"' \
    "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "failure: malformed JSON exits 0 and writes no row" {
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< '{broken'
  assert_success
  [ ! -s "$WD/.context/logs/audit.jsonl" ]
}

@test "contract: --self-test passes (smoke, NON-counting)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "self-test OK"
}
