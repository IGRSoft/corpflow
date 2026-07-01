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
