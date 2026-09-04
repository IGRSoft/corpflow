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
# @arg --dataset=<file>    Output JSONL (default: evals/failure-labels.jsonl)
# @arg --run-index=<n>     Worktask run index (default: 0)
# @arg --stage=<code>      Stage that produced the edited artifact (default: ST)
# @arg --self-test         Run internal test suite; exit 0/non-zero
#
# @env SELF_IMPROVE_LABELS  Set to 0 to opt out — the step becomes a no-op.
# @env CLAUDE_PROJECT_DIR   Repo root used to resolve the default dataset path.
#
# @exitcode 0  success (including opt-out and zero-row input)
# @exitcode 1  usage/environment error
# @exitcode 2  self-test failure
#
# @requires    bash >=3.2, jq, shasum or sha256sum
# @min_shell   bash 3.2 (macOS system bash compatible)
#
# Platform: Linux + macOS (Darwin). No GNU-only flags used.

set -Eeuo pipefail
IFS=$'\n\t'

trap 'printf >&2 "error: %s:%d: exit %d\n" "${BASH_SOURCE[0]}" "$LINENO" "$?"' ERR

usage() {
  printf >&2 'usage: %s --worktask-id=<id> [--changes=<file>] [--dataset=<file>] [--run-index=<n>] [--stage=<code>] [--self-test]\n' \
    "${0##*/}"
  exit 1
}

WORKTASK_ID=""
CHANGES=""
DATASET=""
RUN_INDEX="0"
STAGE="ST"
SELF_TEST=0

for arg in "$@"; do
  case "$arg" in
    --worktask-id=*) WORKTASK_ID="${arg#*=}" ;;
    --changes=*)     CHANGES="${arg#*=}" ;;
    --dataset=*)     DATASET="${arg#*=}" ;;
    --run-index=*)   RUN_INDEX="${arg#*=}" ;;
    --stage=*)       STAGE="${arg#*=}" ;;
    --self-test)     SELF_TEST=1 ;;
    *)               usage ;;
  esac
done

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

  mkdir -p "$(dirname "$dataset")"
  [ -f "$dataset" ] || : > "$dataset"
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

  printf >&2 'append-labels: %d new label(s) -> %s\n' "$written" "$dataset"
}

self_test() {
  local tmp rc=0
  tmp=$(mktemp -d)
  # Expand tmp now, not at trap time.
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT

  local ds="$tmp/labels.jsonl"
  printf 'agents/developer.md\tagents/developer.md\tcompleteness\thigh\t4\t1\tadded Sendable constraint\n' \
    | append_rows "$ds" "wt-1" "0" "ST" 2>/dev/null

  [ "$(wc -l < "$ds" | tr -d ' ')" = "1" ] || { printf >&2 'FAIL: expected 1 row\n'; rc=1; }
  jq -e '.category == "completeness" and .target == "agents/developer.md" and .lines_added == 4' \
    "$ds" >/dev/null || { printf >&2 'FAIL: row fields\n'; rc=1; }

  # Same observation again → still one row (idempotence).
  printf 'agents/developer.md\tagents/developer.md\tcompleteness\thigh\t4\t1\tadded Sendable constraint\n' \
    | append_rows "$ds" "wt-1" "0" "ST" 2>/dev/null
  [ "$(wc -l < "$ds" | tr -d ' ')" = "1" ] || { printf >&2 'FAIL: not idempotent\n'; rc=1; }

  # A different observation appends.
  printf 'skills/worktask/SKILL.md\tskills/worktask/SKILL.md\tstructure\tmedium\t2\t0\treordered sections\n' \
    | append_rows "$ds" "wt-1" "0" "ST" 2>/dev/null
  [ "$(wc -l < "$ds" | tr -d ' ')" = "2" ] || { printf >&2 'FAIL: second row not appended\n'; rc=1; }

  # The same observation in a DIFFERENT worktask is a recurrence, not a duplicate.
  printf 'agents/developer.md\tagents/developer.md\tcompleteness\thigh\t4\t1\tadded Sendable constraint\n' \
    | append_rows "$ds" "wt-2" "0" "ST" 2>/dev/null
  [ "$(wc -l < "$ds" | tr -d ' ')" = "3" ] || { printf >&2 'FAIL: cross-worktask recurrence deduped\n'; rc=1; }

  # Opt-out is honoured by the caller-visible env gate.
  ( SELF_IMPROVE_LABELS=0 "$0" --worktask-id=wt-3 --dataset="$ds" </dev/null ) >/dev/null 2>&1
  [ "$(wc -l < "$ds" | tr -d ' ')" = "3" ] || { printf >&2 'FAIL: opt-out wrote rows\n'; rc=1; }

  [ "$rc" -eq 0 ] && printf >&2 'append-labels: self-test OK\n'
  return "$rc"
}

if [ "$SELF_TEST" -eq 1 ]; then
  self_test || exit 2
  exit 0
fi

[ -n "$WORKTASK_ID" ] || usage

if [ -z "$DATASET" ]; then
  DATASET="${CLAUDE_PROJECT_DIR:-.}/evals/failure-labels.jsonl"
fi

if [ -n "$CHANGES" ]; then
  append_rows "$DATASET" "$WORKTASK_ID" "$RUN_INDEX" "$STAGE" < "$CHANGES"
else
  append_rows "$DATASET" "$WORKTASK_ID" "$RUN_INDEX" "$STAGE"
fi
