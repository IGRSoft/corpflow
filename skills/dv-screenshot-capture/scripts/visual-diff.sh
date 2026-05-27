#!/usr/bin/env bash
# visual-diff.sh — RMSE visual-diff wrapper for QA stage.
#
# Compares a candidate PNG (typically a `dv-NN-canvas-*.png` produced by the
# apple-canvas adapter) against a design reference using ImageMagick's
# `magick compare -metric RMSE`. Emits a `visual_diff_run` audit row.
#
# Graceful-degrade: if `magick` is not on PATH, emits an audit row with
# `imagemagick_not_found` and exits 0 (non-blocking — DV/QA must NOT fail
# the workflow on missing imagemagick per coordination-0.md §risk-watch).
#
# Per PL pd2 (and coordination-0.md): the diff PNG is saved ONLY on a fail
# verdict (5-screenshot budget hygiene). Pass verdicts emit no diff artifact.
#
# Usage:
#   visual-diff.sh
#     --reference <design-ref.png>      reference image (required)
#     --candidate <dv-NN-*.png>         candidate to compare (required)
#     [--threshold 8]                   RMSE percent threshold (default 8.0)
#     [--workflow-id <id>]              workflow_id (for audit subject + diff path)
#     [--slug <kebab>]                  slug used in diff filename if saved
#
# Exit codes:
#   0  — success (regardless of verdict — verdict carried in audit row)
#   2  — argument error
#   3  — magick invocation failed unexpectedly

set -euo pipefail

REFERENCE=""
CANDIDATE=""
THRESHOLD="8.0"
WORKFLOW_ID="default"
SLUG="diff"

usage() {
    cat >&2 <<EOF
usage: visual-diff.sh
  --reference <png>     reference image (required)
  --candidate <png>     candidate image (required)
  [--threshold N]       RMSE percent (default 8.0)
  [--workflow-id <id>]  for audit subject + diff path
  [--slug <kebab>]      for diff filename
EOF
    exit 2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --reference)    REFERENCE="${2:-}";    shift 2 ;;
        --candidate)    CANDIDATE="${2:-}";    shift 2 ;;
        --threshold)    THRESHOLD="${2:-}";    shift 2 ;;
        --workflow-id)  WORKFLOW_ID="${2:-}";  shift 2 ;;
        --slug)         SLUG="${2:-}";         shift 2 ;;
        -h|--help)      usage ;;
        *)              echo "error: unknown flag $1" >&2; usage ;;
    esac
done

[[ -z "$REFERENCE" || -z "$CANDIDATE" ]] && usage

LOGS_DIR=".context/logs"
IMAGES_DIR=".context/images/${WORKFLOW_ID}"
AUDIT_LOG="${LOGS_DIR}/audit.jsonl"
mkdir -p "$LOGS_DIR" "$IMAGES_DIR"

audit() {
    local action="$1"
    local result="$2"
    local metadata="$3"
    local ts
    ts="$(date -u +%FT%TZ)"
    jq -nc \
        --arg ts "$ts" \
        --arg actor "qa-visual-diff" \
        --arg action "$action" \
        --arg subject "${WORKFLOW_ID}/${SLUG}" \
        --arg result "$result" \
        --argjson metadata "$metadata" \
        '{ts: $ts, actor: $actor, action: $action, subject: $subject, result: $result, metadata: $metadata}' \
        >> "$AUDIT_LOG"
}

# Graceful-degrade if magick is not on PATH
if ! command -v magick >/dev/null 2>&1; then
    echo "warn: ImageMagick (magick) not on PATH; skipping visual diff" >&2
    audit visual_diff_run deferred "$(jq -nc \
        --arg reference "$REFERENCE" \
        --arg candidate "$CANDIDATE" \
        --arg metric "RMSE" \
        --argjson threshold_percent "${THRESHOLD}" \
        --arg verdict "skipped" \
        --arg reason "imagemagick_not_found" \
        '{reference:$reference, candidate:$candidate, metric:$metric, threshold_percent:$threshold_percent, verdict:$verdict, reason:$reason}')"
    exit 0
fi

# Sanity check the inputs exist
if [[ ! -f "$REFERENCE" ]]; then
    echo "warn: reference image not found: $REFERENCE" >&2
    audit visual_diff_run deferred "$(jq -nc \
        --arg reference "$REFERENCE" \
        --arg candidate "$CANDIDATE" \
        --arg metric "RMSE" \
        --argjson threshold_percent "${THRESHOLD}" \
        --arg verdict "skipped" \
        --arg reason "reference_not_found" \
        '{reference:$reference, candidate:$candidate, metric:$metric, threshold_percent:$threshold_percent, verdict:$verdict, reason:$reason}')"
    exit 0
fi

if [[ ! -f "$CANDIDATE" ]]; then
    echo "error: candidate image not found: $CANDIDATE" >&2
    audit visual_diff_run error "$(jq -nc \
        --arg reference "$REFERENCE" \
        --arg candidate "$CANDIDATE" \
        --arg metric "RMSE" \
        --argjson threshold_percent "${THRESHOLD}" \
        --arg verdict "error" \
        --arg reason "candidate_not_found" \
        '{reference:$reference, candidate:$candidate, metric:$metric, threshold_percent:$threshold_percent, verdict:$verdict, reason:$reason}')"
    exit 3
fi

# Run magick compare. RMSE output goes to stderr in the form:
#   <absolute> (<normalized>)
# Save the diff PNG to a temp path; we keep it only on fail (pd2).
DIFF_TMP="$(mktemp -t visual-diff-XXXXXX.png)"
trap 'rm -f "$DIFF_TMP"' EXIT

# magick compare returns:
#   0 on identical, 1 on differences, ≥2 on error
set +e
RMSE_RAW=$(magick compare -metric RMSE "$REFERENCE" "$CANDIDATE" "$DIFF_TMP" 2>&1)
MAGICK_EXIT=$?
set -e

if [[ $MAGICK_EXIT -ge 2 ]]; then
    echo "error: magick compare failed (exit $MAGICK_EXIT): $RMSE_RAW" >&2
    audit visual_diff_run error "$(jq -nc \
        --arg reference "$REFERENCE" \
        --arg candidate "$CANDIDATE" \
        --arg metric "RMSE" \
        --argjson threshold_percent "${THRESHOLD}" \
        --arg verdict "error" \
        --arg reason "magick_invocation_failed" \
        --arg raw "$RMSE_RAW" \
        '{reference:$reference, candidate:$candidate, metric:$metric, threshold_percent:$threshold_percent, verdict:$verdict, reason:$reason, magick_output:$raw}')"
    exit 3
fi

# Parse the normalized RMSE (parenthesized fraction 0..1) and convert to percent
NORMALIZED=$(awk '{for (i=1;i<=NF;i++) if ($i ~ /^\(/) {gsub(/[()]/,"",$i); print $i; exit}}' <<<"$RMSE_RAW")
if [[ -z "$NORMALIZED" ]]; then
    NORMALIZED="0"
fi
VALUE_PERCENT=$(awk -v v="$NORMALIZED" 'BEGIN { printf "%.4f", v * 100 }')

# Determine verdict (compare floats with awk)
VERDICT=$(awk -v v="$VALUE_PERCENT" -v t="$THRESHOLD" \
    'BEGIN { if (v + 0 <= t + 0) print "pass"; else print "fail_visual_diff" }')

# pd2: save diff PNG ONLY on fail
DIFF_PATH=""
if [[ "$VERDICT" == "fail_visual_diff" ]]; then
    TS=$(date -u +%Y%m%d-%H%M%S)
    DIFF_PATH="${IMAGES_DIR}/diff-${SLUG}-${TS}.png"
    cp "$DIFF_TMP" "$DIFF_PATH"
fi

audit visual_diff_run ok "$(jq -nc \
    --arg reference "$REFERENCE" \
    --arg candidate "$CANDIDATE" \
    --arg metric "RMSE" \
    --argjson value_percent "$VALUE_PERCENT" \
    --argjson threshold_percent "${THRESHOLD}" \
    --arg verdict "$VERDICT" \
    --arg diff_path "$DIFF_PATH" \
    '{reference:$reference, candidate:$candidate, metric:$metric, value_percent:$value_percent, threshold_percent:$threshold_percent, verdict:$verdict, diff_path:$diff_path}')"

# Print compact summary for the QA agent to read
echo "verdict=$VERDICT value=$VALUE_PERCENT% threshold=$THRESHOLD% diff_path=$DIFF_PATH"
exit 0
