#!/usr/bin/env bash
# pipeline-counts-selftest.sh — the `--self-test` harness for pipeline-counts.sh.
#
# SOURCED, never executed: pipeline-counts.sh loads this file only on the
# `--self-test` path, so the production path never pays for it. Sourcing leaves the
# caller's `$0` and every function it has already defined in scope — this file reads
# the caller's helpers and is not standalone.
#
# Every case passes an explicit --dataset under $tmp, never a bare --plugin-data or
# a real CLAUDE_PLUGIN_DATA: this harness must not touch a real plugin-data root or
# the repo's own evals/ tree, only its own scratch directory.
#
# No jq: pipeline-counts.sh is deliberately jq-free, so its own self-test stays
# jq-free too and asserts JSON fields with `case`/`grep -F` on the known key order.
#
# Contract: defines `self_test`, returning 0 when every case passes.

self_test() {
  local tmp rc=0
  tmp=$(mktemp -d)
  # Expand tmp now, not at trap time.
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT

  local ds="$tmp/data/self-improvement/failure-labels.jsonl"
  local counts="$tmp/data/self-improvement/pipeline-counts.jsonl"

  # Every input file absent -> every count 0, and --dry-run writes no row.
  local err
  "$0" --worktask-id=wt --run-index=0 \
    --context-set="$tmp/nope-ctx" --changes="$tmp/nope-ch" --mapped="$tmp/nope-map" \
    --appended="$tmp/nope-app" --dataset="$ds" --dry-run >/dev/null 2>"$tmp/err0"
  err="$(cat "$tmp/err0")"
  case "$err" in
    *'context_paths=0 changed_paths=0 mapped_rows=0 appended_rows=0'*) ;;
    *) printf >&2 'FAIL: absent-input counts wrong: %s\n' "$err"; rc=1 ;;
  esac
  [ ! -f "$counts" ] || { printf >&2 'FAIL: --dry-run wrote a row\n'; rc=1; }

  # A real run appends exactly one row with the right counts.
  printf 'a\nb\n' >"$tmp/ctx"
  printf 'p\tx\ty\n' >"$tmp/changes"
  printf 'p\t1\tt\t0\t0\n' >"$tmp/mapped"
  printf '2\n' >"$tmp/appended"
  "$0" --worktask-id=wt --run-index=3 --stage=ST \
    --context-set="$tmp/ctx" --changes="$tmp/changes" --mapped="$tmp/mapped" \
    --appended="$tmp/appended" --dataset="$ds" >/dev/null 2>"$tmp/err1"
  if [ -f "$counts" ]; then
    local row
    row="$(cat "$counts")"
    case "$row" in
      *'"worktask_id":"wt"'*'"run_index":3'*'"stage":"ST"'*'"context_paths":2'*'"changed_paths":1'*'"mapped_rows":1'*'"appended_rows":2'*'"labels_enabled":true'*'"dataset_source":"explicit"'*) ;;
      *) printf >&2 'FAIL: counts row fields wrong: %s\n' "$row"; rc=1 ;;
    esac
    [ "$(wc -l <"$counts" | tr -d ' ')" = "1" ] || { printf >&2 'FAIL: expected exactly one row\n'; rc=1; }
  else
    printf >&2 'FAIL: no counts row written\n'
    rc=1
  fi

  # A non-integer --appended first line counts 0 and warns.
  printf 'oops\n' >"$tmp/badappended"
  "$0" --worktask-id=wt --run-index=0 \
    --context-set="$tmp/ctx" --changes="$tmp/changes" --mapped="$tmp/mapped" \
    --appended="$tmp/badappended" --dataset="$ds" --dry-run >/dev/null 2>"$tmp/err2"
  local err2
  err2="$(cat "$tmp/err2")"
  case "$err2" in
    *'not an integer'*) ;;
    *) printf >&2 'FAIL: non-integer appended did not warn\n'; rc=1 ;;
  esac
  case "$err2" in
    *'appended_rows=0'*) ;;
    *) printf >&2 'FAIL: non-integer appended not counted as 0\n'; rc=1 ;;
  esac

  # SELF_IMPROVE_LABELS=0 flips labels_enabled but still writes the row.
  local ds2="$tmp/data2/self-improvement/failure-labels.jsonl"
  local counts2="$tmp/data2/self-improvement/pipeline-counts.jsonl"
  (
    SELF_IMPROVE_LABELS=0 "$0" --worktask-id=wt --run-index=0 \
      --context-set="$tmp/ctx" --changes="$tmp/changes" --mapped="$tmp/mapped" \
      --appended="$tmp/appended" --dataset="$ds2" >/dev/null 2>&1
  )
  if [ -f "$counts2" ]; then
    grep -q '"labels_enabled":false' "$counts2" || { printf >&2 'FAIL: labels_enabled not false\n'; rc=1; }
  else
    printf >&2 'FAIL: opt-out run wrote no counts row\n'
    rc=1
  fi

  # A quoted or backslash-bearing worktask-id is rejected before anything runs.
  if "$0" --worktask-id='bad"id' --run-index=0 \
    --context-set="$tmp/ctx" --changes="$tmp/changes" --mapped="$tmp/mapped" \
    --appended="$tmp/appended" --dataset="$ds" --dry-run >/dev/null 2>&1; then
    printf >&2 'FAIL: quoted worktask-id accepted\n'
    rc=1
  fi

  [ "$rc" -eq 0 ] && printf >&2 'pipeline-counts: self-test OK\n'
  return "$rc"
}
