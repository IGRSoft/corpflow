#!/usr/bin/env bats
# Contract tests for skills/worktask/references/detect-ui-change.sh.
# Contracts (from header):
#   - emits a single JSON line {"requires_screenshots":bool,"signals":[...],"rationale":"..."}
#   - exit 0 ALWAYS on the detection path
#   - OR over S1..S4: ANY signal true => requires_screenshots:true
#   - S3 UI keyword set fires on SwiftUI/view/etc.
#   - fail-safe: unreadable plan => requires_screenshots:true, signals:["fail_safe"], exit 0
#   - --self-test => "fail=0", exit 0
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/references/detect-ui-change.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  printf '## requirements\nAdd a SwiftUI screen with animation.\n## scope\nthe view layer\n' > "$WD/ui.md"
  printf '## requirements\nRefactor the database layer.\n## scope\nbackend only\n' > "$WD/nonui.md"
  printf -- '---\nui_visual_check: true\n---\n## scope\nbackend job\n' > "$WD/s1.md"
  # point the S2 designs probe at an empty dir so only the intended signal fires
  export DESIGNS_DIR="$WD/none"
}

@test "happy: a UI plan (S3 keyword) emits requires_screenshots:true exit 0" {
  run env DESIGNS_DIR="$WD/none" bash "$PLUGIN_ROOT/$SCRIPT" "$WD/ui.md"
  assert_success
  # Save JSON before first jq run mutates $output
  local json="$output"
  run jq -r '.requires_screenshots' <<<"$json"
  assert_output "true"
  run jq -r '.signals | index("S3")' <<<"$json"
  refute_output "null"
}

@test "happy: ui_visual_check:true frontmatter forces S1 true" {
  run env DESIGNS_DIR="$WD/none" bash "$PLUGIN_ROOT/$SCRIPT" "$WD/s1.md"
  assert_success
  local json="$output"
  run jq -r '.requires_screenshots' <<<"$json"
  assert_output "true"
  run jq -r '.signals | index("S1")' <<<"$json"
  refute_output "null"
}

@test "edge: a non-UI plan emits requires_screenshots:false with empty signals" {
  run env DESIGNS_DIR="$WD/none" bash "$PLUGIN_ROOT/$SCRIPT" "$WD/nonui.md"
  assert_success
  # Save the JSON line; subsequent `run` calls overwrite $output
  local json="$output"
  run jq -r '.requires_screenshots' <<<"$json"
  assert_output "false"
  run jq -r '.signals | length' <<<"$json"
  assert_output "0"
}

@test "failure: unreadable plan fails safe to true (exit 0, signals fail_safe)" {
  run env DESIGNS_DIR="$WD/none" bash "$PLUGIN_ROOT/$SCRIPT" /nonexistent/plan.md
  assert_success
  local json="$output"
  run jq -r '.requires_screenshots' <<<"$json"
  assert_output "true"
  run jq -r '.signals | index("fail_safe")' <<<"$json"
  refute_output "null"
}

@test "contract: --self-test passes (smoke, NON-counting)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "fail=0"
}
