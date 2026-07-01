#!/usr/bin/env bash
# tests/lib/test_helper.bash — common setup for every .bats file in this suite.
#
# FROZEN API (per .context/analyzing-0.md#convention). DV0a/DV0b/DV0c code their
# .bats files against exactly this surface; do NOT change names/semantics without
# a coordinated re-freeze.
#
# Every test file begins with:
#     load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"
# (from tests/shell/<group>/<name>.bats the relative path is ../../lib/...)
#
# Exposed to every test file after the load:
#   $PLUGIN_ROOT  — absolute repo root (resolved from this file's location)
#   $FIXTURES     — absolute tests/fixtures dir
#   run_script <relpath-from-PLUGIN_ROOT> [args...]
#                 — runs the target script via `run` (sets $status/$output/$lines);
#                   bash for *.sh, python3 for *.py, direct exec otherwise.
#   mk_tmpworkdir — prints an mktemp -d dir under BATS_TMPDIR; auto-removed in
#                   the default teardown (tracked in _TEST_HELPER_TMPDIRS).

# --- vendor: bats-support + bats-assert -------------------------------------
# Resolve this helper's own directory robustly (BATS_TEST_DIRNAME is the dir of
# the running .bats file, which differs per group; ${BASH_SOURCE} is this file).
_TEST_HELPER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_TEST_HELPER_VENDOR="${_TEST_HELPER_LIB_DIR}/../vendor"

load "${_TEST_HELPER_VENDOR}/bats-support/load.bash"
load "${_TEST_HELPER_VENDOR}/bats-assert/load.bash"

# --- exposed absolute paths --------------------------------------------------
# PLUGIN_ROOT = repo root = parent of tests/. tests/lib/ -> ../../ is the root.
export PLUGIN_ROOT="$(cd "${_TEST_HELPER_LIB_DIR}/../.." && pwd)"
export FIXTURES="${PLUGIN_ROOT}/tests/fixtures"

# --- run_script: dispatch a target under `run` -------------------------------
# Usage: run_script skills/foo/scripts/bar.sh --flag value
# Sets $status/$output/$lines (it wraps bats `run`). The first arg is a path
# RELATIVE to PLUGIN_ROOT; remaining args pass through verbatim.
run_script() {
  local rel="$1"; shift
  local abs="${PLUGIN_ROOT}/${rel}"
  case "$rel" in
    *.py)  run python3 "$abs" "$@" ;;
    *.sh)  run bash    "$abs" "$@" ;;
    *)     run         "$abs" "$@" ;;
  esac
}

# --- mk_tmpworkdir: isolated scratch dir, auto-cleaned -----------------------
# Prints an absolute mktemp -d under BATS_TMPDIR. Registered for teardown.
_TEST_HELPER_TMPDIRS=()
mk_tmpworkdir() {
  local base="${BATS_TMPDIR:-${TMPDIR:-/tmp}}"
  local d
  d="$(mktemp -d "${base%/}/worktask-test.XXXXXX")"
  _TEST_HELPER_TMPDIRS+=("$d")
  printf '%s\n' "$d"
}

# Default teardown. A test file that defines its own teardown() SHOULD call
# `_test_helper_cleanup` to retain auto-cleanup of mk_tmpworkdir dirs.
_test_helper_cleanup() {
  local d
  for d in "${_TEST_HELPER_TMPDIRS[@]:-}"; do
    [ -n "$d" ] && [ -d "$d" ] && rm -rf "$d"
  done
  _TEST_HELPER_TMPDIRS=()
}

teardown() {
  _test_helper_cleanup
}
