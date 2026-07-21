#!/usr/bin/env bash
# run-tests.sh — single, dependency-light entrypoint for the deterministic suite.
#
# AC-1: on a clean clone with the Swift toolchain, python3, jq, and make present
# (NO system bats / pytest / kcov), `./run-tests.sh` self-bootstraps the vendored
# bats and runs the full deterministic suite green. No network. No live dispatch.
# python3 remains a prerequisite: the plugin's skill scripts
# (skills/**/scripts/*.py) stay Python, and both the skill-script tests and the
# benchmark-harness tests are native Python (stdlib unittest; no system pytest).
#
# `make test` delegates here. A bare `./run-tests.sh` is equivalent.
#
# Flags:
#   --coverage    run under coverage tooling (kcov for bash, swift
#                 --enable-code-coverage for the packages); same as COVERAGE=1.
#                 Delegates coverage gating to make.
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
command -v swift   >/dev/null 2>&1 || fail "swift toolchain not found (required)"
command -v python3 >/dev/null 2>&1 || fail "python3 not found (required — skill scripts stay Python)"
command -v jq      >/dev/null 2>&1 || fail "jq not found (required)"

note "vendored bats: $("$BATS" --version 2>/dev/null || echo '?')"
note "swift:         $(swift --version 2>/dev/null | head -1)"
note "python3:       $(python3 --version 2>&1)"

# --- collect shell test files ------------------------------------------------
# All .bats under tests/shell/**. Use find so missing subdirs don't break.
shell_tests=()
while IFS= read -r f; do shell_tests+=("$f"); done < <(
  find "$PLUGIN_ROOT/tests/shell" -type f -name '*.bats' 2>/dev/null | sort
)

rc=0

if [ "$COVERAGE" = "1" ]; then
  note "COVERAGE=1 → delegating to 'make coverage' for kcov/swift-coverage gating"
  make -C "$PLUGIN_ROOT" coverage || rc=$?
  exit "$rc"
fi

# --- run shell tests ---------------------------------------------------------
if [ "${#shell_tests[@]}" -gt 0 ]; then
  note "running ${#shell_tests[@]} bats file(s)…"
  "$BATS" "${shell_tests[@]}" || rc=$?
else
  warn "no .bats files found under tests/shell"
fi

# --- run swift test phases (ttt-template artifact only) ----------------------
swift_packages=(
  "$PLUGIN_ROOT/benchmark/ttt-template"
)
for pkg in "${swift_packages[@]}"; do
  if [ -f "$pkg/Package.swift" ]; then
    note "swift test → ${pkg#$PLUGIN_ROOT/}"
    ( cd "$pkg" && swift test ) || rc=$?
  else
    warn "swift package missing at $pkg"
    rc=1
  fi
done

# --- run python test phases (skill-script tests + harness tests) -------------
# stdlib unittest only (no system pytest) — preserves the AC-1 clean-clone guarantee.
note "python3 -m unittest → tests/python (skill-script tests)"
( cd "$PLUGIN_ROOT" && python3 -m unittest discover -s tests/python -p 'test_*.py' ) || rc=$?
note "python3 -m unittest → benchmark/harness/tests (harness suite)"
( cd "$PLUGIN_ROOT/benchmark/harness" \
    && PYTHONPATH="$PLUGIN_ROOT/benchmark/harness/tests" \
       python3 -m unittest discover -s tests -t . -p 'test_*.py' ) || rc=$?

if [ "$rc" -eq 0 ]; then
  note "ALL GREEN"
else
  warn "suite reported failures (rc=$rc)"
fi
exit "$rc"
