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
