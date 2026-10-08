#!/usr/bin/env bats
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

ADAPTER="hooks/codex-adapter.sh"
CAPTURE="tests/fixtures/hooks/codex-capture.sh"

@test "spawn_agent is normalized to the canonical Agent payload" {
  local wd; wd="$(mk_tmpworkdir)"
  run env BASE_PLUGIN_ROOT="$PLUGIN_ROOT" WORKSPACE_ROOT="$wd" \
    bash "$PLUGIN_ROOT/$ADAPTER" --mode tool --target "$CAPTURE" <<'JSON'
{"tool_name":"spawn_agent","tool_input":{"task_name":"cf_dv0_1","message":"Build it"}}
JSON
  assert_success
  echo "$output" | jq -e '.tool_name == "Agent" and .tool_input == {subagent_type:"cf_dv0_1",prompt:"Build it"}'
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

@test "absolute workspace paths reach tool and post-hook normalization without a duplicate prefix" {
  local wd physical payload mode
  wd="$(mk_tmpworkdir)"; physical="$(cd "$wd" && pwd -P)"
  payload=$(jq -cn --arg p "$wd/new dir/file.txt" '{tool_name:"apply_patch",
    tool_input:{patch:("*** Begin Patch\n*** Add File: " + $p + "\n+x\n*** End Patch")}}')
  for mode in tool patch-post; do
    run env BASE_PLUGIN_ROOT="$PLUGIN_ROOT" WORKSPACE_ROOT="$wd" \
      bash "$PLUGIN_ROOT/$ADAPTER" --mode "$mode" --target "$CAPTURE" <<< "$payload"
    assert_success
    echo "$output" | jq -e --arg p "$physical/new dir/file.txt" '.tool_input.file_path == $p'
  done
}

# A patch maps to a Write, which the pre-write gate never denies; the post-write gate reports it.
@test "relative and absolute artifact patches pass the pre-write gate and fail the post-write gate" {
  local wd path payload
  wd="$(mk_tmpworkdir)"; mkdir -p "$wd/.context"
  printf '{}\n' > "$wd/.context/state.json"
  printf -- '---\nhandoff:\n  stage: DV\n---\n\n## Approach\n' > "$wd/.context/development-0.md"
  for path in .context/development-0.md "$wd/.context/development-0.md"; do
    payload=$(jq -cn --arg p "$path" '{hook_event_name:"PreToolUse",tool_name:"apply_patch",
      tool_input:{patch:("*** Begin Patch\n*** Add File: " + $p + "\n+## Approach\n*** End Patch")}}')
    run env BASE_PLUGIN_ROOT="$PLUGIN_ROOT" WORKSPACE_ROOT="$wd" \
      bash "$PLUGIN_ROOT/$ADAPTER" --mode patch-pre --target hooks/anchor-preflight.sh \
      -- --event pre <<< "$payload"
    assert_success
    assert_output ""
    payload=$(jq -cn --arg p "$path" '{hook_event_name:"PostToolUse",tool_name:"apply_patch",
      tool_input:{patch:("*** Begin Patch\n*** Add File: " + $p + "\n+## Approach\n*** End Patch")}}')
    run env BASE_PLUGIN_ROOT="$PLUGIN_ROOT" WORKSPACE_ROOT="$wd" \
      bash "$PLUGIN_ROOT/$ADAPTER" --mode patch-post --target hooks/anchor-preflight.sh \
      -- --event post <<< "$payload"
    assert_failure 2
    assert_output --partial "has H2 outside the allow-list: ## Approach."
  done
}

@test "an absolute artifact path reaches the real post-write control-byte check" {
  local wd payload
  wd="$(mk_tmpworkdir)"; mkdir -p "$wd/.context"
  printf '{}\n' > "$wd/.context/state.json"
  printf 'bad\000text\n' > "$wd/.context/notes.md"
  payload=$(jq -cn --arg p "$wd/.context/notes.md" '{hook_event_name:"PostToolUse",tool_name:"apply_patch",
    tool_input:{patch:("*** Begin Patch\n*** Update File: " + $p + "\n@@\n+x\n*** End Patch")}}')
  run env BASE_PLUGIN_ROOT="$PLUGIN_ROOT" WORKSPACE_ROOT="$wd" \
    bash "$PLUGIN_ROOT/$ADAPTER" --mode patch-post --target hooks/anchor-preflight.sh \
    -- --event post <<< "$payload"
  assert_failure 2
  assert_output --partial "0x00"
}

@test "patch paths outside the workspace or through escaping symlinks never reach the target" {
  local wd outside capture payload
  wd="$(mk_tmpworkdir)"; outside="$(mk_tmpworkdir)"; capture="$wd/paths"
  mkdir -p "$wd-sibling" "$wd/inside"
  ln -s "$outside" "$wd/escape"
  ln -s "$wd/inside" "$wd/local"
  printf 'valid\n' > "$wd/inside/file.txt"
  printf 'outside\n' > "$outside/file.txt"
  ln -s inside/file.txt "$wd/file-link"
  ln -s "$outside/file.txt" "$wd/outside-link"
  ln -s cycle-b "$wd/cycle-a"
  ln -s cycle-a "$wd/cycle-b"
  payload=$(jq -cn --arg w "$wd" --arg o "$outside" '{tool_name:"apply_patch",tool_input:{patch:
    ("*** Begin Patch\n*** Add File: " + $o + "/outside.txt\n+x\n*** Add File: " + $w + "-sibling/no.txt\n+x\n"
    + "*** Add File: ../outside.txt\n+x\n*** Add File: escape/no.txt\n+x\n"
    + "*** Add File: " + $w + "/escape/no.txt\n+x\n*** Add File: local/yes.txt\n+x\n"
    + "*** Update File: " + $w + "/outside-link\n+x\n*** Update File: " + $w + "/file-link\n+x\n"
    + "*** Update File: cycle-a\n+x\n*** End Patch")}}')
  run env BASE_PLUGIN_ROOT="$PLUGIN_ROOT" WORKSPACE_ROOT="$wd" CODEX_CAPTURE_FILE="$capture" \
    bash "$PLUGIN_ROOT/$ADAPTER" --mode patch-post --target "$CAPTURE" <<< "$payload"
  assert_success
  [ "$(cat "$capture")" = "$(cd "$wd" && pwd -P)/inside/yes.txt
$(cd "$wd" && pwd -P)/inside/file.txt" ]
  rmdir "$wd-sibling"
}
