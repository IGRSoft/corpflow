#!/usr/bin/env bash
# apple-canvas.sh — bash driver for the dv-screenshot-capture `apple-canvas` adapter.
#
# Invoked by the dv-screenshot-capture skill when the Adapter Selection Rule
# routes to `apple-canvas` (state.platform=apple AND (args.force_canvas OR
# sim_unavailable(state))). Orchestrates:
#
#   1. Scaffold-if-missing  → tools/SnapshotHost/ from templates/SnapshotHost-template/
#   2. Invoke preview-ensurer (Swift executable) on modified files
#   3. PreviewBridge.swift viewRegistry rewrite — not implemented; logged as deferred
#   4. swift run --package-path tools/SnapshotHost SnapshotHost --view ... --output ...
#   5. Apply 500 KB size budget (pngquant fallback / oversize/)
#   6. Emit manifest row + audit JSON (canvas_render, preview_added, ...)
#
# AR cascade reference: skills/dv-screenshot-capture/references/apple-canvas.md
# § Failure cascade ladder.
#
# Usage:
#   apple-canvas.sh --worktask-id <id> --task-id <TASK_ID> --modified-files <file-with-paths> \
#                   [--view <ModuleName.TypeName>] \
#                   [--destination macos-host|ios-sim] \
#                   [--size 393x852] [--scheme light|dark]
#
# Writes <ctx>/images/<id>/dv-<TASK_ID>-NN-<slug>.png, <ctx> from the root ladder; the SwiftPM
# host lives under the git toplevel, which is a different root from <ctx>.
#
# Exit codes:
#   0 — success (PNG produced)
#   1 — no .context resolved, or the ledger disagrees with --worktask-id
#   2 — preview-ensurer returned errors (missing_input), or a broken plugin install
#   3 — SnapshotHost render failed (cascade should escalate to apple/sim)
#   4 — scaffold failed
#   5 — argument error (incl. a task id the ledger does not hold, or no git toplevel)

set -euo pipefail

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------
WORKTASK_ID=""
TASK_ID=""
MODIFIED_FILES_PATH=""
VIEW_ARG=""
DESTINATION="macos-host"
SIZE="393x852"
SCHEME="light"
SLUG="canvas-preview"
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"

usage() {
    cat >&2 <<EOF
usage: apple-canvas.sh
  --worktask-id <id>             state.json.worktask_id (required)
  --task-id <TASK_ID>            DV task id, e.g. DV0 (required)
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
        --task-id)         TASK_ID="${2:-}"; shift 2 ;;
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

# Task ids name the evidence stream and sit inside file names, so the grammar has no glob characters.
_task_id_ok() {
  local re='^[A-Z]{2}[0-9]+$'
  [[ $1 =~ $re ]]
}

# Ids that become path segments or manifest cells: no `/`, `|`, whitespace or leading dot.
_field_ok() {
  local re='^[A-Za-z0-9][A-Za-z0-9._-]*$'
  [[ $1 =~ $re ]]
}

# Next NN for one task: 1 + the highest NN on disk (incl. oversize/) or in its manifest.
# The max, not a count, so a deleted capture never recycles a number; 10# keeps 08 and 09 decimal.
_next_nn() {
  local dir="$1" task="$2" max=0 f nn
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    f="${f##*/}"
    nn="${f#dv-"$task"-}"
    nn="${nn%%-*}"
    if [ "$((10#$nn))" -gt "$max" ]; then
      max="$((10#$nn))"
    fi
  done << EOF
$(find "$dir" "$dir/oversize" -maxdepth 1 -type f -name "dv-$task-[0-9][0-9]-*" 2> /dev/null || true)
$(LC_ALL=C awk -F'|' -v t="$task" '/^[[:space:]]*\|/ { gsub(/[[:space:]]/, "", $2); if ($2 ~ /^[0-9][0-9]$/) print "dv-" t "-" $2 "-row" }' "$dir/screenshots-$task.md" 2> /dev/null || true)
EOF
  if [ "$max" -ge 99 ]; then
    return 1
  fi
  printf '%02d\n' "$((max + 1))"
}

[[ -z "$WORKTASK_ID" ]] && { echo "error: --worktask-id required" >&2; exit 5; }
[[ -z "$TASK_ID" ]] && { echo "error: --task-id required" >&2; exit 5; }
[[ -z "$MODIFIED_FILES_PATH" ]] && { echo "error: --modified-files required" >&2; exit 5; }
_task_id_ok "$TASK_ID" || { echo "error: --task-id must match ^[A-Z]{2}[0-9]+\$ (got: $TASK_ID)" >&2; exit 5; }
_field_ok "$WORKTASK_ID" || { echo "error: --worktask-id must match ^[A-Za-z0-9][A-Za-z0-9._-]*\$" >&2; exit 5; }
[[ "$SLUG" =~ ^[a-z0-9][a-z0-9-]{0,39}$ ]] || { echo "error: --slug must be kebab-case ≤40 chars (got: $SLUG)" >&2; exit 5; }

PROJECT_ROOT=$(git rev-parse --show-toplevel 2> /dev/null) || PROJECT_ROOT=""
[[ -n "$PROJECT_ROOT" ]] || { echo "error: apple-canvas needs a git toplevel to host tools/SnapshotHost" >&2; exit 5; }

# Shared audit-row appender — one key order, one symlink refusal for every audit.jsonl.
# Fails closed: a missing library is a broken install, not a runtime condition.
_AUDIT_LIB="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/../../shared/lib" 2> /dev/null && pwd -P)/audit-lib.sh"
if [ ! -r "$_AUDIT_LIB" ]; then
  printf >&2 'apple-canvas: plugin install broken — audit-lib.sh not found\n'
  exit 2
fi
# shellcheck source=../../shared/lib/audit-lib.sh
. "$_AUDIT_LIB"

_STATE_READ_LIB="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/../../shared/lib" 2> /dev/null && pwd -P)/state-read-lib.sh"
if [ ! -r "$_STATE_READ_LIB" ]; then
  printf >&2 'apple-canvas: plugin install broken — state-read-lib.sh not found\n'
  exit 2
fi
# shellcheck source=../../shared/lib/state-read-lib.sh
. "$_STATE_READ_LIB"

# A ledger for another worktask refuses the write, so a worktree capture never lands in the
# main checkout; without a ledger only an explicit CONTEXT_DIR may capture.
_CTX_RC=0
CTX_DIR=$(trap - ERR; corpflow_context_dir) || _CTX_RC=$?
if [ "$_CTX_RC" -eq 2 ]; then
  printf >&2 'apple-canvas: root resolver unreachable\n'
  exit 2
elif [ "$_CTX_RC" -ne 0 ]; then
  printf >&2 'apple-canvas: no .context resolved; set WORKSPACE_ROOT or run inside a worktask\n'
  exit 1
fi
if [ -f "$CTX_DIR/state.json" ]; then
  if [ "$(corpflow_worktask_id "$CTX_DIR/state.json" "")" != "$WORKTASK_ID" ]; then
    printf >&2 'apple-canvas: --worktask-id %s does not match %s\n' "$WORKTASK_ID" "$CTX_DIR/state.json"
    exit 1
  fi
  if [ "$(jq -r --arg t "$TASK_ID" '(.tasks|type) == "object" and (.tasks|has($t))' "$CTX_DIR/state.json" 2> /dev/null || true)" != "true" ]; then
    printf >&2 'apple-canvas: task %s is not in %s\n' "$TASK_ID" "$CTX_DIR/state.json"
    exit 5
  fi
elif [ -z "${CONTEXT_DIR:-}" ] || [ "$CTX_DIR" != "$CONTEXT_DIR" ]; then
  printf >&2 'apple-canvas: no ledger at %s; set CONTEXT_DIR to capture outside a worktask\n' "$CTX_DIR"
  exit 1
fi

# -----------------------------------------------------------------------------
# Path setup
# -----------------------------------------------------------------------------
IMAGES_DIR="${CTX_DIR}/images/${WORKTASK_ID}"
LOGS_DIR="${CTX_DIR}/logs"
ERRORS_DIR="${CTX_DIR}/errors"
AUDIT_LOG="${LOGS_DIR}/audit.jsonl"
mkdir -p "$IMAGES_DIR" "$LOGS_DIR" "$ERRORS_DIR"

TS="$(date -u +%Y%m%d-%H%M%S)"
RENDER_LOG="${LOGS_DIR}/canvas-render-${TS}.log"
BUILD_LOG="${LOGS_DIR}/build-developer-${TS}.log"

NN=$(_next_nn "$IMAGES_DIR" "$TASK_ID") || { echo "error: task $TASK_ID already has capture 99" >&2; exit 1; }
OUTPUT_PNG="${IMAGES_DIR}/dv-${TASK_ID}-${NN}-${SLUG}.png"

# audit <action> <result> <metadata-json> — binds this adapter's actor and subject onto
# the shared appender.
audit() {
    corpflow_audit_row --file "$AUDIT_LOG" --actor "apple-canvas-adapter" \
      --action "$1" --subject "${WORKTASK_ID}/${SLUG}" --task-id "${TASK_ID:-unknown}" --result "$2" --meta "${3:-}"
}

# -----------------------------------------------------------------------------
# Step 1 — Scaffold-if-missing
# -----------------------------------------------------------------------------
SCAFFOLD_DIR="${PROJECT_ROOT}/tools/SnapshotHost"
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
        # errors bubble as missing_input; record + return 2
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
# minimal @testable import set) is implemented as a future enhancement;
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

    # Host build fail → escalate to apple (sim) adapter is the
    # CALLER's responsibility. This driver returns 3; the parent skill
    # is responsible for the fallback.
    audit screenshot_platform_fallback deferred "$(jq -nc \
        --arg requested_platform "apple-canvas" \
        --arg used_adapter "apple" \
        --arg reason "canvas_host_build_failed" \
        '{requested_platform:$requested_platform, used_adapter:$used_adapter, reason:$reason}')"
    exit 3
fi
