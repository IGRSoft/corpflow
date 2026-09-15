#!/usr/bin/env bats
# Tests for hooks/permission-denied.sh — the PermissionDenied observer that appends one deduped
# permission_denied row and never returns a decision.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="hooks/permission-denied.sh"
LIB="hooks/lib/permission-denied-lib.sh"
PARK="skills/worktask/scripts/permission-park.sh"
PAYLOAD="${FIXTURES}/hooks/permission-denied/merge-denied.payload.json"
MERGE_CMD="gh pr merge 412 --squash --delete-branch"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/.context"
  printf '%s' '{"run_index":0,"facts":{},"tasks":{"QA0":{"status":"completed","metadata":{}},"FN0":{"status":"in_progress","metadata":{"retry_count":1}}}}' \
    > "$WD/.context/state.json"
  AUDIT="$WD/.context/logs/audit.jsonl"
}

_hook() {
  run --separate-stderr env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" "$@"
}

_rows() {
  [ -f "$AUDIT" ] || { echo 0; return 0; }
  grep -c '"action":"permission_denied"' "$AUDIT" || true
}

@test "AC5: a classifier denial appends one row carrying the four detail keys" {
  _hook < "$PAYLOAD"
  assert_success
  assert_output ""
  [ "$(_rows)" = 1 ] || fail "expected one permission_denied row, got $(_rows)"
  run jq -e --arg c "$MERGE_CMD" '
    .actor == "hook:permission-denied" and .action == "permission_denied"
    and .subject == "FN0" and .result == "block"
    and .metadata.tool == "Bash" and .metadata.command == $c
    and .metadata.classifier_reason == "Blocked by classifier"
    and .metadata.allow_rule == ("Bash(" + $c + ")")
    and .metadata.source == "hook"
    and (.metadata.dedupe_key | test("^[0-9a-f]{16}$"))' "$AUDIT"
  assert_success
}

@test "AC5: stdout stays empty on every path, so no retry decision can be returned" {
  local input
  for input in "$(cat "$PAYLOAD")" \
    '{"hook_event_name":"PermissionDenied","tool_name":"Bash","tool_input":{"command":"x"},"reason":"Classifier unavailable"}' \
    'not json' ''; do
    run --separate-stderr env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" <<< "$input"
    assert_success
    assert_output ""
  done
  run grep -nE 'retry|hookSpecificOutput' "$PLUGIN_ROOT/$SCRIPT" "$PLUGIN_ROOT/$LIB"
  [ "$status" -eq 1 ] || fail "decision vocabulary present in the hook: $output"
}

@test "AC5: the same denial firing twice still yields one row" {
  _hook < "$PAYLOAD"
  _hook < "$PAYLOAD"
  assert_success
  [ "$(_rows)" = 1 ] || fail "expected one row, got $(_rows)"
}

@test "AC5: the fallback re-writing a hook-logged denial adds no second row" {
  local detail hook_key
  _hook < "$PAYLOAD"
  run --separate-stderr bash "$PLUGIN_ROOT/$PARK" classify < "$PAYLOAD"
  assert_success
  detail="$output"
  run --separate-stderr bash "$PLUGIN_ROOT/$PARK" park --state "$WD/.context/state.json" \
    --task-id FN0 --detail "$detail"
  assert_success
  jq -e '.audit_row_written == false' <<< "$output"
  [ "$(_rows)" = 1 ] || fail "expected one row, got $(_rows)"
  hook_key="$(jq -r 'select(.action == "permission_denied") | .metadata.dedupe_key' "$AUDIT")"
  [ "$hook_key" = "$(jq -r '.dedupe_key' <<< "$output")" ] || fail "hook and fallback keys differ"
}

@test "dedupe: a row whose task could not be resolved still pairs with the fallback" {
  jq '.tasks.DR0 = {"status":"in_progress","metadata":{}}' "$WD/.context/state.json" > "$WD/s.tmp"
  mv "$WD/s.tmp" "$WD/.context/state.json"
  _hook < "$PAYLOAD"
  run jq -r '.subject' "$AUDIT"
  assert_output "unknown"
  run --separate-stderr bash "$PLUGIN_ROOT/$PARK" park --state "$WD/.context/state.json" \
    --task-id FN0 --detail "$(bash "$PLUGIN_ROOT/$PARK" classify < "$PAYLOAD")"
  assert_success
  [ "$(_rows)" = 1 ] || fail "expected one row, got $(_rows)"
}

@test "subject: a launched dispatch for the payload's agent_id names the task" {
  jq '.tasks.DR0 = {"status":"in_progress","metadata":{}}
      | .facts.dispatched_agents = [{"stage":"DR","task_id":"DR0","agent_id":"agent-dr","status":"launched"}]' \
    "$WD/.context/state.json" > "$WD/s.tmp"
  mv "$WD/s.tmp" "$WD/.context/state.json"
  _hook <<< "$(jq -c '. + {agent_id: "agent-dr"}' "$PAYLOAD")"
  assert_success
  run jq -r '.subject' "$AUDIT"
  assert_output "DR0"
}

@test "SR: untrusted command text is bounded and stripped of control characters" {
  local long payload
  long="$(printf 'a%.0s' $(seq 1 3000))"
  payload="$(jq -cn --arg c "$(printf 'rm -rf /tmp/x\n\033[31m')$long" \
    '{hook_event_name:"PermissionDenied", tool_name:"Bash", tool_input:{command:$c}, reason:"Blocked by classifier"}')"
  _hook <<< "$payload"
  assert_success
  run jq -e '(.metadata.command | length) <= 512 and (.metadata.command | test("[[:cntrl:]]") | not)
    and (.metadata.allow_rule | length) <= 600' "$AUDIT"
  assert_success
}

@test "SR: Unicode format characters are removed from every field of the hook row" {
  local rlo pdi zw bom payload
  rlo="$(printf '\342\200\256')" pdi="$(printf '\342\201\251')" zw="$(printf '\342\200\215')" bom="$(printf '\357\273\277')"
  payload="$(jq -cn --arg t "Ba${zw}sh" --arg c "cat ${rlo}txt.exe${pdi}" --arg r "Blocked${bom} by classifier" \
    '{hook_event_name:"PermissionDenied", tool_name:$t, tool_input:{command:$c}, reason:$r}')"
  _hook <<< "$payload"
  assert_success
  run jq -e '.metadata | .tool == "Bash" and .command == "cat txt.exe"
    and .classifier_reason == "Blocked by classifier" and .allow_rule == "Bash(cat txt.exe)"' "$AUDIT"
  assert_success
}

@test "dedupe: with no sha256 tool the key falls back to a deterministic cksum-derived 16 hex" {
  local bin
  bin="$(mk_tmpworkdir)"
  ln -s "$(command -v cksum)" "$bin/cksum"
  run bash -c '. "$1"; PATH="$2"; printf "%s %s %s" "$(pd_dedupe_key FN0 Bash x)" "$(pd_dedupe_key FN0 Bash x)" "$(pd_dedupe_key FN0 Bash y)"' \
    _ "$PLUGIN_ROOT/$LIB" "$bin"
  assert_success
  local a b c
  read -r a b c <<< "$output"
  [[ "$a" =~ ^[0-9a-f]{16}$ ]] || fail "not 16 hex: $a"
  [ "$a" = "$b" ] || fail "fallback key is not deterministic: $a vs $b"
  [ "$a" != "$c" ] || fail "different commands share a fallback key"
}

@test "SR: a symlinked audit.jsonl is refused, never written through" {
  mkdir -p "$WD/.context/logs" "$WD/target"
  ln -s "$WD/target/escaped.txt" "$AUDIT"
  _hook < "$PAYLOAD"
  assert_success
  [ ! -e "$WD/target/escaped.txt" ]
}

@test "no-op: an event other than PermissionDenied writes nothing" {
  _hook <<< '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"ls"},"reason":"x"}'
  assert_success
  [ ! -e "$AUDIT" ]
}

@test "no-op: an unresolved root exits 0 and creates no .context under cwd" {
  local cwd
  cwd="$(mk_tmpworkdir)"
  run_script_env --cwd "$cwd" --unset WORKSPACE_ROOT --unset CLAUDE_PROJECT_DIR --unset CONTEXT_DIR \
    --env "GIT_CEILING_DIRECTORIES=$cwd" --stdin-string "$(cat "$PAYLOAD")" "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  [ ! -e "$cwd/.context" ]
}

@test "AC8: plugin.json registers PermissionDenied on this hook, executable, library not" {
  run jq -e '.hooks.PermissionDenied' "$PLUGIN_ROOT/.claude-plugin/plugin.json"
  assert_success
  run jq -r '.hooks.PermissionDenied[].hooks[].command' "$PLUGIN_ROOT/.claude-plugin/plugin.json"
  assert_output '${CLAUDE_PLUGIN_ROOT}/hooks/permission-denied.sh'
  [ -x "$PLUGIN_ROOT/$SCRIPT" ]
  [ ! -x "$PLUGIN_ROOT/$LIB" ]
}

@test "contract: --self-test passes (smoke, NON-counting)" {
  run_script_env "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "self-test OK"
}
