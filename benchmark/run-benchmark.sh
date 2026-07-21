#!/usr/bin/env bash
# benchmark/run-benchmark.sh — dual-path TTT benchmark orchestrator (Python harness).
#
# DEFAULT (deterministic): builds BOTH the WITH and WITHOUT real TTT apps (Swift
# packages), runs each app's Swift Testing suite, records REAL metrics, writes a
# full-schema comparison BenchmarkRecord, and rotates per-mode latest-3 history.
# NO network. NO --live. NEVER touches the live world (AC-8, import-level).
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
# Wall-clock note: a ttt-template warm-up build happens BEFORE any timing; per-arm
# app builds/tests stay INSIDE the harness Timer. The Python harness itself needs
# no build step (stdlib only). swift stays a hard prerequisite — the harness still
# subprocesses `swift test` on the generated apps (the measurement instrument).
set -euo pipefail

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$BENCH_DIR/.." && pwd)"

MODE="deterministic"
LIVE=0
BUDGET="50.00"
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

command -v swift   >/dev/null 2>&1 || fail "swift toolchain not found (required)"
command -v python3 >/dev/null 2>&1 || fail "python3 not found (required — Python harness)"

RUN_TS="$(date -u +%Y%m%dT%H%M%SZ)"
GIT_SHA="$(git -C "$PLUGIN_ROOT" rev-parse --short=7 HEAD 2>/dev/null || echo "nogit")"
RUN_ID="${MODE}-${RUN_TS}-${GIT_SHA}"
WORKDIR="$BENCH_DIR/workdirs/$RUN_ID"
HISTORY="$BENCH_DIR/results/history.json"
RUNS_DIR="$BENCH_DIR/results/runs"
RECORD_PATH="$RUNS_DIR/$MODE/${RUN_ID}.json"
HARNESS_BIN="$BENCH_DIR/harness/bin"

mkdir -p "$WORKDIR" "$RUNS_DIR/$MODE"

# ---------------------------------------------------------------------------
# UNTIMED warm-up (before ANY timing): a ttt-template build so per-arm module
# caches are hot. The per-arm app builds/tests remain inside the harness Timer.
# The Python harness has no build step of its own.
# ---------------------------------------------------------------------------
note "warming up ttt-template build (untimed)…"
swift build --package-path "$BENCH_DIR/ttt-template" >/dev/null \
  || fail "ttt-template warm-up build failed"

if [ "$LIVE" = "1" ]; then
  # ---------------------------------------------------------------------------
  # LIVE path — the ONLY path that reaches the live world (AC-8).
  # ---------------------------------------------------------------------------
  note "LIVE mode (opt-in). budget=\$$BUDGET run_id=$RUN_ID"
  note "dispatching via frozen seam…"
  # FROZEN SEAM: exactly this argv (+ optional --stages passthrough).
  set +e
  if [ -n "$STAGES" ]; then
    python3 "$HARNESS_BIN/bench-live" \
      --workdir "$RUN_ID" \
      --budget "$BUDGET" \
      --record "$RECORD_PATH" \
      --stages "$STAGES"
  else
    python3 "$HARNESS_BIN/bench-live" \
      --workdir "$RUN_ID" \
      --budget "$BUDGET" \
      --record "$RECORD_PATH"
  fi
  rc=$?
  set -e
  # The shell exit stays cosmetic (D6): the adapter already wrote the record
  # (incl. rc=4 partials) to $RECORD_PATH — read granularity from disk.
  [ "$rc" -eq 0 ] || fail "live dispatch returned rc=$rc (record, if any, at $RECORD_PATH)"
  # Rotate the completed live record into per-mode latest-3 history + runs
  # detail (the deterministic arm does this inside bench-deterministic).
  # rotate() appends same-run_id entries, so a script rerun must skip ingest.
  PYTHONPATH="$BENCH_DIR/harness${PYTHONPATH:+:$PYTHONPATH}" python3 -c '
import json, sys
from benchmarkkit import rotation
record_path, history_path, runs_dir = sys.argv[1], sys.argv[2], sys.argv[3]
with open(record_path) as f:
    record = json.load(f)
rid = record.get("run_id", "")
try:
    with open(history_path) as f:
        existing = [r.get("run_id") for r in json.load(f).get(record.get("mode", "live"), [])]
except (OSError, ValueError):
    existing = []
if rid and rid in existing:
    sys.exit(0)
rotation.rotate(history_path, record)
rotation.rotate_detail(runs_dir, rid, record)
' "$RECORD_PATH" "$HISTORY" "$RUNS_DIR" || fail "live history rotation failed"
  note "live record rotated into history."
else
  # ---------------------------------------------------------------------------
  # DETERMINISTIC path — build both real apps + write the comparison record.
  # ---------------------------------------------------------------------------
  note "DETERMINISTIC mode. run_id=$RUN_ID (no network, no dispatch)"
  python3 "$HARNESS_BIN/bench-deterministic" \
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
