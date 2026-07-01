#!/usr/bin/env bats
# Tests for hooks/precompact-checkpoint.sh (DV0c) — PreCompact hook that copies
# state.json to a timestamped checkpoint and logs a precompact_checkpoint row.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="hooks/precompact-checkpoint.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/.context"
}

@test "happy: copies state.json to a checkpoint and logs result=ok" {
  printf '%s' '{"run_index":0,"stages":{}}' > "$WD/.context/state.json"
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  # A timestamped checkpoint file must now exist alongside state.json.
  run bash -c "ls $WD/.context/state.checkpoint-*.json"
  assert_success
  run jq -e '.action == "precompact_checkpoint" and .result == "ok" and .metadata.run_index == "0"' \
    "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "edge: absent state.json logs a skipped row and writes no checkpoint" {
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  run jq -e '.result == "skipped" and .metadata.reason == "no state.json"' \
    "$WD/.context/logs/audit.jsonl"
  assert_success
  run bash -c "ls $WD/.context/state.checkpoint-*.json 2>/dev/null"
  assert_failure
}

@test "edge: checkpoint records pointers to planning/development artifacts" {
  printf '%s' '{"run_index":2,"stages":{}}' > "$WD/.context/state.json"
  printf '# plan\n' > "$WD/.context/planning-2.md"
  printf '# dev\n' > "$WD/.context/development-2.md"
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  run jq -e '(.metadata.artifacts | length) == 2 and .metadata.run_index == "2"' \
    "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "contract: --self-test passes (smoke, NON-counting)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "self-test OK"
}
