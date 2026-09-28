#!/usr/bin/env bats
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

ADAPTER="hooks/codex-adapter.sh"
CAPTURE="tests/fixtures/hooks/codex-capture.sh"

@test "spawn_agent is normalized to the canonical Task payload" {
  local wd; wd="$(mk_tmpworkdir)"
  run env BASE_PLUGIN_ROOT="$PLUGIN_ROOT" WORKSPACE_ROOT="$wd" \
    bash "$PLUGIN_ROOT/$ADAPTER" --mode tool --target "$CAPTURE" <<'JSON'
{"tool_name":"spawn_agent","tool_input":{"task_name":"cf_dv0_1","message":"Build it"}}
JSON
  assert_success
  echo "$output" | jq -e '.tool_name == "Task" and .tool_input == {subagent_type:"cf_dv0_1",prompt:"Build it"}'
}

@test "request_user_input answers are keyed by question text" {
  local wd; wd="$(mk_tmpworkdir)"
  run env BASE_PLUGIN_ROOT="$PLUGIN_ROOT" WORKSPACE_ROOT="$wd" \
    bash "$PLUGIN_ROOT/$ADAPTER" --mode decision --target "$CAPTURE" <<'JSON'
{"tool_name":"request_user_input","tool_input":{"questions":[{"id":"route","question":"Which route?"}]},"tool_response":{"answers":{"route":{"answers":["Safe"]}}}}
JSON
  assert_success
  echo "$output" | jq -e '.tool_name == "AskUserQuestion" and .tool_response.answers["Which route?"] == ["Safe"]'
}

@test "apply_patch sends one post-hook payload per safe path" {
  local wd capture physical_wd
  wd="$(mk_tmpworkdir)"; capture="$wd/paths"; physical_wd="$(cd "$wd" && pwd -P)"
  run env BASE_PLUGIN_ROOT="$PLUGIN_ROOT" WORKSPACE_ROOT="$wd" CODEX_CAPTURE_FILE="$capture" \
    bash "$PLUGIN_ROOT/$ADAPTER" --mode patch-post --target "$CAPTURE" <<'JSON'
{"tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Add File: one.txt\n+x\n*** Update File: dir/two.txt\n@@\n-old\n+new\n*** Add File: ../escape.txt\n*** End Patch"}}
JSON
  assert_success
  run sed "s#^$physical_wd/##" "$capture"
  assert_success
  assert_output $'one.txt\ndir/two.txt'
}

@test "apply_patch accepts Codex's patch payload field" {
  local wd physical_wd; wd="$(mk_tmpworkdir)"; physical_wd="$(cd "$wd" && pwd -P)"
  run env BASE_PLUGIN_ROOT="$PLUGIN_ROOT" WORKSPACE_ROOT="$wd" \
    bash "$PLUGIN_ROOT/$ADAPTER" --mode tool --target "$CAPTURE" <<'JSON'
{"tool_name":"apply_patch","tool_input":{"patch":"*** Begin Patch\n*** Add File: nested/file.txt\n+x\n*** End Patch"}}
JSON
  assert_success
  echo "$output" | jq -e --arg path "$physical_wd/nested/file.txt" '.tool_name == "Write" and .tool_input.file_path == $path'
}

@test "SubagentStop gains its canonical agent type from the ledger" {
  local wd; wd="$(mk_tmpworkdir)"; mkdir -p "$wd/.context"
  printf '%s\n' '{"facts":{"dispatched_agents":[{"agent_id":"agt_1","subagent_type":"corpflow:developer","task_id":"DV0","stage":"DV"}]}}' > "$wd/.context/state.json"
  run env BASE_PLUGIN_ROOT="$PLUGIN_ROOT" WORKSPACE_ROOT="$wd" \
    bash "$PLUGIN_ROOT/$ADAPTER" --mode subagent --target "$CAPTURE" <<'JSON'
{"agent_id":"agt_1","cwd":"/ignored"}
JSON
  assert_success
  echo "$output" | jq -e '.agent_type == "corpflow:developer" and (.corpflow_task_id? == null)'
}
