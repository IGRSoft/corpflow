#!/usr/bin/env bats
# Tests for hooks/agent-stop.sh (DV0c) — Stop-event multiplexer that writes a
# canonical `stage_completion_hook` row to .context/logs/audit.jsonl.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="hooks/agent-stop.sh"
PAYLOAD="${FIXTURES}/hooks/agent-stop.payload.json"

setup() {
  WD="$(mk_tmpworkdir)"
}

@test "happy: appends a stage_completion_hook row with stage + dedupe keys" {
  run env CLAUDE_PROJECT_DIR="$WD" \
    bash "$PLUGIN_ROOT/$SCRIPT" --stage DV < "$PAYLOAD"
  assert_success
  [ -f "$WD/.context/logs/audit.jsonl" ]
  run jq -e '
    .action == "stage_completion_hook"
    and .subject == "corpflow:product-manager"
    and .metadata.stage == "DV"
    and .metadata.background_tasks_count == 2
    and .metadata.background_task_ids == ["bg1","bg2"]
    and .metadata.session_crons_count == 1
    and (.metadata.dedupe_key == "sess_fix:agt_pl:stage:DV")
  ' "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "edge: missing optional fields default safely (stage=unknown, none parent)" {
  run env CLAUDE_PROJECT_DIR="$WD" \
    bash "$PLUGIN_ROOT/$SCRIPT" <<< '{"agent_type":"corpflow:x"}'
  assert_success
  run jq -e '
    .metadata.stage == "unknown"
    and .metadata.parent_agent_id == "none"
    and .metadata.background_tasks_count == 0
    and (.metadata.dedupe_key == "nosession:noagent:stage:unknown")
  ' "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "failure: malformed JSON payload does not crash (exit 0, no row written)" {
  run env CLAUDE_PROJECT_DIR="$WD" \
    bash "$PLUGIN_ROOT/$SCRIPT" --stage DV <<< 'not-json'
  # Hook swallows jq parse failure and exits 0 (must not block transition).
  assert_success
  [ ! -s "$WD/.context/logs/audit.jsonl" ]
}

@test "contract: --self-test passes (smoke, NON-counting)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "self-test OK"
}
