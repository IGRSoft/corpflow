#!/usr/bin/env bats
# Contract tests for skills/worktask/references/attach-visual-evidence.sh.
# Contracts (from header + body):
#   - --emit pr: requires_screenshots=false => empty stdout, audit reason=requires_screenshots_false
#   - --emit pr: requires_screenshots=true + no manifest/captures => empty stdout, audit reason=no_captures
#   - --emit pr: requires_screenshots=true + markdown-table manifest + co-located PNG + gist mock
#               => stdout contains "## Visual evidence" + "![dv-01 ...](<gist-url>)"
#   - missing/corrupt state.json => exit 1 (catastrophic)
#   - invalid usage (no mode, bad mode) => exit 1 + usage line
#   - --self-test => "fail=0", exit 0
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/references/attach-visual-evidence.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/.context/logs"
  # state.json with requires_screenshots=false for skip tests
  cat > "$WD/state-false.json" <<'EOS'
{"version":1,"worktask_id":"t","run_index":0,"metadata":{"requires_screenshots":false},"facts":{"goal":"test"}}
EOS
  # state.json with requires_screenshots=true for capture tests
  cat > "$WD/state-true.json" <<'EOS'
{"version":1,"worktask_id":"t","run_index":0,"metadata":{"requires_screenshots":true},"facts":{"goal":"test"}}
EOS
  # markdown-table manifest + co-located PNG (img_dir = dirname(MANIFEST_FILE))
  printf '\x89PNG\r\n\x1a\n' > "$WD/dv-01-test.png"
  cat > "$WD/screenshots.md" <<'EOS'
| # | slug | path | bytes | tool | adapter | caption | ts | ref |
|---|------|------|-------|------|---------|---------|----|----|
| 01 | test | dv-01-test.png | 100 | apple | sim | Login screen | 2026-01-01 | DV |
EOS
}

@test "happy: --emit pr with requires_screenshots=false produces empty stdout (exit 0)" {
  run env STATE_FILE="$WD/state-false.json" WORKSPACE_ROOT="$WD" \
    bash "$PLUGIN_ROOT/$SCRIPT" --emit pr
  assert_success
  # empty stdout — skip gate fires before any gh call
  assert_output ""
  # audit row records the skip
  run jq -r '.metadata.reason' <(tail -1 "$WD/.context/logs/audit.jsonl")
  assert_output "requires_screenshots_false"
}

@test "happy: --emit pr with captures + gist mock renders a Visual evidence block" {
  # Requires a markdown-table manifest and a co-located PNG.
  # GIST_VERIFY_FORCE=pass bypasses the anonymous HEAD probe.
  run env STATE_FILE="$WD/state-true.json" WORKSPACE_ROOT="$WD" \
    MANIFEST_FILE="$WD/screenshots.md" \
    ASSET_HOST_MODE=gist GIST_RAW_URL_BASE="https://mock.gist/raw" \
    GIST_VERIFY_FORCE=pass \
    bash "$PLUGIN_ROOT/$SCRIPT" --emit pr
  assert_success
  assert_output --partial "## Visual evidence"
  assert_output --partial "![dv-01 Login screen](https://mock.gist/raw/dv-01-test.png)"
  assert_output --partial "Manifest:"
}

@test "edge: --emit pr with true flag but no manifest/captures → empty stdout, audit no_captures" {
  # No MANIFEST_FILE set → manifest_path resolves to a non-existent path → no_captures.
  run env STATE_FILE="$WD/state-true.json" WORKSPACE_ROOT="$WD" \
    bash "$PLUGIN_ROOT/$SCRIPT" --emit pr
  assert_success
  assert_output ""
  run jq -r '.metadata.reason' <(tail -1 "$WD/.context/logs/audit.jsonl")
  assert_output "no_captures"
}

@test "failure: missing state.json is catastrophic (exit 1)" {
  run env STATE_FILE="$WD/state-missing.json" WORKSPACE_ROOT="$WD" \
    bash "$PLUGIN_ROOT/$SCRIPT" --emit pr
  assert_failure 1
  assert_output --partial "state unreadable"
}

@test "failure: no mode argument prints usage and exits 1" {
  run bash "$PLUGIN_ROOT/$SCRIPT"
  assert_failure 1
  assert_output --partial "usage:"
}

@test "contract: --self-test passes (smoke, NON-counting)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "fail=0"
}
