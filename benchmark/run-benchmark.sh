#!/usr/bin/env bash
# benchmark/run-benchmark.sh — dual-path TTT benchmark orchestrator (Swift harness).
#
# DEFAULT (deterministic): builds BOTH the WITH and WITHOUT real TTT apps (Swift
# packages), runs each app's Swift Testing suite, records REAL metrics, writes a
# full-schema comparison BenchmarkRecord, and rotates per-mode latest-3 history.
# NO network. NO --live. NEVER touches the live world (AC-8, link-level).
#
# OPT-IN (--live): credential-gated, budget-capped. Shells the live adapter via
# the frozen seam:
#     bench-live --workdir <run_id> --budget <usd> --record <path> [--stages ...]
# bench-live owns dispatch and writes the BenchmarkRecord JSON to <path>.
#
# Usage:
#   benchmark/run-benchmark.sh                                  # deterministic
#   benchmark/run-benchmark.sh --live [--budget U] [--stages PL,AR,DV]
#
# Wall-clock note: harness release build + a ttt-template warm-up build happen
# BEFORE any timing; per-arm app builds/tests stay INSIDE the Timer. Cross-
# boundary wall-clock comparisons with pre-Swift (Python) records are invalid.
set -euo pipefail

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$BENCH_DIR/.." && pwd)"

MODE="deterministic"
LIVE=0
BUDGET="5.00"
STAGES=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --live)     LIVE=1; MODE="live"; shift ;;
    --budget)   BUDGET="${2:?--budget needs a USD value}"; shift 2 ;;
    --budget=*) BUDGET="${1#*=}"; shift ;;
    --stages)   STAGES="${2:?--stages needs a comma-separated code list}"; shift 2 ;;
    --stages=*) STAGES="${1#*=}"; shift ;;
    -h|--help)
      grep '^#' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "run-benchmark.sh: unknown arg '$1'" >&2; exit 64 ;;
  esac
done

if [ -n "$STAGES" ] && [ "$LIVE" != "1" ]; then
  echo "run-benchmark.sh: --stages requires --live" >&2; exit 64
fi

note() { printf '\033[1;36m[benchmark]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[benchmark]\033[0m %s\n' "$*" >&2; exit 1; }

command -v swift >/dev/null 2>&1 || fail "swift toolchain not found (required)"

RUN_TS="$(date -u +%Y%m%dT%H%M%SZ)"
GIT_SHA="$(git -C "$PLUGIN_ROOT" rev-parse --short=7 HEAD 2>/dev/null || echo "nogit")"
RUN_ID="${MODE}-${RUN_TS}-${GIT_SHA}"
WORKDIR="$BENCH_DIR/workdirs/$RUN_ID"
HISTORY="$BENCH_DIR/results/history.json"
RUNS_DIR="$BENCH_DIR/results/runs"
RECORD_PATH="$RUNS_DIR/$MODE/${RUN_ID}.json"
BIN_DIR="$BENCH_DIR/harness/.build/release"

mkdir -p "$WORKDIR" "$RUNS_DIR/$MODE"

# ---------------------------------------------------------------------------
# UNTIMED build phase (before ANY timing): harness release binaries + a
# ttt-template warm-up so per-arm module caches are hot. The per-arm app
# builds/tests remain inside the harness Timer.
# ---------------------------------------------------------------------------
note "building harness (release, untimed)…"
swift build -c release --package-path "$BENCH_DIR/harness" >/dev/null \
  || fail "harness build failed"
note "warming up ttt-template build (untimed)…"
swift build --package-path "$BENCH_DIR/ttt-template" >/dev/null \
  || fail "ttt-template warm-up build failed"

if [ "$LIVE" = "1" ]; then
  # ---------------------------------------------------------------------------
  # LIVE path — the ONLY path that reaches the live world (AC-8).
  # ---------------------------------------------------------------------------
  note "LIVE mode (opt-in). budget=\$$BUDGET run_id=$RUN_ID"
  DISPATCH_BIN="$BIN_DIR/bench-live"
  [ -x "$DISPATCH_BIN" ] || fail "bench-live binary not present at $DISPATCH_BIN"
  note "dispatching via frozen seam…"
  # FROZEN SEAM: exactly this argv (+ optional --stages passthrough).
  set +e
  if [ -n "$STAGES" ]; then
    "$DISPATCH_BIN" \
      --workdir "$RUN_ID" \
      --budget "$BUDGET" \
      --record "$RECORD_PATH" \
      --stages "$STAGES"
  else
    "$DISPATCH_BIN" \
      --workdir "$RUN_ID" \
      --budget "$BUDGET" \
      --record "$RECORD_PATH"
  fi
  rc=$?
  set -e
  # The shell exit stays cosmetic (D6): the adapter already wrote the record
  # (incl. rc=4 partials) to $RECORD_PATH — read granularity from disk.
  [ "$rc" -eq 0 ] || fail "live dispatch returned rc=$rc (record, if any, at $RECORD_PATH)"
else
  # ---------------------------------------------------------------------------
  # DETERMINISTIC path — build both real apps + write the comparison record.
  # ---------------------------------------------------------------------------
  note "DETERMINISTIC mode. run_id=$RUN_ID (no network, no dispatch)"
  "$BIN_DIR/bench-deterministic" \
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
