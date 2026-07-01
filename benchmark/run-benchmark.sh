#!/usr/bin/env bash
# benchmark/run-benchmark.sh — dual-path TTT benchmark orchestrator (DV0d).
#
# DEFAULT (deterministic): builds BOTH the WITH and WITHOUT real TTT apps, runs
# each app's unittest suite, records REAL metrics, writes a full-schema comparison
# BenchmarkRecord, and rotates per-mode latest-3 history. NO network. NO --live.
# NEVER imports or invokes benchmark/live/ (AC-8).
#
# OPT-IN (--live): credential-gated, budget-capped. Shells the DV0e adapter via
# the frozen seam:
#     python3 benchmark/live/dispatch.py --workdir <run_id> --budget <usd> --record <path>
# DV0e owns dispatch.py and writes the BenchmarkRecord JSON to <path>.
#
# Usage:
#   benchmark/run-benchmark.sh                       # deterministic
#   benchmark/run-benchmark.sh --live [--budget U]   # live A/B (opt-in)
set -euo pipefail

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$BENCH_DIR/.." && pwd)"
PYTHON="${PYTHON:-python3}"

MODE="deterministic"
LIVE=0
BUDGET="5.00"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --live)   LIVE=1; MODE="live"; shift ;;
    --budget) BUDGET="${2:?--budget needs a USD value}"; shift 2 ;;
    --budget=*) BUDGET="${1#*=}"; shift ;;
    -h|--help)
      grep '^#' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "run-benchmark.sh: unknown arg '$1'" >&2; exit 64 ;;
  esac
done

note() { printf '\033[1;36m[benchmark]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[benchmark]\033[0m %s\n' "$*" >&2; exit 1; }

RUN_TS="$(date -u +%Y%m%dT%H%M%SZ)"
GIT_SHA="$(git -C "$PLUGIN_ROOT" rev-parse --short=7 HEAD 2>/dev/null || echo "nogit")"
RUN_ID="${MODE}-${RUN_TS}-${GIT_SHA}"
WORKDIR="$BENCH_DIR/workdirs/$RUN_ID"
HISTORY="$BENCH_DIR/results/history.json"
RUNS_DIR="$BENCH_DIR/results/runs"
RECORD_PATH="$RUNS_DIR/$MODE/${RUN_ID}.json"

mkdir -p "$WORKDIR" "$RUNS_DIR/$MODE"

if [ "$LIVE" = "1" ]; then
  # ---------------------------------------------------------------------------
  # LIVE path — the ONLY path that reaches benchmark/live/ (AC-8). DV0e owns it.
  # ---------------------------------------------------------------------------
  DISPATCH="$BENCH_DIR/live/dispatch.py"
  note "LIVE mode (opt-in). budget=\$$BUDGET run_id=$RUN_ID"
  if [ ! -f "$DISPATCH" ]; then
    fail "live dispatch adapter not present at $DISPATCH (DV0e not landed). \
Deterministic mode is unaffected; re-run without --live."
  fi
  note "dispatching to DV0e adapter via frozen seam…"
  # FROZEN SEAM (DV0d<->DV0e): exactly this argv.
  "$PYTHON" "$DISPATCH" \
    --workdir "$RUN_ID" \
    --budget "$BUDGET" \
    --record "$RECORD_PATH"
  rc=$?
  [ "$rc" -eq 0 ] || fail "live dispatch returned rc=$rc (see DV0e adapter output)"
else
  # ---------------------------------------------------------------------------
  # DETERMINISTIC path — build both real apps + write the comparison record.
  # Pure Python orchestration (keeps schema/rotation logic in one place).
  # ---------------------------------------------------------------------------
  note "DETERMINISTIC mode. run_id=$RUN_ID (no network, no live dispatch)"
  # Delegate to the pure-Python orchestrator (testable; keeps shell thin).
  PYTHONPATH="$BENCH_DIR/lib" "$PYTHON" "$BENCH_DIR/lib/deterministic_run.py" \
    --workdir "$WORKDIR" \
    --run-id "$RUN_ID" \
    --timestamp "$RUN_TS" \
    --git-sha "$GIT_SHA" \
    --record "$RECORD_PATH" \
    --history "$HISTORY" \
    --runs-dir "$RUNS_DIR" \
    || fail "deterministic benchmark failed"
fi

note "done ($MODE)."
