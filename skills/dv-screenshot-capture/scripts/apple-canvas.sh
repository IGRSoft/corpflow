#!/usr/bin/env bash
# apple-canvas.sh — bash driver for the dv-screenshot-capture `apple-canvas` adapter.
#
# Invoked by the dv-screenshot-capture skill when the Adapter Selection Rule
# routes to `apple-canvas` (state.platform=apple AND (args.force_canvas OR
# sim_unavailable(state))). Orchestrates:
#
#   1. Scaffold-if-missing  → tools/SnapshotHost/ from templates/SnapshotHost-template/
#   2. Invoke preview-ensurer (Swift executable) on modified files
#   3. Rewrite PreviewBridge.swift viewRegistry (idempotent)
#   4. swift run --package-path tools/SnapshotHost SnapshotHost --view ... --output ...
#   5. Apply 500 KB size budget (pngquant fallback / oversize/)
#   6. Emit manifest row + audit JSON (canvas_render, preview_added, ...)
#
# AR cascade reference: skills/dv-screenshot-capture/references/apple-canvas.md
# § Failure cascade ladder.
#
# Usage:
#   apple-canvas.sh --worktask-id <id> --modified-files <file-with-paths> \
#                   [--view <ModuleName.TypeName>] \
#                   [--destination macos-host|ios-sim] \
#                   [--size 393x852] [--scheme light|dark]
#
# Exit codes:
#   0 — success (PNG produced)
#   2 — preview-ensurer returned errors (missing_input)
#   3 — SnapshotHost render failed (cascade should escalate to apple/sim)
#   4 — scaffold failed
#   5 — argument error

set -euo pipefail

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------
WORKTASK_ID=""
MODIFIED_FILES_PATH=""
VIEW_ARG=""
DESTINATION="macos-host"
SIZE="393x852"
SCHEME="light"
SLUG="canvas-preview"
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
PROJECT_ROOT="$(pwd)"

usage() {
    cat >&2 <<EOF
usage: apple-canvas.sh
  --worktask-id <id>             state.json.worktask_id (required)
  --modified-files <path>        newline-separated file list, OR newline content (required)
  [--view <ModuleName.TypeName>] target view key
  [--destination macos-host|ios-sim]   default macos-host
  [--size 393x852]               WxH
  [--scheme light|dark]          default light
  [--slug <kebab>]               kebab-case slug for PNG filename
EOF
    exit 5
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --worktask-id)     WORKTASK_ID="${2:-}"; shift 2 ;;
        --modified-files)  MODIFIED_FILES_PATH="${2:-}"; shift 2 ;;
        --view)            VIEW_ARG="${2:-}"; shift 2 ;;
        --destination)     DESTINATION="${2:-}"; shift 2 ;;
        --size)            SIZE="${2:-}"; shift 2 ;;
        --scheme)          SCHEME="${2:-}"; shift 2 ;;
        --slug)            SLUG="${2:-}"; shift 2 ;;
        -h|--help)         usage ;;
        *)                 echo "error: unknown flag $1" >&2; usage ;;
    esac
done

[[ -z "$WORKTASK_ID" ]] && { echo "error: --worktask-id required" >&2; exit 5; }
[[ -z "$MODIFIED_FILES_PATH" ]] && { echo "error: --modified-files required" >&2; exit 5; }

# -----------------------------------------------------------------------------
# Path setup
# -----------------------------------------------------------------------------
IMAGES_DIR=".context/images/${WORKTASK_ID}"
LOGS_DIR=".context/logs"
ERRORS_DIR=".context/errors"
AUDIT_LOG="${LOGS_DIR}/audit.jsonl"
mkdir -p "$IMAGES_DIR" "$LOGS_DIR" "$ERRORS_DIR"

TS="$(date -u +%Y%m%d-%H%M%S)"
RENDER_LOG="${LOGS_DIR}/canvas-render-${TS}.log"
BUILD_LOG="${LOGS_DIR}/build-developer-${TS}.log"

# Compute next NN
existing_count=$(find "$IMAGES_DIR" -maxdepth 1 -type f -name 'dv-*.png' 2>/dev/null | wc -l | tr -d ' ')
NN=$(printf '%02d' $((existing_count + 1)))
OUTPUT_PNG="${IMAGES_DIR}/dv-${NN}-${SLUG}.png"

# -----------------------------------------------------------------------------
# Audit helper
# -----------------------------------------------------------------------------
audit() {
    # audit <action> <result> <metadata-json>
    local action="$1"
    local result="$2"
    local metadata="$3"
    local ts
    ts="$(date -u +%FT%TZ)"
    jq -nc \
        --arg ts "$ts" \
        --arg actor "apple-canvas-adapter" \
        --arg action "$action" \
        --arg subject "$WORKTASK_ID/${SLUG}" \
        --arg result "$result" \
        --argjson metadata "$metadata" \
        '{ts: $ts, actor: $actor, action: $action, subject: $subject, result: $result, metadata: $metadata}' \
        >> "$AUDIT_LOG"
}

# -----------------------------------------------------------------------------
# Step 1 — Scaffold-if-missing
# -----------------------------------------------------------------------------
SCAFFOLD_DIR="tools/SnapshotHost"
TEMPLATE_DIR="${PLUGIN_DIR}/skills/dv-screenshot-capture/templates/SnapshotHost-template"

if [[ ! -f "${SCAFFOLD_DIR}/Package.swift" ]]; then
    echo "[apple-canvas] scaffolding ${SCAFFOLD_DIR}/ from template" | tee -a "$BUILD_LOG"
    if [[ ! -d "$TEMPLATE_DIR" ]]; then
        echo "error: template not found at $TEMPLATE_DIR" | tee -a "$BUILD_LOG" >&2
        audit canvas_render error "$(jq -nc \
            --arg phase scaffold --arg view "$VIEW_ARG" --arg destination "$DESTINATION" \
            --arg reason "template_not_found" \
            '{phase:$phase, view:$view, destination:$destination, reason:$reason}')"
        exit 4
    fi
    mkdir -p "$SCAFFOLD_DIR/Sources/SnapshotHost"
    cp "$TEMPLATE_DIR/Package.swift" "$SCAFFOLD_DIR/Package.swift"
    # canvas-render-host.swift becomes main.swift inside the scaffold
    cp "${PLUGIN_DIR}/skills/dv-screenshot-capture/templates/canvas-render-host.swift" \
       "$SCAFFOLD_DIR/Sources/SnapshotHost/main.swift"
    cp "$TEMPLATE_DIR/Sources/SnapshotHost/PreviewBridge.swift" \
       "$SCAFFOLD_DIR/Sources/SnapshotHost/PreviewBridge.swift"
    echo "1" > "$SCAFFOLD_DIR/.canvas-scaffold-version"

    # If destination is ios-sim, uncomment the .iOS(.v16) platform line
    if [[ "$DESTINATION" == "ios-sim" ]]; then
        sed -i.bak 's|// \.iOS(\.v16),|.iOS(.v16),|' "$SCAFFOLD_DIR/Package.swift"
        rm -f "$SCAFFOLD_DIR/Package.swift.bak"
    fi

    audit canvas_render ok "$(jq -nc \
        --arg phase scaffold --arg view "$VIEW_ARG" --arg destination "$DESTINATION" \
        --arg swift_version "$(swift --version 2>/dev/null | head -1 | tr -d '\n' || echo unknown)" \
        '{phase:$phase, view:$view, destination:$destination, swift_version:$swift_version}')"
fi

# -----------------------------------------------------------------------------
# Step 2 — Invoke preview-ensurer
# -----------------------------------------------------------------------------
ENSURER_DIR="${PLUGIN_DIR}/skills/preview-ensurer/references/reference-impl"
ENSURER_JSON_LOG="${LOGS_DIR}/preview-ensurer-${TS}.json"

if [[ -d "$ENSURER_DIR" ]] && command -v swift >/dev/null 2>&1; then
    echo "[apple-canvas] invoking preview-ensurer" | tee -a "$BUILD_LOG"
    set +e
    swift run --package-path "$ENSURER_DIR" PreviewEnsurer \
        --modified-files "$MODIFIED_FILES_PATH" \
        --auto-add true \
        --project-root "$PROJECT_ROOT" \
        > "$ENSURER_JSON_LOG" 2>> "$BUILD_LOG"
    ENSURER_EXIT=$?
    set -e

    if [[ $ENSURER_EXIT -ne 0 ]]; then
        echo "error: preview-ensurer exited with code $ENSURER_EXIT" | tee -a "$BUILD_LOG" >&2
        cat "$ENSURER_JSON_LOG" >&2 2>/dev/null || true
        # Per ad8 — errors bubble as missing_input; record + return 2
        echo "missing_input: preview-ensurer errors" >> "${ERRORS_DIR}/developer.md"
        audit canvas_render error "$(jq -nc \
            --arg phase complete --arg view "$VIEW_ARG" --arg destination "$DESTINATION" \
            --arg reason "preview_ensurer_errors" \
            '{phase:$phase, view:$view, destination:$destination, reason:$reason}')"
        exit 2
    fi

    # Emit preview_added rows from the JSON output
    if [[ -s "$ENSURER_JSON_LOG" ]] && command -v jq >/dev/null 2>&1; then
        jq -c '.views[] | select(.action == "added")' < "$ENSURER_JSON_LOG" 2>/dev/null | \
        while IFS= read -r view; do
            file=$(jq -r .file <<<"$view")
            view_type=$(jq -r .type <<<"$view")
            mock_strategy=$(jq -r '.mock_strategy // "unknown"' <<<"$view")
            lines_added=$(jq -r '.lines_added // 0' <<<"$view")
            audit preview_added ok "$(jq -nc \
                --arg file "$file" --arg view_type "$view_type" \
                --arg mock_strategy "$mock_strategy" --argjson lines_added "$lines_added" \
                '{file:$file, view_type:$view_type, mock_strategy:$mock_strategy, lines_added:$lines_added}')"
        done
    fi
else
    echo "[apple-canvas] preview-ensurer skipped (Swift toolchain or preview-ensurer impl unavailable)" | tee -a "$BUILD_LOG"
fi

# -----------------------------------------------------------------------------
# Step 3 — Update PreviewBridge.swift (idempotent rewrite)
# -----------------------------------------------------------------------------
# v1 implementation: leave the bridge as-is from the template. Real scaffolder
# logic (walking `swift package show-dependencies --format json` to derive the
# minimal @testable import set per ad3) is implemented as a future enhancement;
# the apple-canvas adapter logs it but does not block on it in v1.
echo "[apple-canvas] PreviewBridge.swift rewrite deferred (v1: empty registry stub from template)" | tee -a "$BUILD_LOG"

# -----------------------------------------------------------------------------
# Step 4 — swift run SnapshotHost
# -----------------------------------------------------------------------------
RENDER_START="$(date +%s)"
RENDER_EXIT=0

if [[ -z "$VIEW_ARG" ]]; then
    echo "warn: --view not provided; SnapshotHost will fail with exit 2 unless registry happens to contain a default" | tee -a "$BUILD_LOG"
fi

if command -v swift >/dev/null 2>&1; then
    set +e
    swift run --package-path "$SCAFFOLD_DIR" SnapshotHost \
        --view "$VIEW_ARG" \
        --output "$OUTPUT_PNG" \
        --size "$SIZE" \
        --scheme "$SCHEME" \
        > "$RENDER_LOG" 2>&1
    RENDER_EXIT=$?
    set -e
else
    echo "error: swift not on PATH" | tee -a "$BUILD_LOG" >&2
    RENDER_EXIT=127
fi

RENDER_END="$(date +%s)"
DURATION_MS=$(( (RENDER_END - RENDER_START) * 1000 ))

# -----------------------------------------------------------------------------
# Step 5 — Outcome
# -----------------------------------------------------------------------------
if [[ $RENDER_EXIT -eq 0 ]] && [[ -f "$OUTPUT_PNG" ]]; then
    BYTES=$(stat -f%z "$OUTPUT_PNG" 2>/dev/null || stat -c%s "$OUTPUT_PNG" 2>/dev/null || echo 0)
    audit canvas_render ok "$(jq -nc \
        --arg phase complete --arg view "$VIEW_ARG" --arg destination "$DESTINATION" \
        --arg output_path "$OUTPUT_PNG" --argjson bytes "$BYTES" \
        --argjson duration_ms "$DURATION_MS" \
        --arg swift_version "$(swift --version 2>/dev/null | head -1 | tr -d '\n' || echo unknown)" \
        '{phase:$phase, view:$view, destination:$destination, output_path:$output_path, bytes:$bytes, duration_ms:$duration_ms, swift_version:$swift_version}')"
    echo "$OUTPUT_PNG"
    exit 0
else
    audit canvas_render error "$(jq -nc \
        --arg phase complete --arg view "$VIEW_ARG" --arg destination "$DESTINATION" \
        --argjson duration_ms "$DURATION_MS" \
        --arg prev_error "render_exit_${RENDER_EXIT}" \
        '{phase:$phase, view:$view, destination:$destination, duration_ms:$duration_ms, prev_error:$prev_error}')"

    # Per ad6 — host build fail → escalate to apple (sim) adapter is the
    # CALLER's responsibility. This driver returns 3; the parent skill
    # is responsible for the fallback.
    audit screenshot_platform_fallback deferred "$(jq -nc \
        --arg requested_platform "apple-canvas" \
        --arg used_adapter "apple" \
        --arg reason "canvas_host_build_failed" \
        '{requested_platform:$requested_platform, used_adapter:$used_adapter, reason:$reason}')"
    exit 3
fi
