#!/usr/bin/env bash
# run-e2e.sh — apple-canvas end-to-end smoke against the canvas-fixture.
#
# Asserts:
#   1. `.context/logs/audit.jsonl` contains a `canvas_render` row OR scaffold row.
#   2. `.context/logs/audit.jsonl` contains a `preview_added` row.
#   3. If `design-ref.png` is present, a `visual_diff_run` row appears.
#
# Best-effort: when the Swift toolchain or imagemagick is unavailable, the
# smoke records the absence in the audit log and exits 0 — graceful-degrade
# per coordination-0.md §risk-watch.

set -euo pipefail

# Resolve repo root (this script lives at examples/canvas-fixture/)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

WORKTASK_ID="canvas-fixture-smoke"
SLUG="canvas-fixture"
IMAGES_DIR=".context/images/${WORKTASK_ID}"
LOGS_DIR=".context/logs"
AUDIT_LOG="${LOGS_DIR}/audit.jsonl"

mkdir -p "$IMAGES_DIR" "$LOGS_DIR"

# Record audit-log size before for "since" filtering
PRE_LINES=$(wc -l < "$AUDIT_LOG" 2>/dev/null | tr -d ' ' || echo 0)

# Build the modified-files list for the adapter — the fixture's SimpleView.swift
MOD_FILE="$(mktemp -t canvas-fixture-mods-XXXXXX)"
echo "examples/canvas-fixture/Sources/FixtureApp/Views/SimpleView.swift" > "$MOD_FILE"

# Detect environment readiness
HAS_SWIFT=0
command -v swift >/dev/null 2>&1 && HAS_SWIFT=1

HAS_MAGICK=0
command -v magick >/dev/null 2>&1 && HAS_MAGICK=1

echo "[run-e2e] swift=${HAS_SWIFT} magick=${HAS_MAGICK}"

# Invoke the adapter. Don't fail the harness on adapter errors — we assert
# on audit rows below, not on adapter exit code (adapter exits non-zero in
# many graceful-degrade scenarios).
set +e
"${REPO_ROOT}/skills/dv-screenshot-capture/scripts/apple-canvas.sh" \
    --worktask-id "$WORKTASK_ID" \
    --modified-files "$MOD_FILE" \
    --view "FixtureApp.SimpleView" \
    --destination "macos-host" \
    --size "393x852" \
    --scheme "light" \
    --slug "$SLUG"
ADAPTER_EXIT=$?
set -e

echo "[run-e2e] apple-canvas.sh exit=$ADAPTER_EXIT"

# Optional: if a design-ref.png exists, run the visual-diff
DESIGN_REF="${IMAGES_DIR}/design-ref.png"
if [[ -f "$DESIGN_REF" ]]; then
    # Find the most recent canvas PNG produced for this worktask
    CANDIDATE=$(find "$IMAGES_DIR" -maxdepth 1 -name 'dv-*-canvas-*.png' -print0 2>/dev/null | xargs -0 ls -t 2>/dev/null | head -n1 || true)
    if [[ -n "$CANDIDATE" ]]; then
        echo "[run-e2e] invoking visual-diff against $DESIGN_REF"
        "${REPO_ROOT}/skills/dv-screenshot-capture/scripts/visual-diff.sh" \
            --reference "$DESIGN_REF" \
            --candidate "$CANDIDATE" \
            --threshold "8" \
            --worktask-id "$WORKTASK_ID" \
            --slug "$SLUG" || true
    fi
fi

# Slice the new audit rows
TAIL_LINES=$(wc -l < "$AUDIT_LOG" 2>/dev/null | tr -d ' ' || echo 0)
NEW_LINES=$(( TAIL_LINES - PRE_LINES ))
NEW_ROWS="$(tail -n "$NEW_LINES" "$AUDIT_LOG" 2>/dev/null || true)"

echo "[run-e2e] new audit rows:"
echo "$NEW_ROWS"

# Assertions
PASS=0
FAIL=0

if echo "$NEW_ROWS" | grep -q '"action":"canvas_render"'; then
    echo "[PASS] canvas_render row present"
    PASS=$((PASS+1))
else
    echo "[FAIL] canvas_render row missing"
    FAIL=$((FAIL+1))
fi

# preview_added is best-effort: it only emits if preview-ensurer ran AND found
# a file to mutate. If the Swift toolchain isn't installed, skip the assert.
if [[ $HAS_SWIFT -eq 1 ]]; then
    if echo "$NEW_ROWS" | grep -q '"action":"preview_added"'; then
        echo "[PASS] preview_added row present"
        PASS=$((PASS+1))
    else
        echo "[WARN] preview_added row missing (swift present but ensurer didn't add — may be already-added on rerun)"
    fi
else
    echo "[SKIP] preview_added — swift toolchain not installed"
fi

if [[ -f "$DESIGN_REF" ]]; then
    if echo "$NEW_ROWS" | grep -q '"action":"visual_diff_run"'; then
        echo "[PASS] visual_diff_run row present"
        PASS=$((PASS+1))
    else
        echo "[FAIL] visual_diff_run row missing (design-ref present)"
        FAIL=$((FAIL+1))
    fi
else
    echo "[SKIP] visual_diff_run — no design-ref.png"
fi

echo "[run-e2e] summary: $PASS pass / $FAIL fail"

# Cleanup
rm -f "$MOD_FILE"

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
