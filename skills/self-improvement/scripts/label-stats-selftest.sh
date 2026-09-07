#!/usr/bin/env bash
# label-stats-selftest.sh — the `--self-test` harness for label-stats.sh.
#
# SOURCED, never executed: label-stats.sh loads this file only on the `--self-test`
# path, so the production path never pays for it. Sourcing leaves the caller's
# `$0` and every function it has already defined in scope — this file reads the
# caller's helpers and is not standalone.
#
# Contract: defines `self_test`, returning 0 when every case passes.

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
