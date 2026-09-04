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

# --- manifest schema (REQ-8) --------------------------------------------------
# Presence alone used to pass the gate, so a manifest whose rows did not match the
# canonical 9-column table reached the consuming stage, which silently dropped the
# evidence. The schema verdict is delegated to attach-visual-evidence.sh so the
# grammar keeps exactly one parser.

_canonical_row() {
  printf '| # | Slug | Path | Bytes | Platform | Adapter | Caption | Captured | Design Ref |\n'
  printf '|---|------|------|-------|----------|---------|---------|----------|------------|\n'
  printf '| 01 | home | dv-01-home.png | 1234 | apple | sim | Home screen | 2026-01-01T00:00:00Z | - |\n'
}

@test "schema: a manifest whose rows miss the canonical schema blocks with a schema reason" {
  printf '%s' '{"version":1,"worktask_id":"wt-bad","metadata":{}}' > "$WD/.context/state.json"
  mkdir -p "$WD/.context/images/wt-bad"
  {
    printf '# screenshots\n\n'
    printf '| # | Path | Caption |\n|---|------|---------|\n'
    printf '| 1 | shot.png | too few columns |\n'
  } > "$WD/.context/images/wt-bad/screenshots.md"
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" < "$DEV_PAYLOAD"
  assert_success   # blocks via stdout JSON, exit stays 0
  echo "$output" | jq -e '
    .decision == "block"
    and (.reason | test("screenshot_manifest_schema"))
    and (.hookSpecificOutput.additionalContext | test("canonical 9-column"))
  '
  run jq -e '.action == "screenshot_gate_block"
             and .metadata.block_kind == "screenshot_manifest_schema"' \
    "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "schema: a canonical manifest passes the gate" {
  printf '%s' '{"version":1,"worktask_id":"wt-good","metadata":{}}' > "$WD/.context/state.json"
  mkdir -p "$WD/.context/images/wt-good"
  _canonical_row > "$WD/.context/images/wt-good/screenshots.md"
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" < "$DEV_PAYLOAD"
  assert_success
  [ -z "$output" ]
  run jq -e '.action == "screenshot_gate_pass"' "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "schema: a table-free manifest with NO captures beside it passes (genuine skip rationale)" {
  printf '%s' '{"version":1,"worktask_id":"wt-skip","metadata":{}}' > "$WD/.context/state.json"
  mkdir -p "$WD/.context/images/wt-skip"
  printf '# screenshots\n\nNo captures: headless CI, rationale recorded in development-0.md.\n' \
    > "$WD/.context/images/wt-skip/screenshots.md"
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" < "$DEV_PAYLOAD"
  assert_success
  [ -z "$output" ]
  run jq -e '.action == "screenshot_gate_pass"' "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "schema: AC-4 — a table-free manifest sitting beside real captures BLOCKS" {
  # The silent evidence drop REQ-8 exists to remove: the PNGs were captured, the manifest
  # references none of them, and every downstream stage sees "a manifest is present".
  printf '%s' '{"version":1,"worktask_id":"wt-drop","metadata":{}}' > "$WD/.context/state.json"
  mkdir -p "$WD/.context/images/wt-drop"
  printf '# screenshots\n\nHeadless CI, no captures.\n' \
    > "$WD/.context/images/wt-drop/screenshots.md"
  printf '\x89PNG\r\n\x1a\n' > "$WD/.context/images/wt-drop/dv-01-home.png"
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" < "$DEV_PAYLOAD"
  assert_success   # blocks via stdout JSON, exit stays 0
  echo "$output" | jq -e '.decision == "block" and (.reason | test("screenshot_manifest_schema"))'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("image file")'
  run jq -e '.metadata.block_kind == "screenshot_manifest_schema"' "$WD/.context/logs/audit.jsonl"
  assert_success
}

@test "schema: requires_screenshots=false never blocks even with captures and no rows" {
  printf '%s' '{"version":1,"worktask_id":"wt-noui3","metadata":{"requires_screenshots":false}}' \
    > "$WD/.context/state.json"
  mkdir -p "$WD/.context/images/wt-noui3"
  printf '# screenshots\n\nnone\n' > "$WD/.context/images/wt-noui3/screenshots.md"
  printf '\x89PNG\r\n\x1a\n' > "$WD/.context/images/wt-noui3/dv-01-home.png"
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" < "$DEV_PAYLOAD"
  assert_success
  [ -z "$output" ]
}

@test "schema: requires_screenshots=false skips the schema check entirely" {
  printf '%s' '{"version":1,"worktask_id":"wt-noui2","metadata":{"requires_screenshots":false}}' \
    > "$WD/.context/state.json"
  mkdir -p "$WD/.context/images/wt-noui2"
  printf '| 1 | broken |\n' > "$WD/.context/images/wt-noui2/screenshots.md"
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" < "$DEV_PAYLOAD"
  assert_success
  [ -z "$output" ]
}

@test "contract: --self-test passes (smoke, NON-counting)" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "self-test OK"
}

@test "SR: a symlinked audit.jsonl is refused on the block path" {
  printf '%s' '{"version":1,"worktask_id":"wt-sym","metadata":{}}' > "$WD/.context/state.json"
  mkdir -p "$WD/.context/logs" "$WD/target-dir"
  ln -s "$WD/target-dir/escaped.txt" "$WD/.context/logs/audit.jsonl"
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" < "$DEV_PAYLOAD"
  assert_success
  # The block itself must still travel: refusing the row never weakens the gate.
  echo "$output" | jq -e '.decision == "block"'
  [ ! -e "$WD/target-dir/escaped.txt" ]
}

@test "SR: a symlinked audit.jsonl is refused on the pass path" {
  printf '%s' '{"version":1,"worktask_id":"wt-sym2","metadata":{}}' > "$WD/.context/state.json"
  mkdir -p "$WD/.context/images/wt-sym2" "$WD/.context/logs" "$WD/target-dir"
  printf '# screenshots\n' > "$WD/.context/images/wt-sym2/screenshots.md"
  ln -s "$WD/target-dir/escaped.txt" "$WD/.context/logs/audit.jsonl"
  run env CLAUDE_PROJECT_DIR="$WD" bash "$PLUGIN_ROOT/$SCRIPT" < "$DEV_PAYLOAD"
  assert_success
  [ ! -e "$WD/target-dir/escaped.txt" ]
}
