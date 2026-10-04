#!/usr/bin/env bats
# headless-poststop.sh — replays the SubagentStop hooks a headless main session never fires.
# Most cases run against a FIXTURE plugin.json and fixture hook scripts, so a live gate's own
# behaviour changing under it can never flip this suite red or green by accident. The
# "real hooks" block below is the deliberate exception: it replays the plugin's OWN installed
# plugin.json against the real dv-screenshot-gate.sh and state-merge.sh, because a fixture
# double cannot prove the replay actually reaches those two gates end to end.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/scripts/headless-poststop.sh"

setup() {
  RIG="$(mk_tmpworkdir)"
  mkdir -p "$RIG/hooks" "$RIG/ws/.context"
  cat > "$RIG/ws/.context/state.json" <<'EOF'
{"tasks":{"DV0":{"status":"in_progress","metadata":{"agent":"corpflow:developer"}},
"FN0":{"status":"in_progress","metadata":{"agent":"corpflow:project-manager"}},
"QA0":{"status":"in_progress","metadata":{"agent":"corpflow:qa-engineer"}}},"facts":{}}
EOF

  cat > "$RIG/hooks/pass.sh" << 'EOF'
#!/usr/bin/env bash
cat > /dev/null
echo '{}'
exit 0
EOF
  cat > "$RIG/hooks/block.sh" << 'EOF'
#!/usr/bin/env bash
cat > /dev/null
echo '{"decision":"block","reason":"missing manifest","hookSpecificOutput":{"hookEventName":"SubagentStop","additionalContext":"capture a screenshot"}}'
exit 0
EOF
  cat > "$RIG/hooks/second-block.sh" << 'EOF'
#!/usr/bin/env bash
cat > /dev/null
echo '{"decision":"block","reason":"comment density too low","hookSpecificOutput":{"hookEventName":"SubagentStop","additionalContext":"trim the header docstring"}}'
exit 0
EOF
  cat > "$RIG/hooks/record-env.sh" << 'EOF'
#!/usr/bin/env bash
cat > /dev/null
printf '%s\n' "$CLAUDE_TASK_ID|$CLAUDE_TASK_METADATA_STAGE|$CLAUDE_AGENT_NAME" > "$RECORD_FILE"
echo '{}'
exit 0
EOF

  cat > "$RIG/plugin.json" << EOF
{"hooks":{"SubagentStop":[
  {"matcher":"^corpflow:developer\$","hooks":[
    {"type":"command","command":"$RIG/hooks/pass.sh"},
    {"type":"command","command":"$RIG/hooks/block.sh"}
  ]},
  {"matcher":"^corpflow:project-manager\$","hooks":[
    {"type":"command","command":"$RIG/hooks/pass.sh","args":["--stage","FN"]}
  ]}
]}}
EOF
}

run_poststop() { # extra args
  run_script "$SCRIPT" --task DV0 --session child-sess-1 --orchestrator-session orch-sess-1 \
    --agent corpflow:developer --workspace "$RIG/ws" --plugin-json "$RIG/plugin.json" "$@"
}

field() { jq -r --arg k "$1" '.[$k]' <<< "$output"; }

@test "a matched group's block verdict is aggregated: blocked=true, reason and context carried" {
  run_poststop --attempt 1
  assert_success
  [ "$(field blocked)" = "true" ]
  [ "$(jq -r '.reasons[0]' <<< "$output")" = "missing manifest" ]
  [ "$(field additional_context)" = "capture a screenshot" ]
  [ "$(field escalate)" = "false" ]
}

@test "every matched hook runs regardless of an earlier one blocking (aggregation, not short-circuit)" {
  cat > "$RIG/plugin.json" << EOF
{"hooks":{"SubagentStop":[
  {"matcher":"^corpflow:developer\$","hooks":[
    {"type":"command","command":"$RIG/hooks/block.sh"},
    {"type":"command","command":"$RIG/hooks/second-block.sh"}
  ]}
]}}
EOF
  run_poststop --attempt 1
  assert_success
  [ "$(field blocked)" = "true" ]
  assert_output --partial "missing manifest"
  assert_output --partial "comment density too low"
}

@test "a non-matching agent's group never runs, and the row is not blocked" {
  run_script "$SCRIPT" --task FN0 --session sess-2 --orchestrator-session orch-sess-2 \
    --agent corpflow:project-manager --workspace "$RIG/ws" --plugin-json "$RIG/plugin.json" --attempt 1
  assert_success
  [ "$(field blocked)" = "false" ]
  [ "$(jq -r '.reasons | length' <<< "$output")" -eq 0 ]
}

@test "a matcher-less group always runs, regardless of the agent" {
  cat > "$RIG/plugin.json" << EOF
{"hooks":{"SubagentStop":[
  {"hooks":[{"type":"command","command":"$RIG/hooks/pass.sh"}]}
]}}
EOF
  run_script "$SCRIPT" --task QA0 --session sess-3 --orchestrator-session orch-sess-3 \
    --agent corpflow:qa-engineer --workspace "$RIG/ws" --plugin-json "$RIG/plugin.json" --attempt 1
  assert_success
  assert_output --partial "pass.sh"
}

@test "attempt 2 (first resume) sets stop_hook_active but does not yet escalate" {
  run_poststop --attempt 2
  assert_success
  [ "$(field blocked)" = "true" ]
  [ "$(field escalate)" = "false" ]
}

@test "attempt 3 (second resume, the cap), still blocked, escalates instead of a fourth replay" {
  run_poststop --attempt 3
  assert_success
  [ "$(field blocked)" = "true" ]
  [ "$(field escalate)" = "true" ]
}

@test "attempt 1 never escalates even when blocked" {
  run_poststop --attempt 1
  assert_success
  [ "$(field escalate)" = "false" ]
}

@test "hooks_run lists every hook actually invoked, in plugin.json's declared order" {
  run_poststop --attempt 1
  assert_success
  first="$(jq -r '.hooks_run[0]' <<< "$output")"
  second="$(jq -r '.hooks_run[1]' <<< "$output")"
  [[ "$first" == *pass.sh ]]
  [[ "$second" == *block.sh ]]
}

@test "declared --args reach the replayed hook (data-driven parity with plugin.json)" {
  cat > "$RIG/hooks/args-echo.sh" << 'EOF'
#!/usr/bin/env bash
cat > /dev/null
printf '{}' # valid, non-blocking
echo "$*" >&2
exit 0
EOF
  chmod +x "$RIG/hooks/args-echo.sh"
  cat > "$RIG/plugin.json" << EOF
{"hooks":{"SubagentStop":[
  {"matcher":"^corpflow:project-manager\$","hooks":[
    {"type":"command","command":"$RIG/hooks/args-echo.sh","args":["--stage","FN"]}
  ]}
]}}
EOF
  run_script "$SCRIPT" --task FN0 --session sess-4 --orchestrator-session orch-sess-4 \
    --agent corpflow:project-manager --workspace "$RIG/ws" --plugin-json "$RIG/plugin.json" --attempt 1
  assert_success
}

@test "the synthesized payload's CLAUDE_* env matches the CLI flags, not the hooks it replays" {
  RECORD_FILE="$RIG/record.txt"
  cat > "$RIG/plugin.json" << EOF
{"hooks":{"SubagentStop":[
  {"matcher":"^corpflow:developer\$","hooks":[
    {"type":"command","command":"$RIG/hooks/record-env.sh"}
  ]}
]}}
EOF
  RECORD_FILE="$RECORD_FILE" run_script "$SCRIPT" --task DV0 --session sess-5 \
    --orchestrator-session orch-sess-5 --agent corpflow:developer --workspace "$RIG/ws" \
    --artifact development-0.md --plugin-json "$RIG/plugin.json" --attempt 1
  assert_success
  [ "$(cat "$RECORD_FILE")" = "DV0|DV|corpflow:developer" ]
}

@test "no effort key is emitted in the payload when the tier was never observed" {
  cat > "$RIG/hooks/dump-payload.sh" << EOF
#!/usr/bin/env bash
cat > "$RIG/payload.json"
echo '{}'
exit 0
EOF
  chmod +x "$RIG/hooks/dump-payload.sh"
  cat > "$RIG/plugin.json" << EOF
{"hooks":{"SubagentStop":[
  {"matcher":"^corpflow:developer\$","hooks":[
    {"type":"command","command":"$RIG/hooks/dump-payload.sh"}
  ]}
]}}
EOF
  run_poststop --attempt 1
  assert_success
  [ "$(jq -r '.effort' "$RIG/payload.json")" = "{}" ]
}

@test "an observed effort.level flows through to the synthesized payload" {
  cat > "$RIG/hooks/dump-payload.sh" << EOF
#!/usr/bin/env bash
cat > "$RIG/payload.json"
echo '{}'
exit 0
EOF
  chmod +x "$RIG/hooks/dump-payload.sh"
  cat > "$RIG/plugin.json" << EOF
{"hooks":{"SubagentStop":[
  {"matcher":"^corpflow:developer\$","hooks":[
    {"type":"command","command":"$RIG/hooks/dump-payload.sh"}
  ]}
]}}
EOF
  run_script "$SCRIPT" --task DV0 --session sess-6 --orchestrator-session orch-sess-6 \
    --agent corpflow:developer --workspace "$RIG/ws" --plugin-json "$RIG/plugin.json" --effort-level xhigh --attempt 1
  assert_success
  [ "$(jq -r '.effort.level' "$RIG/payload.json")" = "xhigh" ]
}

@test "usage error: missing required flags exits 2" {
  run_script "$SCRIPT" --task DV0 --session sess-1
  assert_failure 2
}

@test "an unreadable plugin.json path is a usage error" {
  run_script "$SCRIPT" --task DV0 --session sess-1 --agent corpflow:developer \
    --plugin-json "$RIG/no-such-plugin.json"
  assert_failure 2
}

@test "an invalid --attempt value is a usage error" {
  run_poststop --attempt 4
  assert_failure 2
}

@test "no --orchestrator-session is a usage error" {
  run_script "$SCRIPT" --task DV0 --session child-sess-1 --agent corpflow:developer \
    --workspace "$RIG/ws" --plugin-json "$RIG/plugin.json" --attempt 1
  assert_failure 2
}

@test "the synthesized payload's session_id is the orchestrator's session, agent_id is the child's" {
  RECORD_FILE="$RIG/record.txt"
  cat > "$RIG/hooks/dump-payload.sh" << EOF
#!/usr/bin/env bash
cat > "$RIG/payload.json"
echo '{}'
exit 0
EOF
  chmod +x "$RIG/hooks/dump-payload.sh"
  cat > "$RIG/plugin.json" << EOF
{"hooks":{"SubagentStop":[
  {"matcher":"^corpflow:developer\$","hooks":[
    {"type":"command","command":"$RIG/hooks/dump-payload.sh"}
  ]}
]}}
EOF
  run_poststop --attempt 1
  assert_success
  [ "$(jq -r '.session_id' "$RIG/payload.json")" = "orch-sess-1" ]
  [ "$(jq -r '.agent_id' "$RIG/payload.json")" = "child-sess-1" ]
}

# --- AC7: the real installed plugin.json against the real gates, not a fixture double ---------

@test "AC7: a missing screenshot manifest blocks through the real dv-screenshot-gate.sh" {
  ORCH_ROOT="$(mk_tmpworkdir)"
  mkdir -p "$ORCH_ROOT/.context/logs"
  cat > "$ORCH_ROOT/.context/state.json" << 'EOF'
{"run_index":1,"tasks":{"DV9":{"status":"in_progress",
  "metadata":{"stage":"DV","agent":"corpflow:developer","requires_screenshots":true,
    "artifact":".context/development-9.md"}}},"facts":{}}
EOF
  cat > "$ORCH_ROOT/development-9.md" << 'EOF'
---
handoff:
  stage: DV
  verdict: ok
  summary: "no manifest yet"
---
EOF
  run_script "$SCRIPT" --task DV9 --session child-real-1 --orchestrator-session orch-real-1 \
    --agent corpflow:developer --workspace "$ORCH_ROOT" --artifact development-9.md \
    --plugin-json "$PLUGIN_ROOT/.claude-plugin/plugin.json" --attempt 1
  assert_success
  [ "$(field blocked)" = "true" ]
  assert_output --partial "dv-screenshot-gate.sh"
}

@test "AC7: the real state-merge.sh merges the artifact's handoff into WORKSPACE_ROOT's ledger" {
  ORCH_ROOT="$(mk_tmpworkdir)"
  mkdir -p "$ORCH_ROOT/.context/logs"
  cat > "$ORCH_ROOT/.context/state.json" << 'EOF'
{"run_index":1,"tasks":{"DV9":{"status":"in_progress",
  "metadata":{"stage":"DV","agent":"corpflow:developer","artifact":".context/development-9.md",
    "dispatch_surface":"headless"}}},"facts":{}}
EOF
  cat > "$ORCH_ROOT/development-9.md" << 'EOF'
---
handoff:
  stage: DV
  verdict: ok
  summary: "headless child merged via replayed state-merge"
---
EOF
  WORKSPACE_ROOT="$ORCH_ROOT" run_script "$SCRIPT" --task DV9 --session child-real-2 \
    --orchestrator-session orch-real-2 --agent corpflow:developer --workspace "$ORCH_ROOT" \
    --artifact development-9.md --plugin-json "$PLUGIN_ROOT/.claude-plugin/plugin.json" \
    --attempt 1
  assert_success
  MERGED_STATUS="$(jq -r '.tasks.DV9.status' "$ORCH_ROOT/.context/state.json")"
  [ "$MERGED_STATUS" = "completed" ]
  # No landing code change (ADR-2): the merge keeps whatever dispatch metadata was already on
  # the row, including dispatch_surface — the replay neither strips nor requires it.
  [ "$(jq -r '.tasks.DV9.metadata.dispatch_surface' "$ORCH_ROOT/.context/state.json")" = "headless" ]
}

@test "AC7: SessionEnd tags a headless child's own in_progress row instead of reading it unsettled" {
  ORCH_ROOT="$(mk_tmpworkdir)"
  mkdir -p "$ORCH_ROOT/.context/logs"
  cat > "$ORCH_ROOT/.context/state.json" << 'EOF'
{"run_index":1,"tasks":{"DV9":{"status":"in_progress",
  "metadata":{"stage":"DV","agent":"corpflow:developer"}}},"facts":{}}
EOF
  WORKSPACE_ROOT="$ORCH_ROOT" CORPFLOW_HEADLESS_CHILD="DV9" CLAUDE_SESSION_ID="child-real-3" \
    run_script "hooks/session-end-finalize.sh"
  assert_success
  LAST_ROW="$(tail -1 "$ORCH_ROOT/.context/logs/audit.jsonl")"
  [ "$(jq -r '.metadata.headless_child' <<< "$LAST_ROW")" = "DV9" ]
}

@test "real screenshot gates stay blocked across retries after state-merge completes the task" {
  local ledger stream attempt
  ledger="$(mk_tmpworkdir)"; stream="$(mk_tmpworkdir)"
  mkdir -p "$ledger/.context/logs"
  cat > "$ledger/.context/state.json" <<'EOF'
{"worktask_id":"replay-test","platform":"web","run_index":0,"facts":{},"tasks":{
"DV0":{"status":"in_progress","metadata":{"agent":"corpflow:developer","requires_screenshots":true}},
"DV1":{"status":"in_progress","metadata":{"agent":"corpflow:developer","requires_screenshots":true}}}}
EOF
  cat > "$ledger/.context/development-0.md" <<'EOF'
---
handoff:
  stage: DV
  verdict: ok
  summary: "implementation without screenshots"
---
EOF
  for attempt in 1 2 3; do
    run_script "$SCRIPT" --task DV0 --session child-retry --orchestrator-session parent \
      --agent corpflow:developer --workspace "$stream" --ledger-root "$ledger" \
      --artifact "$ledger/.context/development-0.md" --attempt "$attempt"
    assert_success
    [ "$(field blocked)" = true ]
    assert_output --partial "task DV0 on platform web has no capture rows"
    [ "$(jq -r '.tasks.DV0.status' "$ledger/.context/state.json")" = completed ]
    [ "$(jq -r '.tasks.DV1.status' "$ledger/.context/state.json")" = in_progress ]
    [ ! -e "$stream/.context/state.json" ]
  done
  [ "$(field escalate)" = true ]
  # A gate-approved policy change provides a positive control after the repeated blocks.
  jq '.tasks.DV0.metadata.requires_screenshots = false' "$ledger/.context/state.json" > "$ledger/state.next"
  mv "$ledger/state.next" "$ledger/.context/state.json"
  run_script "$SCRIPT" --task DV0 --session child-retry --orchestrator-session parent \
    --agent corpflow:developer --workspace "$stream" --ledger-root "$ledger" \
    --artifact "$ledger/.context/development-0.md" --attempt 3
  assert_success
  [ "$(field blocked)" = false ]
}

@test "a missing ledger or task refuses the replay before any hooks run" {
  rm "$RIG/ws/.context/state.json"
  run_poststop
  assert_failure 2
  assert_output --partial "no hooks replayed"
  printf '{"tasks":{},"facts":{}}\n' > "$RIG/ws/.context/state.json"
  run_poststop
  assert_failure 2
  assert_output --partial "no hooks replayed"
  refute_output --partial '"hooks_run"'
}
