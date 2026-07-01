#!/usr/bin/env bats
# Tests for hooks/dv-screenshot-gate.sh (DV0c) — SubagentStop gate that blocks
# the developer agent when the screenshots.md manifest is missing.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="hooks/dv-screenshot-gate.sh"
DEV_PAYLOAD="${FIXTURES}/hooks/dv-screenshot-gate-developer.payload.json"
NONDEV_PAYLOAD="${FIXTURES}/hooks/dv-screenshot-gate-nondeveloper.payload.json"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/.context"
}

@test "failure: developer + manifest absent -> block decision + block audit row" {
  printf '%s' '{"version":1,"worktask_id":"wt-block","metadata":{}}' > "$WD/.context/state.json"
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" < "$DEV_PAYLOAD"
  assert_success   # block is communicated via stdout JSON, exit stays 0
  echo "$output" | jq -e '
    .decision == "block"
    and (.reason | test("missing screenshots.md"))
    and .hookSpecificOutput.hookEventName == "SubagentStop"
    and (.hookSpecificOutput.additionalContext | test("dv-screenshot-capture"))
  '
  run jq -e '.action == "screenshot_gate_block" and .result == "block"
             and .metadata.worktask_id == "wt-block"' \
    "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "happy: manifest present on disk -> pass row, no block on stdout" {
  printf '%s' '{"version":1,"worktask_id":"wt-pass","metadata":{}}' > "$WD/.context/state.json"
  mkdir -p "$WD/.context/images/wt-pass"
  printf '# screenshots\n' > "$WD/.context/images/wt-pass/screenshots.md"
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" < "$DEV_PAYLOAD"
  assert_success
  [ -z "$output" ]
  run jq -e '.action == "screenshot_gate_pass" and .metadata.reason == "manifest present"' \
    "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "edge: requires_screenshots=false passes even with no manifest" {
  printf '%s' '{"version":1,"worktask_id":"wt-noui","metadata":{"requires_screenshots":false}}' \
    > "$WD/.context/state.json"
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" < "$DEV_PAYLOAD"
  assert_success
  [ -z "$output" ]
  run jq -e '.action == "screenshot_gate_pass" and .metadata.reason == "requires_screenshots=false"' \
    "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "edge: non-developer agent is a no-op (no block, no audit row)" {
  printf '%s' '{"version":1,"worktask_id":"wt-x","metadata":{}}' > "$WD/.context/state.json"
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" < "$NONDEV_PAYLOAD"
  assert_success
  [ -z "$output" ]
  [ ! -f "$WD/.context/logs/audit.jsonl" ]
}

@test "contract: --self-test passes (smoke, NON-counting)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "self-test OK"
}
