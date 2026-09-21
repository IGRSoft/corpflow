#!/usr/bin/env bash
# @file        append-labels.sh
# @description Step 5b of the self-improvement pipeline.
#              Appends each kept, classified user edit to the COMMITTED label
#              dataset at evals/failure-labels.jsonl. learnings.md is per-worktask
#              and lives under the gitignored .context/, so without this step every
#              domain-expert label the pipeline produces is discarded at the end of
#              the run.
#
#              Input TSV (stdin or --changes), one row per kept change:
#                <path>\t<target>\t<category>\t<confidence>\t<added>\t<removed>\t<summary>
#
#              Emits nothing on stdout; appends JSONL rows to the dataset and
#              prints a one-line count to stderr.
#
# @usage       append-labels.sh --worktask-id=<id> [options]
#
# @arg --worktask-id=<id>  Worktask identifier the labels belong to (required)
# @arg --changes=<file>    Input TSV (default: stdin)
# @arg --dataset=<file>    Output JSONL — see plugin-data-lib.sh (default: resolved)
# @arg --plugin-data=<dir> Plugin data root — see plugin-data-lib.sh
# @arg --count-out=<file>  Appended row count, written on every exit (EXIT trap)
# @arg --run-index=<n>     Worktask run index (default: 0)
# @arg --stage=<code>      Stage that produced the edited artifact (default: ST)
# @arg --self-test         Run internal test suite; exit 0/non-zero
#
# @env SELF_IMPROVE_LABELS  Set to 0 to opt out — the step becomes a no-op.
# @env CLAUDE_PROJECT_DIR   Passed through to plugin-data-lib.sh's fallback rung.
# @env CLAUDE_PLUGIN_DATA   Passed through to plugin-data-lib.sh's env rung.
#
# @exitcode 0  success (including opt-out and zero-row input)
# @exitcode 1  usage/environment error
# @exitcode 2  self-test failure
# @exitcode 3  plugin-data-lib.sh unreachable — plugin install broken
#
# @requires    bash >=3.2, jq, shasum or sha256sum
# @min_shell   bash 3.2 (macOS system bash compatible)
#
# Platform: Linux + macOS (Darwin). No GNU-only flags used.

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
  printf >&2 'append-labels: plugin-data-lib.sh unreachable at %s — plugin install broken\n' \
    "$LIB_PATH"
  exit 3
fi

usage() {
  printf >&2 'usage: %s --worktask-id=<id> [--changes=<file>] [--dataset=<file>] [--plugin-data=<dir>] [--count-out=<file>] [--run-index=<n>] [--stage=<code>] [--self-test]\n' \
    "${0##*/}"
  exit 1
}

WORKTASK_ID=""
CHANGES=""
DATASET=""
PLUGIN_DATA=""
COUNT_OUT=""
RUN_INDEX="0"
STAGE="ST"
SELF_TEST=0

for arg in "$@"; do
  case "$arg" in
    --worktask-id=*) WORKTASK_ID="${arg#*=}" ;;
    --changes=*)     CHANGES="${arg#*=}" ;;
    --dataset=*)     DATASET="${arg#*=}" ;;
    --plugin-data=*) PLUGIN_DATA="${arg#*=}" ;;
    --count-out=*)   COUNT_OUT="${arg#*=}" ;;
    --run-index=*)   RUN_INDEX="${arg#*=}" ;;
    --stage=*)       STAGE="${arg#*=}" ;;
    --self-test)     SELF_TEST=1 ;;
    *)               usage ;;
  esac
done

# Installed before the early exits so opt-out and missing-jq runs still write 0.
APPENDED=0
_write_count_out() {
  local rc=$?
  if [ -n "$COUNT_OUT" ]; then
    mkdir -p -- "$(dirname "$COUNT_OUT")" 2>/dev/null || true
    printf '%s\n' "$APPENDED" >"$COUNT_OUT" 2>/dev/null || true
  fi
  return "$rc"
}
trap _write_count_out EXIT

if [ "${SELF_IMPROVE_LABELS:-1}" = "0" ]; then
  printf >&2 'append-labels: SELF_IMPROVE_LABELS=0, skipping label capture\n'
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  printf >&2 'append-labels: jq not found, skipping\n'
  exit 0
fi

# Content hash of one observation, scoped to its worktask run: the same edit
# recurring in a later worktask is a new label — recurrence is the frequency
# signal label-stats aggregates. Deliberately NOT a hash of the diff body,
# which is never stored (size + the edits may be private).
sha256_stdin() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256
  else
    sha256sum
  fi
}

label_id() {
  printf '%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s' "$1" "$2" "$3" "$4" "$5" "$6" \
    | sha256_stdin | cut -d' ' -f1 | cut -c1-16
}

append_rows() {
  local dataset="$1" worktask_id="$2" run_index="$3" stage="$4"
  local ts path target category confidence added removed summary lid written=0
  local old_umask

  mkdir -p "$(dirname "$dataset")"
  # `: >>`, not `[ -f ] || : >`: append-mode touch creates a missing file without
  # ever truncating one that a concurrent megatask worktree is also appending to.
  # umask 077 around the touch only: a newly created dataset must be 0600
  # regardless of the parent dir's own umask/ACL; an existing file is untouched.
  old_umask=$(umask)
  umask 077
  : >> "$dataset"
  umask "$old_umask"
  ts=$(date -u +%FT%TZ)

  while IFS=$'\t' read -r path target category confidence added removed summary; do
    [ -n "${path:-}" ] || continue
    lid=$(label_id "$worktask_id" "$run_index" "$path" "${added:-0}" "${removed:-0}" "${summary:-}")
    # Idempotent: re-running the skill on the same worktask must not duplicate rows.
    if grep -q "\"label_id\":\"$lid\"" "$dataset" 2>/dev/null; then
      continue
    fi
    jq -cn \
      --arg ts "$ts" --arg wt "$worktask_id" --arg ri "$run_index" --arg st "$stage" \
      --arg path "$path" --arg target "${target:-unknown}" \
      --arg cat "${category:-unclassified}" --arg conf "${confidence:-unknown}" \
      --arg added "${added:-0}" --arg removed "${removed:-0}" \
      --arg summary "${summary:-}" --arg lid "$lid" \
      '{ts:$ts, worktask_id:$wt, run_index:($ri|tonumber? // 0), stage:$st,
        path:$path, target:$target, category:$cat, confidence:$conf,
        lines_added:($added|tonumber? // 0), lines_removed:($removed|tonumber? // 0),
        summary:$summary, label_id:$lid}' >> "$dataset"
    written=$((written + 1))
  done

  # Global: the EXIT trap reads it.
  APPENDED=$((APPENDED + written))
  printf >&2 'append-labels: %d new label(s) -> %s\n' "$written" "$dataset"
}

if [ "$SELF_TEST" -eq 1 ]; then
  # Sourced HERE, not at the top: the harness is test code the production path
  # never runs. `[ -r ]` first, not a bare `.`: sourcing a missing file with the
  # `.` builtin is a special-builtin error that exits the shell immediately,
  # bypassing an `if ! . …` guard entirely.
  SELFTEST_LIB_PATH="$(dirname "${BASH_SOURCE[0]}")/append-labels-selftest.sh"
  if [ -r "$SELFTEST_LIB_PATH" ]; then
    # shellcheck source=skills/self-improvement/scripts/append-labels-selftest.sh
    # shellcheck disable=SC1090
    . "$SELFTEST_LIB_PATH"
  else
    printf >&2 'append-labels: self-test harness unreachable at %s — plugin install broken\n' \
      "$SELFTEST_LIB_PATH"
    exit 2
  fi
  self_test || exit 2
  exit 0
fi

[ -n "$WORKTASK_ID" ] || usage

si_resolve_dataset "$DATASET" "$PLUGIN_DATA" "${CLAUDE_PLUGIN_DATA:-}" "failure-labels.jsonl" || exit 1
DATASET="$SI_DATASET_PATH"

if [ -n "$CHANGES" ]; then
  append_rows "$DATASET" "$WORKTASK_ID" "$RUN_INDEX" "$STAGE" < "$CHANGES"
else
  append_rows "$DATASET" "$WORKTASK_ID" "$RUN_INDEX" "$STAGE"
fi
