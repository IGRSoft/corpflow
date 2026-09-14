#!/usr/bin/env bats
# Tests for hooks/session-end-finalize.sh (R3f) — SessionEnd hook that records
# which tasks were still in_progress when the session tore down. Background work
# killed by teardown previously left no completion record anywhere.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="hooks/session-end-finalize.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/.context"
}

@test "happy: an in_progress task is reported as unsettled with result=warn" {
  printf '%s' '{"run_index":1,"tasks":{"PL0":{"status":"completed"},"DV0":{"status":"in_progress"}}}' \
    > "$WD/.context/state.json"
  run_script_env --env "CLAUDE_PROJECT_DIR=$WD" \
    --stdin-string '{"hook_event_name":"SessionEnd","reason":"clear"}' "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  run jq -e '.action == "session_end_finalize" and .result == "warn"
             and (.metadata.unsettled | index("DV0"))
             and .metadata.session_end_reason == "clear"
             and .metadata.run_index == "1"' "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "happy: a fully settled ledger records result=ok and no unsettled tasks" {
  printf '%s' '{"run_index":0,"tasks":{"PL0":{"status":"completed"},"QA0":{"status":"skipped"}}}' \
    > "$WD/.context/state.json"
  run_script_env --env "CLAUDE_PROJECT_DIR=$WD" "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  run jq -e '.result == "ok" and (.metadata.unsettled | length) == 0
             and .metadata.status_counts.completed == 1
             and .metadata.status_counts.skipped == 1' "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "edge: an empty stdin records reason=unknown rather than failing" {
  printf '%s' '{"run_index":0,"tasks":{}}' > "$WD/.context/state.json"
  run_script_env --env "CLAUDE_PROJECT_DIR=$WD" "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  run jq -e '.metadata.session_end_reason == "unknown"' "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "edge: absent state.json logs a skipped row and still exits 0" {
  run_script_env --env "CLAUDE_PROJECT_DIR=$WD" "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  run jq -e '.result == "skipped" and .metadata.reason == "no state.json"' \
    "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "edge: a corrupt ledger neither aborts teardown nor invents a task list" {
  printf '%s' '{ not json at all' > "$WD/.context/state.json"
  run_script_env --env "CLAUDE_PROJECT_DIR=$WD" "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  run jq -e '.action == "session_end_finalize" and (.metadata.unsettled | length) == 0
             and .metadata.run_index == "unknown"' "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "contract: the ledger itself is never mutated" {
  local state="$WD/.context/state.json" before
  printf '%s' '{"run_index":0,"tasks":{"DV0":{"status":"in_progress"}}}' > "$state"
  before="$(cat "$state")"
  run_script_env --env "CLAUDE_PROJECT_DIR=$WD" "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  run cat "$state"
  assert_output "$before"
}

@test "SR: a symlinked audit.jsonl is refused, never written through" {
  printf '%s' '{"run_index":0,"tasks":{}}' > "$WD/.context/state.json"
  mkdir -p "$WD/.context/logs" "$WD/target-dir"
  ln -s "$WD/target-dir/escaped.txt" "$WD/.context/logs/audit.jsonl"
  run_script_env --env "CLAUDE_PROJECT_DIR=$WD" "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  [ ! -e "$WD/target-dir/escaped.txt" ]
}

@test "contract: --self-test passes (smoke, NON-counting)" {
  run_script_env "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "self-test OK"
}

@test "unresolved root exits 0 and creates no .context under cwd" {
  local cwd
  cwd="$(mk_tmpworkdir)"
  run_script_env --cwd "$cwd" --unset WORKSPACE_ROOT --unset CLAUDE_PROJECT_DIR --unset CONTEXT_DIR \
    --env "GIT_CEILING_DIRECTORIES=$cwd" \
    --stdin-string '{"hook_event_name":"SessionEnd","reason":"clear"}' "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  [ ! -e "$cwd/.context" ]
}
