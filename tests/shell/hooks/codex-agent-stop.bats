#!/usr/bin/env bats
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="hooks/codex-agent-stop.sh"

_write_state() {
  local wd="$1" stage="$2"
  mkdir -p "$wd/.context"
  jq -n --arg stage "$stage" '{version:2,facts:{dispatched_agents:[{agent_id:"agt_1",subagent_type:"corpflow:product-manager",task_id:"PL0",stage:$stage}]}}' > "$wd/.context/state.json"
}

@test "an unknown Codex agent is a fail-open no-op" {
  local wd; wd="$(mk_tmpworkdir)"; _write_state "$wd" PL
  run env BASE_PLUGIN_ROOT="$PLUGIN_ROOT" WORKSPACE_ROOT="$wd" \
    bash "$PLUGIN_ROOT/$SCRIPT" <<'JSON'
{"agent_id":"missing"}
JSON
  assert_success
  [ ! -e "$wd/.context/logs/audit.jsonl" ]
}

@test "a non-boundary stage is not routed to agent-stop" {
  local wd; wd="$(mk_tmpworkdir)"; _write_state "$wd" DV
  run env BASE_PLUGIN_ROOT="$PLUGIN_ROOT" WORKSPACE_ROOT="$wd" \
    bash "$PLUGIN_ROOT/$SCRIPT" <<'JSON'
{"agent_id":"agt_1"}
JSON
  assert_success
  [ ! -e "$wd/.context/logs/audit.jsonl" ]
}

@test "a planning agent is routed with its resolved type and stage" {
  local wd; wd="$(mk_tmpworkdir)"; _write_state "$wd" PL
  run env BASE_PLUGIN_ROOT="$PLUGIN_ROOT" WORKSPACE_ROOT="$wd" \
    bash "$PLUGIN_ROOT/$SCRIPT" <<'JSON'
{"agent_id":"agt_1","session_id":"sess_codex"}
JSON
  assert_success
  run jq -e 'select(.action == "stage_completion_hook" and .subject == "corpflow:product-manager" and .metadata.stage == "PL")' "$wd/.context/logs/audit.jsonl"
  assert_success
}

@test "malformed hook input cannot create a completion row" {
  local wd; wd="$(mk_tmpworkdir)"; _write_state "$wd" PL
  run env BASE_PLUGIN_ROOT="$PLUGIN_ROOT" WORKSPACE_ROOT="$wd" \
    bash "$PLUGIN_ROOT/$SCRIPT" <<'TEXT'
not-json
TEXT
  assert_success
  [ ! -e "$wd/.context/logs/audit.jsonl" ]
}
