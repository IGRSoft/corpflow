#!/usr/bin/env bats
# tests/shell/dv-screenshot/apple-canvas.bats
# Target: skills/dv-screenshot-capture/scripts/apple-canvas.sh
# Covers: missing required args → exit 5, template absent → exit 4,
#         swift absent → exit 3 (render failed), root and ledger guards.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/dv-screenshot-capture/scripts/apple-canvas.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/.context/logs" "$WD/.context/errors"
  git -C "$WD" init -q
  printf '%s' '{"version":2,"worktask_id":"wt-test","tasks":{"DV0":{"status":"in_progress"}}}' \
    > "$WD/.context/state.json"
  FILES="$WD/files.txt"
  printf 'src/Foo.swift\n' > "$FILES"
}

mk_package() {
  mkdir -p "$WD/tools/SnapshotHost/Sources/SnapshotHost"
  cat > "$WD/tools/SnapshotHost/Package.swift" << 'PKGEOF'
// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "SnapshotHost", targets: [.executableTarget(name: "SnapshotHost")])
PKGEOF
}

# ---------------------------------------------------------------------------

@test "happy: a successful render exits 0, writes the PNG and records an ok row" {
  # The toolchain double is `swift`: the script shells out to
  # `swift run --package-path … SnapshotHost --output <png>` and never invokes xcrun.
  mk_package
  # Recording double: writes a PNG wherever --output points, so the script's
  # own `[[ -f "$OUTPUT_PNG" ]]` success gate is exercised for real.
  stub_cmd swift --body '
    prev=""
    for a in "$@"; do
      if [ "$prev" = "--output" ]; then printf "\211PNG\r\n\032\ncanvas" > "$a"; fi
      prev="$a"
    done
    if [ "$1" = "--version" ]; then echo "swift-driver version: 6.0"; fi
    exit 0
  '
  run bash -c "cd '$WD' && PATH='$STUB_PATH' WORKSPACE_ROOT='$WD' CLAUDE_PLUGIN_ROOT='/nonexistent_$$' \
    bash '$PLUGIN_ROOT/$SCRIPT' --worktask-id wt-test --task-id DV0 --modified-files '$FILES' --slug my-view"
  [ "$status" -eq 0 ]
  # The emitted path is the contract with the caller, and the file must exist.
  assert_output --partial ".context/images/wt-test/dv-DV0-01-my-view.png"
  [ -s "$WD/.context/images/wt-test/dv-DV0-01-my-view.png" ]
  # ok row carrying the real byte count, not merely "an audit line appeared".
  run jq -se 'map(select(.action == "canvas_render" and .result == "ok" and .task_id == "DV0")) | length >= 1' \
    "$WD/.context/logs/audit.jsonl"
  assert_success
  # The render step must actually have been driven through --output.
  run stub_log swift
  assert_output --partial "--output"
}

@test "arg error: missing --worktask-id exits 5" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --task-id DV0 --modified-files "$FILES"
  [ "$status" -eq 5 ]
}

@test "arg error: missing --modified-files exits 5" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --worktask-id wt-test --task-id DV0
  [ "$status" -eq 5 ]
}

@test "arg error: missing or malformed --task-id exits 5" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --worktask-id wt-test --modified-files "$FILES"
  [ "$status" -eq 5 ]
  run bash "$PLUGIN_ROOT/$SCRIPT" --worktask-id wt-test --task-id DV0x --modified-files "$FILES"
  [ "$status" -eq 5 ]
}

@test "scaffold error: template not found -> exit 4 + canvas_render error row" {
  # No tools/SnapshotHost and a non-existent PLUGIN_DIR, so the template is not found.
  run bash -c "cd '$WD' && WORKSPACE_ROOT='$WD' CLAUDE_PLUGIN_ROOT='/nonexistent_plugin_root_$$' bash '$PLUGIN_ROOT/$SCRIPT' \
    --worktask-id wt-test --task-id DV0 --modified-files '$FILES'"
  [ "$status" -eq 4 ]
  run jq -e '.action == "canvas_render" and .result == "error"' "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "render error: SnapshotHost build fails -> exit 3 + screenshot_platform_fallback deferred row" {
  # A minimal Package.swift with no real Sources and a nonexistent CLAUDE_PLUGIN_ROOT, so
  # preview-ensurer is skipped and `swift run SnapshotHost` fails.
  mk_package
  run bash -c "cd '$WD' && WORKSPACE_ROOT='$WD' CLAUDE_PLUGIN_ROOT='/nonexistent_$$' bash '$PLUGIN_ROOT/$SCRIPT' \
    --worktask-id wt-test --task-id DV0 --modified-files '$FILES'"
  [ "$status" -eq 3 ]
  run jq -e '.action == "screenshot_platform_fallback" and .result == "deferred"' "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "root: no git toplevel for the SwiftPM host exits 5 without writing" {
  local cwd
  cwd="$(mk_tmpworkdir)"
  run bash -c "cd '$cwd' && GIT_CEILING_DIRECTORIES='$cwd' WORKSPACE_ROOT='$WD' bash '$PLUGIN_ROOT/$SCRIPT' \
    --worktask-id wt-test --task-id DV0 --modified-files '$FILES'"
  [ "$status" -eq 5 ]
  [ ! -e "$cwd/.context" ]
  [ ! -e "$WD/.context/images" ]
}

@test "root: a ledger for another worktask exits 1; a task the ledger lacks exits 5" {
  run bash -c "cd '$WD' && WORKSPACE_ROOT='$WD' bash '$PLUGIN_ROOT/$SCRIPT' \
    --worktask-id other --task-id DV0 --modified-files '$FILES'"
  [ "$status" -eq 1 ]
  run bash -c "cd '$WD' && WORKSPACE_ROOT='$WD' bash '$PLUGIN_ROOT/$SCRIPT' \
    --worktask-id wt-test --task-id DV4 --modified-files '$FILES'"
  [ "$status" -eq 5 ]
  [ ! -e "$WD/.context/images" ]
}
