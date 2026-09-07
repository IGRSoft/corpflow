#!/usr/bin/env bash
# append-labels-selftest.sh — the `--self-test` harness for append-labels.sh.
#
# SOURCED, never executed: append-labels.sh loads this file only on the `--self-test`
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
