#!/usr/bin/env bash
# dv-tree-preflight-selftest.sh — the `--self-test` harness for dv-tree-preflight.sh.
#
# SOURCED, never executed: dv-tree-preflight.sh loads this file only on the `--self-test`
# path, so the production path never pays for it. Sourcing leaves the caller's
# `$0` and every function it has already defined in scope — this file reads the
# caller's helpers and is not standalone.
#
# Contract: defines `run_self_test`, returning 0 when every case passes.

run_self_test() {
  local SELF td repo wt rc out
  SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
  td=$(mktemp -d -t dv-tree-preflight-XXXXXX)
  # shellcheck disable=SC2064  # expand $td now so the trap removes the right dir
  trap "rm -rf '${td}'" EXIT

  repo="$td/repo"
  mkdir -p "$repo"
  (
    cd "$repo"
    git init -q .
    git config user.email t@t.t
    git config user.name t
    printf 'x\n' > f.txt
    git add f.txt
    git commit -qm init
  )

  # S1: matching tree passes silently.
  set +e
  out=$(cd "$repo" && bash "$SELF" --assigned "$repo" --quiet 2>&1)
  rc=$?
  set -e
  if [[ "$rc" -eq 0 && -z "$out" ]]; then
    printf 'S1: matching tree passes silently: ok\n'
  else
    printf 'S1: matching tree must pass silently (rc=%s out=%s): FAIL\n' "$rc" "$out" >&2
    exit 1
  fi

  # S2: a different tree blocks and names both paths.
  wt="$td/other"
  mkdir -p "$wt"
  set +e
  out=$(cd "$repo" && bash "$SELF" --assigned "$wt" 2>&1)
  rc=$?
  set -e
  if [[ "$rc" -eq 1 ]] && printf '%s' "$out" | grep -q 'MISMATCH'; then
    printf 'S2: mismatched tree blocks naming both paths: ok\n'
  else
    printf 'S2: mismatched tree must exit 1 (rc=%s): FAIL\n' "$rc" >&2
    exit 1
  fi

  # S3: unresolved assignment warns rather than blocking.
  set +e
  out=$(cd "$repo" && WORKSPACE_ROOT="" bash "$SELF" --state /nonexistent/state.json 2>&1)
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]] && printf '%s' "$out" | grep -q 'WARN'; then
    printf 'S3: unresolved assignment warns, never blocks: ok\n'
  else
    printf 'S3: unresolved assignment must warn and exit 0 (rc=%s): FAIL\n' "$rc" >&2
    exit 1
  fi

  printf 'self-test: ALL PASS\n'
  exit 0
}
