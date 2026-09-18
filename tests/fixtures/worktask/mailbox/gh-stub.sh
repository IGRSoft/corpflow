#!/usr/bin/env bash
# gh-stub.sh — a fixture `gh` double for GH_BIN (test data only; not shipped by any skill).
#
# Records every call's argv (space-joined) as one line to GH_STUB_CALL_LOG, when set — a
# test that must prove `gh` was never invoked asserts that file is absent. Serves the
# contents of GH_STUB_COMMENTS_JSON verbatim for `api …` (default `[]` when unset or
# unreadable); exits 0 for `issue comment …`, and for every other subcommand, unless
# GH_STUB_FORCE_FAIL=1, which fails every call (after the marker is recorded) with
# GH_STUB_FORCE_FAIL_CODE (default 1) — used to prove a caller degrades rather than races
# ahead on a `gh` failure.
#
# @env GH_STUB_CALL_LOG        Optional. Appended one line per call (this call's argv).
# @env GH_STUB_COMMENTS_JSON   Optional. Path to the JSON array served for `api …`.
# @env GH_STUB_FORCE_FAIL      "1" forces every call to fail.
# @env GH_STUB_FORCE_FAIL_CODE Exit code used with GH_STUB_FORCE_FAIL (default 1).
set -u

if [ -n "${GH_STUB_CALL_LOG:-}" ]; then
  printf '%s\n' "$*" >> "$GH_STUB_CALL_LOG" 2> /dev/null || true
fi

if [ "${GH_STUB_FORCE_FAIL:-0}" = "1" ]; then
  exit "${GH_STUB_FORCE_FAIL_CODE:-1}"
fi

case "${1:-}" in
  api)
    if [ -n "${GH_STUB_COMMENTS_JSON:-}" ] && [ -r "${GH_STUB_COMMENTS_JSON}" ]; then
      cat -- "${GH_STUB_COMMENTS_JSON}"
    else
      printf '[]\n'
    fi
    ;;
  *)
    : ;;
esac
exit 0
