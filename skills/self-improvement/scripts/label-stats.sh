#!/usr/bin/env bash
# @file        label-stats.sh
# @description Aggregates evals/failure-labels.jsonl into per-target and
#              per-category counts — the input error analysis reads to find which
#              agents/skills the user corrects most, and in what way.
#
# @usage       label-stats.sh [--dataset=<file>] [--format=table|json] [--min-count=<n>] [--self-test]
#
# @arg --dataset=<file>  JSONL label dataset (default: evals/failure-labels.jsonl)
# @arg --format=<fmt>    table (default) or json
# @arg --min-count=<n>   Recurrence threshold: flag targets/categories with at
#                        least n labels (default 3; 0 disables the section)
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

# Row count at which evals/README.md unblocks writing failure-taxonomy.md.
TAXONOMY_THRESHOLD=100

DATASET=""
FORMAT="table"
MIN_COUNT=3
SELF_TEST=0

usage() {
  printf >&2 'usage: %s [--dataset=<file>] [--format=table|json] [--min-count=<n>] [--self-test]\n' \
    "${0##*/}"
  exit 1
}

for arg in "$@"; do
  case "$arg" in
    --dataset=*)   DATASET="${arg#*=}" ;;
    --format=*)    FORMAT="${arg#*=}" ;;
    --min-count=*) MIN_COUNT="${arg#*=}" ;;
    --self-test)   SELF_TEST=1 ;;
    *) usage ;;
  esac
done

case "$MIN_COUNT" in
  ''|*[!0-9]*) printf >&2 'label-stats: --min-count must be a non-negative integer\n'; exit 1 ;;
esac

if ! command -v jq >/dev/null 2>&1; then
  printf >&2 'label-stats: jq not found\n'
  exit 1
fi

stats_json() {
  # `recurring` reports; it never acts. Acting on a repeat stays gated on the
  # human approval of a Step 5 proposal.
  jq -s --argjson min "$2" --argjson taxonomy "$TAXONOMY_THRESHOLD" '
    (group_by(.target) | map({key: .[0].target, value: length}) | from_entries) as $targets |
    (group_by(.category) | map({key: .[0].category, value: length}) | from_entries) as $categories |
    {
      total: length,
      worktasks: ([.[].worktask_id] | unique | length),
      by_target: $targets,
      by_category: $categories,
      by_confidence: (group_by(.confidence) | map({key: .[0].confidence, value: length}) | from_entries),
      recurrence_threshold: $min,
      recurring: {
        targets: (if $min > 0 then ($targets | with_entries(select(.value >= $min))) else {} end),
        categories: (if $min > 0 then ($categories | with_entries(select(.value >= $min))) else {} end)
      },
      taxonomy: {rows: length, threshold: $taxonomy, ready: (length >= $taxonomy)}
    }' "$1"
}

render() {
  local dataset="$1" format="$2" min="$3"
  if [ ! -s "$dataset" ]; then
    printf 'no labels yet (%s)\n' "$dataset"
    return 0
  fi
  if [ "$format" = "json" ]; then
    stats_json "$dataset" "$min"
    return 0
  fi
  stats_json "$dataset" "$min" | jq -r '
    "labels: \(.total)  worktasks: \(.worktasks)",
    "taxonomy trigger: \(.taxonomy.rows)/\(.taxonomy.threshold) rows — \(if .taxonomy.ready then "READY" else "not yet" end)",
    "",
    "by target:",
    (.by_target | to_entries | sort_by(-.value) | .[] | "  \(.value)\t\(.key)"),
    "",
    "by category:",
    (.by_category | to_entries | sort_by(-.value) | .[] | "  \(.value)\t\(.key)"),
    (if .recurrence_threshold > 0 then
      "",
      "recurring (>=\(.recurrence_threshold)):",
      (( (.recurring.targets | to_entries | map(. + {kind: "target"}))
       + (.recurring.categories | to_entries | map(. + {kind: "category"})) )
       | sort_by(-.value)
       | if length == 0 then ["  none"] else map("  \(.kind)\t\(.value)\t\(.key)") end
       | .[])
     else empty end)'
}

self_test() {
  local tmp rc=0
  tmp=$(mktemp -d)
  # Expand tmp now, not at trap time.
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT

  local ds="$tmp/labels.jsonl"
  : > "$ds"
  render "$ds" table 3 | grep -q "no labels yet" || { printf >&2 'FAIL: empty dataset\n'; rc=1; }

  printf '%s\n' \
    '{"target":"agents/developer.md","category":"completeness","confidence":"high","worktask_id":"a"}' \
    '{"target":"agents/developer.md","category":"accuracy","confidence":"high","worktask_id":"a"}' \
    '{"target":"skills/worktask/SKILL.md","category":"completeness","confidence":"low","worktask_id":"b"}' \
    > "$ds"

  local out
  out=$(render "$ds" json 3)
  [ "$(printf '%s' "$out" | jq -r '.total')" = "3" ] || { printf >&2 'FAIL: total\n'; rc=1; }
  [ "$(printf '%s' "$out" | jq -r '.worktasks')" = "2" ] || { printf >&2 'FAIL: worktasks\n'; rc=1; }
  [ "$(printf '%s' "$out" | jq -r '.by_target["agents/developer.md"]')" = "2" ] \
    || { printf >&2 'FAIL: by_target\n'; rc=1; }
  [ "$(printf '%s' "$out" | jq -r '.by_category["completeness"]')" = "2" ] \
    || { printf >&2 'FAIL: by_category\n'; rc=1; }

  render "$ds" table 3 | grep -q "by category:" || { printf >&2 'FAIL: table render\n'; rc=1; }

  # Threshold 2 catches the repeated target and category; threshold 3 catches
  # neither, so an absent recurrence is a real "none", not a formatting slip.
  out=$(render "$ds" json 2)
  [ "$(printf '%s' "$out" | jq -r '.recurring.targets["agents/developer.md"]')" = "2" ] \
    || { printf >&2 'FAIL: recurring target at min=2\n'; rc=1; }
  [ "$(printf '%s' "$out" | jq -r '.recurring.categories["completeness"]')" = "2" ] \
    || { printf >&2 'FAIL: recurring category at min=2\n'; rc=1; }
  [ "$(render "$ds" json 3 | jq -r '.recurring.targets | length')" = "0" ] \
    || { printf >&2 'FAIL: recurring target at min=3\n'; rc=1; }
  [ "$(render "$ds" json 0 | jq -r '.recurring.targets | length')" = "0" ] \
    || { printf >&2 'FAIL: min=0 did not disable recurrence\n'; rc=1; }
  if render "$ds" table 0 | grep -q "recurring"; then
    printf >&2 'FAIL: min=0 rendered section\n'; rc=1
  fi
  render "$ds" table 2 | grep -qE '^  target[[:space:]]+2[[:space:]]+agents/developer\.md$' \
    || { printf >&2 'FAIL: recurring table row\n'; rc=1; }
  render "$ds" table 3 | grep -q "  none" || { printf >&2 'FAIL: empty recurrence render\n'; rc=1; }

  # The taxonomy gate has to announce itself; 3 rows is far below the 100 the
  # README blocks failure-taxonomy.md on.
  [ "$(printf '%s' "$out" | jq -r '.taxonomy.ready')" = "false" ] \
    || { printf >&2 'FAIL: taxonomy ready\n'; rc=1; }
  render "$ds" table 3 | grep -q "taxonomy trigger: 3/100 rows — not yet" \
    || { printf >&2 'FAIL: taxonomy trigger line\n'; rc=1; }

  [ "$rc" -eq 0 ] && printf >&2 'label-stats: self-test OK\n'
  return "$rc"
}

if [ "$SELF_TEST" -eq 1 ]; then
  self_test || exit 2
  exit 0
fi

[ -n "$DATASET" ] || DATASET="${CLAUDE_PROJECT_DIR:-.}/evals/failure-labels.jsonl"
[ -f "$DATASET" ] || { printf 'no labels yet (%s)\n' "$DATASET"; exit 0; }
render "$DATASET" "$FORMAT" "$MIN_COUNT"
