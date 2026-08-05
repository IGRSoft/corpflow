#!/usr/bin/env bats
# tests/shell/dv-screenshot/apple-canvas.bats — DV0c
# Target: skills/dv-screenshot-capture/scripts/apple-canvas.sh
# Covers: missing required args → exit 5, template absent → exit 4,
#         swift absent → exit 3 (render failed).
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/dv-screenshot-capture/scripts/apple-canvas.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/.context/logs" "$WD/.context/errors"
}

# ---------------------------------------------------------------------------

@test "happy: a successful render exits 0, writes the PNG and records an ok row" {
  # Carried from DV2/DV3: every other test here drives a failure path, so the
  # success path — the one that actually produces the DV evidence artifact — was
  # never executed. The toolchain double is `swift`, not `xcrun`: this script
  # shells out to `swift run --package-path … SnapshotHost --output <png>` and
  # never invokes xcrun (the carried item's premise was wrong on that point).
  mkdir -p "$WD/tools/SnapshotHost/Sources/SnapshotHost" "$WD/.context/images/wt-test"
  cat > "$WD/tools/SnapshotHost/Package.swift" << 'PKGEOF'
// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "SnapshotHost", targets: [.executableTarget(name: "SnapshotHost")])
PKGEOF
  FILES="$WD/files.txt"
  printf 'src/Foo.swift\n' > "$FILES"
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
  run bash -c "cd '$WD' && PATH='$STUB_PATH' CLAUDE_PLUGIN_ROOT='/nonexistent_$$' \
    bash '$PLUGIN_ROOT/$SCRIPT' --worktask-id wt-test --modified-files '$FILES' --slug my-view"
  [ "$status" -eq 0 ]
  # The emitted path is the contract with the caller, and the file must exist.
  assert_output --partial ".context/images/wt-test/dv-01-my-view.png"
  [ -s "$WD/.context/images/wt-test/dv-01-my-view.png" ]
  # ok row carrying the real byte count, not merely "an audit line appeared".
  run jq -se 'map(select(.action == "canvas_render" and .result == "ok")) | length >= 1' \
    "$WD/.context/logs/audit.jsonl"
  assert_success
  # The render step must actually have been driven through --output.
  run stub_log swift
  assert_output --partial "--output"
}

@test "arg error: missing --worktask-id exits 5" {
  # Provide --modified-files but omit --worktask-id
  FILES="$WD/files.txt"
  printf 'src/Foo.swift\n' > "$FILES"
  run bash "$PLUGIN_ROOT/$SCRIPT" --modified-files "$FILES"
  [ "$status" -eq 5 ]
}

@test "arg error: missing --modified-files exits 5" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --worktask-id wt-test
  [ "$status" -eq 5 ]
}

@test "scaffold error: template not found -> exit 4 + canvas_render error row" {
  # Run from WD (no tools/SnapshotHost present) with a non-existent PLUGIN_DIR
  # so the template is not found → exit 4.
  FILES="$WD/files.txt"
  printf 'src/Foo.swift\n' > "$FILES"
  run bash -c "cd '$WD' && CLAUDE_PLUGIN_ROOT='/nonexistent_plugin_root_$$' bash '$PLUGIN_ROOT/$SCRIPT' \
    --worktask-id wt-test --modified-files '$FILES'"
  [ "$status" -eq 4 ]
  # Audit log must exist with a canvas_render error row
  run jq -e '.action == "canvas_render" and .result == "error"' "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "render error: SnapshotHost build fails -> exit 3 + screenshot_platform_fallback deferred row" {
  # Scaffold tools/SnapshotHost with a minimal Package.swift (no real Sources),
  # point CLAUDE_PLUGIN_ROOT to a nonexistent path so preview-ensurer step is
  # skipped, then swift run SnapshotHost will fail → exit 3.
  mkdir -p "$WD/tools/SnapshotHost/Sources/SnapshotHost"
  cat > "$WD/tools/SnapshotHost/Package.swift" << 'PKGEOF'
// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "SnapshotHost", targets: [.executableTarget(name: "SnapshotHost")])
PKGEOF
  FILES="$WD/files.txt"
  printf 'src/Foo.swift\n' > "$FILES"
  run bash -c "cd '$WD' && CLAUDE_PLUGIN_ROOT='/nonexistent_$$' bash '$PLUGIN_ROOT/$SCRIPT' \
    --worktask-id wt-test --modified-files '$FILES'"
  [ "$status" -eq 3 ]
  # screenshot_platform_fallback deferred row must be present
  run jq -e '.action == "screenshot_platform_fallback" and .result == "deferred"' "$WD/.context/logs/audit.jsonl"
  assert_success
}
