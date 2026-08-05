#!/usr/bin/env bats
# Contract tests for skills/worktask/scripts/detect-ui-change.sh.
# Contracts (from header):
#   - emits a single JSON line {"requires_screenshots":bool,"signals":[...],"rationale":"..."}
#   - exit 0 ALWAYS on the detection path
#   - OR over S1..S4: ANY signal true => requires_screenshots:true
#   - S3 UI keyword set fires on SwiftUI/view/etc.
#   - fail-safe: unreadable plan => requires_screenshots:true, signals:["fail_safe"], exit 0
#   - --self-test => "fail=0", exit 0
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/scripts/detect-ui-change.sh"

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

@test "S2: a figma-registry.md in DESIGNS_DIR fires S2 and nothing else" {
  mkdir -p "$WD/designs"
  printf '# Figma registry\n' > "$WD/designs/figma-registry.md"
  # nonui.md carries no S3 keyword, so an exact ["S2"] proves the probe fired on
  # its own rather than riding on another signal.
  run env DESIGNS_DIR="$WD/designs" bash "$PLUGIN_ROOT/$SCRIPT" "$WD/nonui.md"
  assert_success
  local json="$output"
  run jq -cr '.signals' <<<"$json"
  assert_output '["S2"]'
  run jq -r '.requires_screenshots' <<<"$json"
  assert_output "true"
}

@test "S2: a bare *.png in DESIGNS_DIR is the second, independent trigger" {
  mkdir -p "$WD/designs"
  printf 'not really a png\n' > "$WD/designs/mock.png"
  run env DESIGNS_DIR="$WD/designs" bash "$PLUGIN_ROOT/$SCRIPT" "$WD/nonui.md"
  assert_success
  local json="$output"
  run jq -cr '.signals' <<<"$json"
  assert_output '["S2"]'
}

@test "S2: an empty DESIGNS_DIR fires nothing (control for the two above)" {
  mkdir -p "$WD/designs"
  run env DESIGNS_DIR="$WD/designs" bash "$PLUGIN_ROOT/$SCRIPT" "$WD/nonui.md"
  assert_success
  local json="$output"
  run jq -cr '.signals' <<<"$json"
  assert_output '[]'
}

@test "S4: a UI path class under an admitted platform fires S4 and nothing else" {
  # .tsx is deliberate: it is in UI_PATH_CLASSES but matches no UI_KEYWORD, so
  # S3 cannot mask a broken S4. (Views/, res/layout etc. all trip S3 as well.)
  printf '## scope\nrewrite src/App.tsx\n' > "$WD/s4.md"
  run env DESIGNS_DIR="$WD/none" bash "$PLUGIN_ROOT/$SCRIPT" "$WD/s4.md" --platform web
  assert_success
  local json="$output"
  run jq -cr '.signals' <<<"$json"
  assert_output '["S4"]'
  run jq -r '.requires_screenshots' <<<"$json"
  assert_output "true"
}

@test "S4: the same plan on a non-admitted platform fires nothing" {
  # Falsification arm for the case statement at :122-127 — without it the S4
  # test above would pass even if the platform gate were deleted.
  printf '## scope\nrewrite src/App.tsx\n' > "$WD/s4.md"
  run env DESIGNS_DIR="$WD/none" bash "$PLUGIN_ROOT/$SCRIPT" "$WD/s4.md" --platform systems
  assert_success
  local json="$output"
  run jq -cr '.signals' <<<"$json"
  assert_output '[]'
  run jq -r '.requires_screenshots' <<<"$json"
  assert_output "false"
}

@test "contract: --self-test passes (smoke, NON-counting)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "fail=0"
}
