#!/usr/bin/env bash
# run-tests.sh — single, dependency-light entrypoint for the deterministic suite.
#
# AC-1: on a clean clone with ONLY Python 3.14, jq, and make present (NO system
# bats / pytest / kcov), `./run-tests.sh` self-bootstraps the vendored bats and
# runs the full deterministic suite green. No network. No live dispatch.
#
# `make test` delegates here. A bare `./run-tests.sh` is equivalent.
#
# Flags:
#   --coverage    run under coverage tooling (kcov for bash, coverage.py for
#                 python); same as COVERAGE=1. Delegates coverage gating to make
#                 where kcov is available, else documents the proxy.
#   --quiet       less chatty bats output (bats default is already terse).
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PLUGIN_ROOT"

BATS="$PLUGIN_ROOT/tests/vendor/bats-core/bin/bats"
COVERAGE="${COVERAGE:-0}"

for arg in "$@"; do
  case "$arg" in
    --coverage) COVERAGE=1 ;;
    --quiet)    : ;;  # bats is terse by default; reserved
    *) echo "run-tests.sh: unknown arg '$arg'" >&2; exit 64 ;;
  esac
done

note() { printf '\033[1;34m[run-tests]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[run-tests]\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31m[run-tests]\033[0m %s\n' "$*" >&2; exit 1; }

# --- bootstrap check: vendored bats must be present --------------------------
if [ ! -x "$BATS" ]; then
  fail "vendored bats missing at $BATS — the repo is incomplete (expected tests/vendor/bats-core). \
See tests/vendor/VENDOR.md."
fi

# Hard prerequisites that the host MUST provide (per AC-1 environment contract).
command -v python3 >/dev/null 2>&1 || fail "python3 not found (required)"
command -v jq      >/dev/null 2>&1 || fail "jq not found (required)"

note "vendored bats: $("$BATS" --version 2>/dev/null || echo '?')"
note "python3:       $(python3 --version 2>&1)"

# --- collect shell test files ------------------------------------------------
# All .bats under tests/shell/**. Use find so missing subdirs don't break.
shell_tests=()
while IFS= read -r f; do shell_tests+=("$f"); done < <(
  find "$PLUGIN_ROOT/tests/shell" -type f -name '*.bats' 2>/dev/null | sort
)

# --- python test discovery ---------------------------------------------------
have_python_tests=0
if find "$PLUGIN_ROOT/tests/python" -name 'test_*.py' -type f 2>/dev/null | grep -q .; then
  have_python_tests=1
fi

rc=0

if [ "$COVERAGE" = "1" ]; then
  note "COVERAGE=1 → delegating to 'make coverage' for kcov/coverage.py gating"
  make -C "$PLUGIN_ROOT" coverage || rc=$?
  exit "$rc"
fi

# --- run shell tests ---------------------------------------------------------
if [ "${#shell_tests[@]}" -gt 0 ]; then
  note "running ${#shell_tests[@]} bats file(s)…"
  "$BATS" "${shell_tests[@]}" || rc=$?
else
  warn "no .bats files found under tests/shell — (other DV tracks not yet landed?)"
fi

# --- run python tests --------------------------------------------------------
if [ "$have_python_tests" = "1" ]; then
  note "running python unittest discovery under tests/python…"
  ( cd "$PLUGIN_ROOT" && python3 -m unittest discover -s tests/python -p 'test_*.py' -v ) || rc=$?
else
  warn "no python tests found under tests/python (DV0c not yet landed?)"
fi

if [ "$rc" -eq 0 ]; then
  note "ALL GREEN"
else
  warn "suite reported failures (rc=$rc)"
fi
exit "$rc"
