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
#   --changed     run only the .bats the change→test matrix selects (opt-in).
#   --base <ref>  diff base for --changed (default origin/master → master → HEAD~1).
#   --print-selection  emit the selection plan and run nothing.
#
# CORPFLOW_TEST_SELECT=0 hard-disables selection; a bare invocation is
# byte-for-byte the same full suite it has always been.
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PLUGIN_ROOT"

# Re-entrancy guard, 1 of 2 — read the inherited slot before claiming it. Keyed on
# the tree, not the script: a sandbox copy has its own root and must stay runnable.
RUN_TESTS_OUTER_ROOT="${RUN_TESTS_ACTIVE_ROOT:-}"
export RUN_TESTS_ACTIVE_ROOT="$PLUGIN_ROOT"

BATS="$PLUGIN_ROOT/tests/vendor/bats-core/bin/bats"
COVERAGE="${COVERAGE:-0}"
# Opt-in: a skipped Swift phase stays advisory so hosts with no Apple toolchain
# still pass; set to 1 where Swift coverage is actually being claimed.
RUN_TESTS_REQUIRE_SWIFT="${RUN_TESTS_REQUIRE_SWIFT:-0}"

# Reported even when the suite is green, so green is never read as "everything ran".
skipped_phases=()

SELECT_CHANGED=0
PRINT_SELECTION=0
SELECT_BASE=""
TEST_SELECT="${CORPFLOW_TEST_SELECT:-1}"
# Test seam: lets a guard drive the cap and fallback paths without a real
# selection. Not part of the documented flag surface.
SELECTOR="${RUN_TESTS_SELECTOR:-$PLUGIN_ROOT/tests/bin/select-tests.sh}"

# `while`/`shift`, not `for arg in "$@"`: a `for` loop cannot consume a flag's
# value, so `--base master` would reach the default arm and exit 64 on `master`.
while [ "$#" -gt 0 ]; do
  case "$1" in
    --coverage)        COVERAGE=1 ;;
    --quiet)           : ;;  # bats is terse by default; reserved
    --changed)         SELECT_CHANGED=1 ;;
    --print-selection) PRINT_SELECTION=1; SELECT_CHANGED=1 ;;
    --base)
      if [ "$#" -lt 2 ]; then echo "run-tests.sh: --base needs a value" >&2; exit 64; fi
      SELECT_BASE="$2"; shift
      ;;
    *) echo "run-tests.sh: unknown arg '$1'" >&2; exit 64 ;;
  esac
  shift
done

# kcov's denominator is the source set, independent of which .bats ran, and the
# coverage branch short-circuits before the test list is read — so this pair would
# silently produce a full coverage run that ignored --changed.
if [ "$SELECT_CHANGED" -eq 1 ] && [ "$COVERAGE" = "1" ]; then
  echo "run-tests.sh: --changed and --coverage are mutually exclusive (coverage is a full-suite activity; see tests/COVERAGE.md)" >&2
  exit 64
fi

note() { printf '\033[1;34m[run-tests]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[run-tests]\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31m[run-tests]\033[0m %s\n' "$*" >&2; exit 1; }

# --- bootstrap check: vendored bats must be present --------------------------
if [ ! -x "$BATS" ]; then
  fail "vendored bats missing at $BATS — the repo is incomplete (expected tests/vendor/bats-core). \
See tests/vendor/VENDOR.md."
fi

# Hard prerequisites that the host MUST provide (per AC-1 environment contract).
command -v python3 >/dev/null 2>&1 || fail "python3 not found (required — skill scripts stay Python)"
command -v jq      >/dev/null 2>&1 || fail "jq not found (required)"

# Swift is optional: this plugin orchestrates six platforms and must be testable
# on a host with no Apple toolchain. Presence on PATH is not usability — a
# swiftly shim outlives the toolchain it selects — so probe the binary.
SWIFT_USABLE=0
if command -v swift >/dev/null 2>&1 && swift --version >/dev/null 2>&1; then
  SWIFT_USABLE=1
fi

note "vendored bats: $("$BATS" --version 2>/dev/null || echo '?')"
if [ "$SWIFT_USABLE" -eq 1 ]; then
  note "swift:         $(swift --version 2>/dev/null | head -1)"
else
  note "swift:         unusable or absent — Swift phases will be skipped"
fi
note "python3:       $(python3 --version 2>&1)"

# --- collect shell test files ------------------------------------------------
# All .bats under tests/shell/**. Use find so missing subdirs don't break.
shell_tests=()
while IFS= read -r f; do shell_tests+=("$f"); done < <(
  find "$PLUGIN_ROOT/tests/shell" -type f -name '*.bats' 2>/dev/null | sort
)

# --- change→test selection (opt-in) ------------------------------------------
# The find above stays the full set: it is both the fallback and the superset the
# selection is checked against. A FULL verdict or a selector crash runs everything.
dv_in_progress() {
  local ctx="${CLAUDE_PROJECT_DIR:-$PLUGIN_ROOT}/.context/state.json"
  [ -r "$ctx" ] || return 1
  local running
  # Ledger keys are numbered (DV0, DV1), so strip the index: parallel tracks of one
  # stage are still that stage, not an ambiguity.
  running="$(jq -r '[.tasks // {} | to_entries[] | select(.value.status == "in_progress")
    | .key | sub("[0-9]+$"; "")] | unique | join(",")' \
    "$ctx" 2>/dev/null)" || return 1
  # Ambiguity is not DV: two distinct in-progress stages means the ledger cannot say
  # whose authority applies, and refusing on a guess would block a human mid-run.
  [ "$running" = "DV" ]
}

if [ "$SELECT_CHANGED" -eq 1 ] && [ "$TEST_SELECT" = "0" ]; then
  # --print-selection must still run nothing when selection is disabled; falling
  # through here would turn a "show me the plan" request into a full suite run.
  if [ "$PRINT_SELECTION" -eq 1 ]; then
    printf 'VERDICT\tFULL\tDISABLED\tCORPFLOW_TEST_SELECT=0\n'
    exit 0
  fi
  warn "CORPFLOW_TEST_SELECT=0 — selection disabled, running the full suite"
  SELECT_CHANGED=0
fi

if [ "$SELECT_CHANGED" -eq 1 ]; then
  sel_args=(--changed)
  [ -n "$SELECT_BASE" ] && sel_args+=(--base "$SELECT_BASE")
  sel_err="$(mktemp "${TMPDIR:-/tmp}/rtsel.XXXXXX")"
  sel_rc=0
  sel_out="$("$SELECTOR" "${sel_args[@]}" 2>"$sel_err")" || sel_rc=$?

  if [ "$PRINT_SELECTION" -eq 1 ]; then
    # One renderer: the selector's stream verbatim, so there is no second format
    # that can drift from what the run actually used.
    printf '%s\n' "$sel_out"
    [ "$sel_rc" -eq 0 ] || { warn "selector exited $sel_rc"; cat "$sel_err" >&2; }
    rm -f "$sel_err"
    exit 0
  fi

  sel_verdict="$(printf '%s\n' "$sel_out" | awk -F'\t' '$1 == "VERDICT" { print $2; exit }')"
  if [ "$sel_rc" -ne 0 ]; then
    warn "selector crashed (rc=$sel_rc) — falling back to the full suite"
    cat "$sel_err" >&2 || true
  elif [ "$sel_verdict" = "FULL" ]; then
    note "selection verdict FULL ($(printf '%s\n' "$sel_out" | awk -F'\t' '$1 == "VERDICT" { print $3 " " $4; exit }')) — running the full suite"
  else
    if [ "$sel_verdict" = "WIDE" ]; then
      if dv_in_progress; then
        warn "$(printf '%s\n' "$sel_out" | awk -F'\t' '$1 == "VERDICT" { print $4; exit }')"
        warn "this exceeds DV's scoped authority — hand off to QA for the full suite"
        rm -f "$sel_err"
        exit 65
      fi
      warn "selection is WIDE; proceeding because no DV stage is in progress"
    fi
    selected=()
    while IFS= read -r f; do
      [ -n "$f" ] && selected+=("$PLUGIN_ROOT/$f")
    done < <(printf '%s\n' "$sel_out" | awk -F'\t' '$1 == "SELECT" { print $2 }' | LC_ALL=C sort -u)

    if [ "${#selected[@]}" -eq 0 ]; then
      warn "selection was empty — falling back to the full suite"
    else
      # Both sides through LC_ALL=C sort: comm false-reports on a non-C locale.
      extra="$(comm -13 \
        <(printf '%s\n' "${shell_tests[@]}" | LC_ALL=C sort) \
        <(printf '%s\n' "${selected[@]}" | LC_ALL=C sort))"
      if [ -n "$extra" ]; then
        warn "selection is not a subset of the discovered suite — falling back to the full suite"
        warn "  unexpected: $extra"
      else
        deselected="$(comm -23 \
          <(printf '%s\n' "${shell_tests[@]}" | LC_ALL=C sort) \
          <(printf '%s\n' "${selected[@]}" | LC_ALL=C sort) | grep -c . || true)"
        # A DESELECTED: prefix keeps "ALL GREEN" from ever reading as "everything ran".
        skipped_phases+=("DESELECTED: ${deselected:-0} of ${#shell_tests[@]} bats file(s) not selected by --changed")
        shell_tests=("${selected[@]}")
        note "scoped selection: ${#shell_tests[@]} of $(( ${#shell_tests[@]} + ${deselected:-0} )) bats file(s)"
      fi
    fi
  fi
  rm -f "$sel_err"
fi

# Re-entrancy guard, 2 of 2 — everything above this line runs nothing and stays
# callable from inside a run. Re-entering the execution phases for a tree already
# under test recurses without bound and in silence, because bats captures the
# child's output; fail loudly instead of hanging until the CI job times out.
if [ -n "$RUN_TESTS_OUTER_ROOT" ] && [ "$RUN_TESTS_OUTER_ROOT" = "$PLUGIN_ROOT" ]; then
  fail "re-entered for a tree already under test ($PLUGIN_ROOT). Use --print-selection, or run a sandbox copy with its own root."
fi

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
  skipped_phases+=("bats (no .bats files under tests/shell)")
fi

# --- run swift test phases (ttt-template artifact only) ----------------------
swift_packages=(
  "$PLUGIN_ROOT/benchmark/ttt-template"
)
for pkg in "${swift_packages[@]}"; do
  if [ ! -f "$pkg/Package.swift" ]; then
    warn "swift package missing at $pkg"
    rc=1
  elif [ "$SWIFT_USABLE" -eq 1 ]; then
    note "swift test → ${pkg#$PLUGIN_ROOT/}"
    ( cd "$pkg" && swift test ) || rc=$?
  else
    warn "SKIP swift test → ${pkg#$PLUGIN_ROOT/} (no usable swift toolchain)"
    skipped_phases+=("swift test → ${pkg#$PLUGIN_ROOT/} (no usable swift toolchain)")
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

if [ "${#skipped_phases[@]}" -gt 0 ]; then
  warn "SKIPPED PHASES: ${#skipped_phases[@]}"
  for phase in "${skipped_phases[@]}"; do
    warn "  - $phase"
  done
  if [ "$RUN_TESTS_REQUIRE_SWIFT" = "1" ] && [ "$SWIFT_USABLE" -ne 1 ]; then
    warn "RUN_TESTS_REQUIRE_SWIFT=1 and the Swift phase was skipped — failing the run"
    rc=1
  fi
fi

if [ "$rc" -eq 0 ]; then
  note "ALL GREEN"
else
  warn "suite reported failures (rc=$rc)"
fi
exit "$rc"
