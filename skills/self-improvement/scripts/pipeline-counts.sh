#!/usr/bin/env bash
# @file        pipeline-counts.sh
# @description Step 5b closing call of the self-improvement pipeline. Runs LAST on
#              every path — short-circuit, opt-out and missing-jq runs too — because it counts
#              rows in the OTHER stages' own output files, so the model never
#              supplies a number and a zero-row result is never silently read as
#              "the user made no edits" (SKILL.md § "An empty join is a silent
#              no-op").
#
#              Counts, each absent input file = 0, each via awk END{print n+0}
#              (never wc -l / grep -c, which mis-handle a file with no trailing
#              newline the same way a shell `read` loop would):
#                context_paths  --context-set  lines with NF>=1
#                changed_paths  --changes      TSV (-F'\t') rows with NF==3
#                mapped_rows    --mapped       TSV (-F'\t') rows with NF==5 and a
#                               numeric $2 (a DISCARD row never reaches this file,
#                               so no separate kept/discarded filter is needed)
#                appended_rows  --appended     line 1, must be an integer; a
#                               non-integer line counts 0 and warns on stderr
#
#              Emits nothing on stdout; appends one JSONL row to
#              <dataset dir>/pipeline-counts.jsonl (no row on the fallback rung or
#              under --dry-run — see plugin-data-lib.sh) and always prints one
#              counts line to stderr.
#
# @usage       pipeline-counts.sh --worktask-id=<id> --run-index=<n> \
#                --context-set=<f> --changes=<f> --mapped=<f> --appended=<f> \
#                [options]
#
# @arg --worktask-id=<id>  Worktask identifier (required; rejects '"' and '\')
# @arg --run-index=<n>     Non-negative integer (required)
# @arg --stage=<code>      Stage that produced the counted artifacts (default: ST)
# @arg --context-set=<f>   Step 1 output (build-context-set.sh) (required)
# @arg --changes=<f>       Step 2 output (detect-user-changes.sh) (required)
# @arg --mapped=<f>        Step 4 output (map-and-filter.sh) (required)
# @arg --appended=<f>      append-labels.sh's --count-out file (required)
# @arg --dataset=<file>    Explicit label-dataset path — see plugin-data-lib.sh
# @arg --plugin-data=<dir> Plugin data root — see plugin-data-lib.sh
# @arg --dry-run           Print the stderr counts line; write no row
# @arg --self-test         Run internal test suite; exit 0/non-zero
#
# @env SELF_IMPROVE_LABELS  Read verbatim into the row's labels_enabled field.
# @env CLAUDE_PROJECT_DIR   Passed through to plugin-data-lib.sh's fallback rung.
#
# @exitcode 0  success (including fallback-rung and --dry-run "no row" runs)
# @exitcode 1  usage/environment error
# @exitcode 2  self-test failure
# @exitcode 3  plugin-data-lib.sh unreachable — plugin install broken
#
# @requires    bash >=3.2
# @min_shell   bash 3.2 (macOS system bash compatible)
#
# Platform: Linux + macOS (Darwin). No GNU-only flags used.
# NOTE: deliberately does not use jq — the row is built with printf so this script
# still runs (and still counts) on the jq-missing path map-and-filter's callers hit.

set -Eeuo pipefail
IFS=$'\n\t'

trap 'printf >&2 "error: %s:%d: exit %d\n" "${BASH_SOURCE[0]}" "$LINENO" "$?"' ERR

# `[ -r ]` first: `.` on a missing file exits a `set -e` shell before any guard runs.
LIB_PATH="$(dirname "${BASH_SOURCE[0]}")/plugin-data-lib.sh"
if [ -r "$LIB_PATH" ]; then
  # shellcheck source=skills/self-improvement/scripts/plugin-data-lib.sh
  # shellcheck disable=SC1090
  . "$LIB_PATH"
else
  printf >&2 'pipeline-counts: plugin-data-lib.sh unreachable at %s — plugin install broken\n' \
    "$LIB_PATH"
  exit 3
fi

usage() {
  printf >&2 'usage: %s --worktask-id=<id> --run-index=<n> --context-set=<f> --changes=<f> --mapped=<f> --appended=<f> [--stage=<code>] [--dataset=<file>] [--plugin-data=<dir>] [--dry-run] [--self-test]\n' \
    "${0##*/}"
  exit 1
}

WORKTASK_ID=""
RUN_INDEX=""
STAGE="ST"
CONTEXT_SET=""
CHANGES=""
MAPPED=""
APPENDED_FILE=""
DATASET=""
PLUGIN_DATA=""
DRY_RUN=0
SELF_TEST=0

for arg in "$@"; do
  case "$arg" in
    --worktask-id=*) WORKTASK_ID="${arg#*=}" ;;
    --run-index=*) RUN_INDEX="${arg#*=}" ;;
    --stage=*) STAGE="${arg#*=}" ;;
    --context-set=*) CONTEXT_SET="${arg#*=}" ;;
    --changes=*) CHANGES="${arg#*=}" ;;
    --mapped=*) MAPPED="${arg#*=}" ;;
    --appended=*) APPENDED_FILE="${arg#*=}" ;;
    --dataset=*) DATASET="${arg#*=}" ;;
    --plugin-data=*) PLUGIN_DATA="${arg#*=}" ;;
    --dry-run) DRY_RUN=1 ;;
    --self-test) SELF_TEST=1 ;;
    *) usage ;;
  esac
done

# count_context_paths <file> — NF>=1 line count; absent file = 0.
count_context_paths() {
  local file="$1"
  if [ -n "$file" ] && [ -f "$file" ]; then
    awk 'NF>=1{n++} END{print n+0}' "$file"
  else
    printf '0\n'
  fi
}

# count_changed_paths <file> — 3-field TSV row count; absent file = 0.
count_changed_paths() {
  local file="$1"
  if [ -n "$file" ] && [ -f "$file" ]; then
    awk -F'\t' 'NF==3{n++} END{print n+0}' "$file"
  else
    printf '0\n'
  fi
}

# count_mapped_rows <file> — 5-field TSV row count with a numeric $2; absent file = 0.
count_mapped_rows() {
  local file="$1"
  if [ -n "$file" ] && [ -f "$file" ]; then
    awk -F'\t' 'NF==5 && $2 ~ /^[0-9]+$/ {n++} END{print n+0}' "$file"
  else
    printf '0\n'
  fi
}

# count_appended_rows <file> — line-1 integer; non-integer = 0 + stderr warn;
# absent file = 0. Plain `read`, not awk/wc: the same no-trailing-newline case
# the header warns about is exactly what a `read` loop handles correctly.
count_appended_rows() {
  local file="$1" val=""
  if [ -n "$file" ] && [ -f "$file" ]; then
    IFS= read -r val <"$file" || true
    case "$val" in
      '' | *[!0-9]*)
        printf >&2 'pipeline-counts: --appended file first line is not an integer (%s); counting 0\n' \
          "${val:-<empty>}"
        printf '0\n'
        ;;
      *) printf '%s\n' "$((10#$val))" ;;
    esac
  else
    printf '0\n'
  fi
}

if [ "$SELF_TEST" -eq 1 ]; then
  # Sourced HERE, not at the top: the harness is test code the production path
  # never runs.
  SELFTEST_LIB_PATH="$(dirname "${BASH_SOURCE[0]}")/pipeline-counts-selftest.sh"
  if [ -r "$SELFTEST_LIB_PATH" ]; then
    # shellcheck source=skills/self-improvement/scripts/pipeline-counts-selftest.sh
    # shellcheck disable=SC1090
    . "$SELFTEST_LIB_PATH"
  else
    printf >&2 'pipeline-counts: self-test harness unreachable at %s — plugin install broken\n' \
      "$SELFTEST_LIB_PATH"
    exit 2
  fi
  self_test || exit 2
  exit 0
fi

[ -n "$WORKTASK_ID" ] || usage
# '"' and '\' would break the printf'd JSON row's quoting/escaping; a control
# character (tab/CR/newline) would break the one-row-per-line JSONL contract.
# All are cheaper to reject here than to escape correctly in a jq-less writer.
case "$WORKTASK_ID" in
  *\"* | *\\* | *[[:cntrl:]]*)
    printf >&2 'pipeline-counts: --worktask-id must not contain a double quote, backslash, or control character\n'
    exit 1
    ;;
esac

[ -n "$RUN_INDEX" ] || usage
case "$RUN_INDEX" in
  '' | *[!0-9]*)
    printf >&2 'pipeline-counts: --run-index must be a non-negative integer\n'
    exit 1
    ;;
esac
# Force base-10 so a leading zero ("008") never reaches the printf'd row as an
# octal-looking literal; also collapses it to the canonical "8".
RUN_INDEX=$((10#$RUN_INDEX))

# Two uppercase letters plus optional digits (ST, PL, TL2, ...), anchored: this
# is also what keeps a quote/backslash/control character out of the row, since
# the charset it accepts excludes all three.
if ! [[ "$STAGE" =~ ^[A-Z]{2}[0-9]*$ ]]; then
  printf >&2 'pipeline-counts: --stage must match ^[A-Z]{2}[0-9]*$ (e.g. ST, PL2)\n'
  exit 1
fi

[ -n "$CONTEXT_SET" ] || usage
[ -n "$CHANGES" ] || usage
[ -n "$MAPPED" ] || usage
[ -n "$APPENDED_FILE" ] || usage

CONTEXT_PATHS="$(count_context_paths "$CONTEXT_SET")"
CHANGED_PATHS="$(count_changed_paths "$CHANGES")"
MAPPED_ROWS="$(count_mapped_rows "$MAPPED")"
APPENDED_ROWS="$(count_appended_rows "$APPENDED_FILE")"

# Always printed, on every path (short-circuit, opt-out, fallback, --dry-run):
# this line, not the row, is the one signal SKILL.md guarantees is never skipped.
printf >&2 'self-improve-counts: context_paths=%s changed_paths=%s mapped_rows=%s appended_rows=%s\n' \
  "$CONTEXT_PATHS" "$CHANGED_PATHS" "$MAPPED_ROWS" "$APPENDED_ROWS"

if [ "${SELF_IMPROVE_LABELS:-1}" = "0" ]; then
  LABELS_ENABLED="false"
else
  LABELS_ENABLED="true"
fi

si_resolve_dataset "$DATASET" "$PLUGIN_DATA" "${CLAUDE_PLUGIN_DATA:-}" "failure-labels.jsonl" || exit 1

# Fallback rung: no row, so nothing new lands in the repo tree.
# --dry-run: caller wants the stderr line only.
if [ "$DRY_RUN" -eq 1 ] || [ "$SI_DATASET_SOURCE" = "fallback" ]; then
  exit 0
fi

COUNTS_FILE="$(dirname "$SI_DATASET_PATH")/pipeline-counts.jsonl"
mkdir -p -- "$(dirname "$COUNTS_FILE")"
TS="$(date -u +%FT%TZ)"
# Subshell-scoped umask: a newly created row file must be 0600 even when the
# parent dir's own umask/ACL would otherwise leave it group/world-readable.
(
  umask 077
  printf '{"schema":"self-improve-counts/v1","ts":"%s","worktask_id":"%s","run_index":%s,"stage":"%s","context_paths":%s,"changed_paths":%s,"mapped_rows":%s,"appended_rows":%s,"labels_enabled":%s,"dataset_source":"%s"}\n' \
    "$TS" "$WORKTASK_ID" "$RUN_INDEX" "$STAGE" "$CONTEXT_PATHS" "$CHANGED_PATHS" "$MAPPED_ROWS" "$APPENDED_ROWS" \
    "$LABELS_ENABLED" "$SI_DATASET_SOURCE" >>"$COUNTS_FILE"
)
