#!/usr/bin/env bash
# @file        label-stats.sh
# @description Aggregates evals/failure-labels.jsonl into per-target and
#              per-category counts — the input error analysis reads to find which
#              agents/skills the user corrects most, and in what way.
#
# @usage       label-stats.sh [--dataset=<file>] [--format=table|json] [--self-test]
#
# @arg --dataset=<file>  JSONL label dataset (default: evals/failure-labels.jsonl)
# @arg --format=<fmt>    table (default) or json
# @arg --self-test       Run internal test suite; exit 0/non-zero
#
# @exitcode 0  success (including an empty or absent dataset)
# @exitcode 1  usage/environment error
# @exitcode 2  self-test failure
#
# @requires    bash >=3.2, jq
# @min_shell   bash 3.2 (macOS system bash compatible)

set -euo pipefail
IFS=$'\n\t'

trap 'printf >&2 "error: %s:%d: exit %d\n" "${BASH_SOURCE[0]}" "$LINENO" "$?"' ERR

DATASET=""
FORMAT="table"
SELF_TEST=0

for arg in "$@"; do
  case "$arg" in
    --dataset=*) DATASET="${arg#*=}" ;;
    --format=*)  FORMAT="${arg#*=}" ;;
    --self-test) SELF_TEST=1 ;;
    *) printf >&2 'usage: %s [--dataset=<file>] [--format=table|json] [--self-test]\n' "${0##*/}"; exit 1 ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  printf >&2 'label-stats: jq not found\n'
  exit 1
fi

stats_json() {
  jq -s '{
    total: length,
    worktasks: ([.[].worktask_id] | unique | length),
    by_target: (group_by(.target) | map({key: .[0].target, value: length}) | from_entries),
    by_category: (group_by(.category) | map({key: .[0].category, value: length}) | from_entries),
    by_confidence: (group_by(.confidence) | map({key: .[0].confidence, value: length}) | from_entries)
  }' "$1"
}

render() {
  local dataset="$1" format="$2"
  if [ ! -s "$dataset" ]; then
    printf 'no labels yet (%s)\n' "$dataset"
    return 0
  fi
  if [ "$format" = "json" ]; then
    stats_json "$dataset"
    return 0
  fi
  stats_json "$dataset" | jq -r '
    "labels: \(.total)  worktasks: \(.worktasks)",
    "",
    "by target:",
    (.by_target | to_entries | sort_by(-.value) | .[] | "  \(.value)\t\(.key)"),
    "",
    "by category:",
    (.by_category | to_entries | sort_by(-.value) | .[] | "  \(.value)\t\(.key)")'
}

self_test() {
  local tmp rc=0
  tmp=$(mktemp -d)
  # Expand tmp now, not at trap time.
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT

  local ds="$tmp/labels.jsonl"
  : > "$ds"
  render "$ds" table | grep -q "no labels yet" || { printf >&2 'FAIL: empty dataset\n'; rc=1; }

  printf '%s\n' \
    '{"target":"agents/developer.md","category":"completeness","confidence":"high","worktask_id":"a"}' \
    '{"target":"agents/developer.md","category":"accuracy","confidence":"high","worktask_id":"a"}' \
    '{"target":"skills/worktask/SKILL.md","category":"completeness","confidence":"low","worktask_id":"b"}' \
    > "$ds"

  local out
  out=$(render "$ds" json)
  [ "$(printf '%s' "$out" | jq -r '.total')" = "3" ] || { printf >&2 'FAIL: total\n'; rc=1; }
  [ "$(printf '%s' "$out" | jq -r '.worktasks')" = "2" ] || { printf >&2 'FAIL: worktasks\n'; rc=1; }
  [ "$(printf '%s' "$out" | jq -r '.by_target["agents/developer.md"]')" = "2" ] \
    || { printf >&2 'FAIL: by_target\n'; rc=1; }
  [ "$(printf '%s' "$out" | jq -r '.by_category["completeness"]')" = "2" ] \
    || { printf >&2 'FAIL: by_category\n'; rc=1; }

  render "$ds" table | grep -q "by category:" || { printf >&2 'FAIL: table render\n'; rc=1; }

  [ "$rc" -eq 0 ] && printf >&2 'label-stats: self-test OK\n'
  return "$rc"
}

if [ "$SELF_TEST" -eq 1 ]; then
  self_test || exit 2
  exit 0
fi

[ -n "$DATASET" ] || DATASET="${CLAUDE_PROJECT_DIR:-.}/evals/failure-labels.jsonl"
[ -f "$DATASET" ] || { printf 'no labels yet (%s)\n' "$DATASET"; exit 0; }
render "$DATASET" "$FORMAT"
