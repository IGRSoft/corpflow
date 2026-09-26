#!/usr/bin/env bash
# visual-diff.sh — RMSE visual-diff wrapper for QA stage.
#
# Compares a candidate PNG (typically a `dv-<TASK_ID>-NN-canvas-*.png` produced by the
# apple-canvas adapter) against a design reference using ImageMagick's
# `magick compare -metric RMSE`. Emits a `visual_diff_run` audit row.
#
# Graceful-degrade: if `magick` is not on PATH, emits an audit row with
# `imagemagick_not_found` and exits 0 (non-blocking — DV/QA do not fail
# the worktask on missing imagemagick).
#
# The diff PNG is saved only on a fail verdict (5-screenshot budget
# hygiene). Pass verdicts emit no diff artifact.
#
# Usage:
#   visual-diff.sh
#     --reference <design-ref.png>      reference image (required)
#     --candidate <dv-<TASK_ID>-NN-*.png>  candidate to compare (required)
#     [--threshold 8]                   RMSE percent threshold (default 8.0)
#     [--worktask-id <id>]              worktask_id (for audit subject + diff path)
#     [--slug <kebab>]                  slug used in diff filename if saved
#
# Exit codes:
#   0  — success (regardless of verdict — verdict carried in audit row)
#   1  — no .context resolved (root ladder, never cwd), or --worktask-id disagrees with the ledger
#   2  — argument error, or a broken plugin install
#   3  — magick invocation failed unexpectedly

set -euo pipefail

REFERENCE=""
CANDIDATE=""
THRESHOLD="8.0"
WORKTASK_ID=""
SLUG="diff"

usage() {
    cat >&2 <<EOF
usage: visual-diff.sh
  --reference <png>     reference image (required)
  --candidate <png>     candidate image (required)
  [--threshold N]       RMSE percent (default 8.0)
  [--worktask-id <id>]  for audit subject + diff path
  [--slug <kebab>]      for diff filename
EOF
    exit 2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --reference)    REFERENCE="${2:-}";    shift 2 ;;
        --candidate)    CANDIDATE="${2:-}";    shift 2 ;;
        --threshold)    THRESHOLD="${2:-}";    shift 2 ;;
        --worktask-id)  WORKTASK_ID="${2:-}";  shift 2 ;;
        --slug)         SLUG="${2:-}";         shift 2 ;;
        -h|--help)      usage ;;
        *)              echo "error: unknown flag $1" >&2; usage ;;
    esac
done

[[ -z "$REFERENCE" || -z "$CANDIDATE" ]] && usage
[[ -z "$WORKTASK_ID" || "$WORKTASK_ID" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || usage
[[ "$SLUG" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || usage

# Shared audit-row appender — one key order, one symlink refusal for every audit.jsonl.
# Fails closed: a missing library is a broken install, not a runtime condition.
_AUDIT_LIB="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/../../shared/lib" 2> /dev/null && pwd -P)/audit-lib.sh"
if [ ! -r "$_AUDIT_LIB" ]; then
  printf >&2 'visual-diff: plugin install broken — audit-lib.sh not found\n'
  exit 2
fi
# shellcheck source=../../shared/lib/audit-lib.sh
. "$_AUDIT_LIB"

_STATE_READ_LIB="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/../../shared/lib" 2> /dev/null && pwd -P)/state-read-lib.sh"
if [ ! -r "$_STATE_READ_LIB" ]; then
  printf >&2 'visual-diff: plugin install broken — state-read-lib.sh not found\n'
  exit 2
fi
# shellcheck source=../../shared/lib/state-read-lib.sh
. "$_STATE_READ_LIB"

# The ledger names the worktask when --worktask-id is omitted; a different explicit id is refused.
_CTX_RC=0
CTX_DIR=$(trap - ERR; corpflow_context_dir) || _CTX_RC=$?
if [ "$_CTX_RC" -eq 2 ]; then
  printf >&2 'visual-diff: root resolver unreachable\n'
  exit 2
elif [ "$_CTX_RC" -ne 0 ]; then
  printf >&2 'visual-diff: no .context resolved; set WORKSPACE_ROOT or run inside a worktask\n'
  exit 1
fi
if [ -f "$CTX_DIR/state.json" ]; then
  _LEDGER_WID="$(corpflow_worktask_id "$CTX_DIR/state.json" "")"
  [[ -n "$WORKTASK_ID" ]] || WORKTASK_ID="$_LEDGER_WID"
  if [[ -z "$WORKTASK_ID" || "$WORKTASK_ID" != "$_LEDGER_WID" ]]; then
    printf >&2 'visual-diff: --worktask-id %s does not match %s\n' "$WORKTASK_ID" "$CTX_DIR/state.json"
    exit 1
  fi
elif [ -z "${CONTEXT_DIR:-}" ] || [ "$CTX_DIR" != "$CONTEXT_DIR" ]; then
  printf >&2 'visual-diff: no ledger at %s; set CONTEXT_DIR to run outside a worktask\n' "$CTX_DIR"
  exit 1
fi
[[ -n "$WORKTASK_ID" ]] || WORKTASK_ID="default"

LOGS_DIR="${CTX_DIR}/logs"
IMAGES_DIR="${CTX_DIR}/images/${WORKTASK_ID}"
AUDIT_LOG="${LOGS_DIR}/audit.jsonl"
mkdir -p "$LOGS_DIR" "$IMAGES_DIR"

# audit <action> <result> <metadata-json> — binds this adapter's actor and subject onto
# the shared appender.
audit() {
    corpflow_audit_row --file "$AUDIT_LOG" --actor "qa-visual-diff" \
      --action "$1" --subject "${WORKTASK_ID}/${SLUG}" --result "$2" --task-id unknown --meta "${3:-}"
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
# A suffixed name has no portable single-mktemp form (BSD substitutes only a trailing
# X-run, so "-XXXXXX.png" left the suffix literal and unrandomised) — name it inside a
# private temp dir instead and remove the whole dir on exit.
DIFF_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/visual-diff.XXXXXX")"
DIFF_TMP="$DIFF_TMP_DIR/diff.png"
trap 'rm -rf "$DIFF_TMP_DIR"' EXIT

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
