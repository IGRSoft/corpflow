# Plugin Benchmark — Dual-Path Tic-Tac-Toe A/B Test

Measures plugin overhead via a real, runnable Python Tic-Tac-Toe app built two ways: **WITH the plugin's staged worktask pipeline** (5 stages: estimate → scaffold → test → review → commit) vs **WITHOUT it** (single-shot baseline). Each generated app ships its own passing `unittest` suite; the harness runs the tests, captures all metrics, and stores the latest 3 results per mode as a rolling history.

## Quick Start

```bash
# Deterministic default (offline, CI-safe, process-overhead comparison)
make benchmark

# Live full-pipeline (opt-in, requires API key, measures real tokens/cost)
make benchmark-live

# Render an HTML report of all metrics + generated-app paths (auto-run after a benchmark)
make report        # -> benchmark/results/result.html  (open in a browser)

# Or explicitly:
./benchmark/run-benchmark.sh           # deterministic
./benchmark/run-benchmark.sh --live    # live with --budget 5.00 (USD)
./benchmark/run-benchmark.sh --live --budget 2.50  # custom budget cap
```

## What It Does

1. **Builds a REAL Python Tic-Tac-Toe app** two ways:
   - **WITH plugin**: staged worktask pipeline (5 stages, estimate-calc → scaffold → test → review bookkeeping)
   - **WITHOUT plugin**: single-shot baseline (no stages, direct generation)

2. **Each generated app includes**:
   - CLI interface + optional curses TUI
   - Core game logic: board state, win/draw detection, move validation
   - Stdlib `unittest` suite testing win/draw/move scenarios
   - Real passing tests (both paths ship valid 9/9 pass)

3. **Captures ALL metrics**:
   - `loc_produced` — lines of code generated
   - `test_count` — number of `unittest` test cases
   - `wall_clock_s` — real elapsed wall-clock seconds
   - `estimate_complexity_score` — with-plugin only (estimate-calc.py output)
   - `stage_count` — 5 (with) vs 1 (without)
   - `pass_fail` — unittest suite result
   - `tokens` / `cost_usd` — null in deterministic, real in live
   - `coverage_pct` — unittest coverage % (reported by unittest discovery)

4. **Computes deltas**: WITH-vs-WITHOUT comparison in a `comparison` block with:
   - `delta_loc_produced`, `delta_test_count`, `delta_wall_clock_s`, etc.
   - `stage_count_ratio` (5:1)

5. **Stores rolling history**: latest 3 results per mode (deterministic + live) in `benchmark/results/history.json`, newest last. On the 4th run of a mode, the oldest is dropped.

## Modes

### Deterministic (Default)

```bash
make benchmark
```

**Characteristics:**
- Fully offline (zero network calls)
- CI-safe (no API key required, no randomness)
- Process-overhead comparison: same template TTT app built both paths, quality held constant
- Deterministic `run_id` (timestamp + hash)
- `tokens` / `cost_usd` = `null` (no LLM)
- All other metrics are real measured values

**Use case:** continuous integration, baseline perf tracking, plugin overhead quantification.

### Live (Opt-In)

```bash
make benchmark-live

# Or with custom budget:
./benchmark/run-benchmark.sh --live --budget 3.00
```

**Characteristics:**
- **NEVER CI** — requires API key, real spend, credential handling
- Full real worktask pipeline: PL→AR→TL→DV→DR→SR→QA→DC→FN→ST
- WITH-path runs through all 10 stages; WITHOUT-path baseline stays 1 stage
- Measures real tokens/cost/quality deltas
- `tokens` / `cost_usd` populated from claude agents run dispatch
- `mode` = `"live"`
- `budget_usd` (default 5.00, configurable via `--budget <usd>`)

**Credential handling** (FAIL-FAST):
- Checks `ANTHROPIC_API_KEY` presence before stage 1
- Key VALUE never logged/echoed/persisted (presence-probe only)
- Missing key → stderr message, returns rc=3, no dispatch, no record

**Budget enforcement** (HARD CAP):
- Pre-flight projection via `estimate-calc.py` — declines entire run if estimate exceeds budget
- Running-tally gate before EACH stage — aborts BEFORE the breaching stage
- Partial record written if run aborts (sets `live_partial=true`, `pass_fail="fail"`, partial `stage_count`)
- Returns rc=4 on budget breach (vs rc=0 success, rc=2 pre-flight decline, rc=3 no-credential)

**Use case:** quality comparison (WITH leverages human-in-loop review; WITHOUT is raw LLM), cost modeling, live fidelity testing.

## Output & History

```
benchmark/
  run-benchmark.sh                  # Orchestrator (deterministic default, --live opt-in)
  results/
    history.json                    # Rolling latest-3 per mode (tracked in git)
    runs/
      deterministic/
        <run_id1>.json              # Full BenchmarkRecord (gitignored per-run detail)
        <run_id2>.json
        …
      live/
        <run_id1>.json
        …
  workdirs/
    <run_id>/                       # Generated app per run (gitignored scratch)
      generated_with_plugin/
      generated_without_plugin/
  ttt-template/                     # Canonical shared TTT package template
    tictactoe/
      board.py
      cli.py
      tui.py
    tests/
      test_board.py                 # 9 unittest cases (all pass)
  with-plugin/
    generate.py                     # Generator driving plugin's estimate→scaffold→test→review
  without-plugin/
    generate.py                     # Single-shot baseline generator
  lib/
    metrics.py                      # Frozen BenchmarkRecord dataclass + JSON I/O
    genlib.py                       # Shared generator helpers (loc_count, run_app_tests, Timer)
    rotation.py                     # Per-mode latest-3 atomic rotation (tmp→fsync→rename)
    deterministic_run.py            # Deterministic orchestration (no live path)
  live/
    dispatch.py                     # Live pipeline adapter: claude agents run PL→AR→…→ST
    credentials.py                  # API key probe (fail-fast)
    budget.py                       # Pre-flight + running-tally enforcement
    prompts/
      pl.txt, ar.txt, …, st.txt    # Per-stage prompts (10 total, deterministic)
      README.md
  tests/
    with-plugin/
      test_metrics_schema.py        # AC-6: metric schema validity (26 tests)
      test_generators.py            # AC-5: real app generation + tests pass (13 tests)
      test_rotation_per_mode.py     # AC-7: latest-3 per-mode rotation (21 tests)
    live/
      test_live_gate.py             # AC-8: default deterministic never touches live (tripwire)
      test_budget_enforcement.py    # Budget pre-flight decline + running-tally abort
      test_credential_probe.py      # Missing/empty key fast-exit with frozen message
```

## Metric Schema

**BenchmarkRecord** (stdlib JSON):

```python
{
  "run_id": "20240630T120000_abc123",  # Deterministic timestamp + hash
  "timestamp_utc": "2024-06-30T12:00:00Z",
  "mode": "deterministic" | "live",
  "git_sha": "abc123def456",
  
  # Per-path metrics (WITH-plugin and WITHOUT-plugin)
  "with": {
    "tokens": {
      "input_tokens": 1234,
      "output_tokens": 567,
      "total_tokens": 1801
    },
    "cost_usd": 0.123,           # null if deterministic
    "wall_clock_s": 12.34,
    "loc_produced": 275,
    "test_count": 9,
    "coverage_pct": 85.2,
    "estimate_complexity_score": 15,  # estimate-calc.py output
    "stage_count": 5,
    "pass_fail": "pass"
  },
  "without": {
    "tokens": {
      "input_tokens": null,      # deterministic only
      "output_tokens": null,
      "total_tokens": null
    },
    "cost_usd": null,            # null if deterministic
    "wall_clock_s": 2.10,
    "loc_produced": 275,
    "test_count": 9,
    "coverage_pct": 85.2,
    "estimate_complexity_score": 0,  # baseline; no estimation
    "stage_count": 1,
    "pass_fail": "pass"
  },
  
  # Comparison (WITH-vs-WITHOUT)
  "comparison": {
    "delta_loc_produced": 0,                    # both paths same template
    "delta_test_count": 0,
    "delta_wall_clock_s": 10.24,               # with overhead
    "delta_tokens": 1801,                       # null-safe sum
    "delta_cost_usd": 0.123,
    "stage_count_ratio": "5:1"
  },
  
  # Live-only fields
  "budget_usd": 5.00,            # live mode cap (null if deterministic)
  "live_partial": false,         # true if run aborted / degraded
  
  # Metadata
  "with_plugin_path": "…/workdir/generated_with_plugin/",
  "without_plugin_path": "…/workdir/generated_without_plugin/"
}
```

All values are real measured (not fabricated). In deterministic mode, `tokens`/`cost_usd` are `null`. In live mode, partial records are written if the run aborts mid-pipeline (budget breach, credential fail, dispatch error).

## Running the Benchmark

### Deterministic (Default)

```bash
# Single run
make benchmark

# Inspect the latest result
cat benchmark/results/runs/deterministic/$(ls -t benchmark/results/runs/deterministic/ | head -1)

# View rolling history
cat benchmark/results/history.json | jq '.deterministic'
```

**Output:**
```
Benchmark (deterministic)
[...]
✓ WITH-plugin: 275 loc, 9 tests, stage_count=5, wall_clock=12.34s
✓ WITHOUT-plugin: 275 loc, 9 tests, stage_count=1, wall_clock=2.10s
✓ Comparison: delta_wall_clock=+10.24s (overhead)
✓ History rotated: 3/3 deterministic records retained
```

**Exit codes:**
- 0 — success
- non-zero — app generation failed, tests failed, or history rotation failed

### Live

```bash
export ANTHROPIC_API_KEY="sk-…"

# Default budget (5.00 USD)
make benchmark-live

# Custom budget
./benchmark/run-benchmark.sh --live --budget 2.50

# Inspect live record
cat benchmark/results/runs/live/$(ls -t benchmark/results/runs/live/ | head -1)
```

**Exit codes:**
- 0 — success
- 2 — pre-flight budget decline (record not written)
- 3 — missing/empty credential (record not written)
- 4 — running-tally budget breach (partial record written)
- non-zero — dispatch/app gen/test failure

**Environment variables** (live only):
- `ANTHROPIC_API_KEY` — required (fail-fast if missing)
- `CLAUDE_BUDGET` — optional, overrides `--budget` arg (for CI integration)

## Coverage Story

The benchmark measures its own quality via test harness coverage:

**60 harness self-tests** (`benchmark/tests/with-plugin/`):
- schema validation (26 tests)
- real app generation + unittest execution (13 tests)
- per-mode rotation correctness (21 tests)

**17 live-gate tests** (`benchmark/tests/live/`):
- AC-8 tripwire: default `make benchmark` never imports `benchmark/live/` (confirmed)
- Budget pre-flight decline + running-tally abort scenarios
- Credential probe (absent/empty key fast-exit)
- All tests use injected fake/tripwire dispatcher (zero LLM calls in test suite)

**Reference:** `tests/COVERAGE.md` for the full test suite's 94%/92% Python coverage and bash assertion-density proxy.

## Known Issues

### F5 (P2) — Live STAGE_TABLE Model Drift

`benchmark/live/dispatch.py` line ~71 pins `DR` stage to `claude-sonnet-4-6` (sonnet tier), but the canonical spec (`CLAUDE.md`, `stage-codes.md`, `headless-dispatch.md`) specifies DR=`claude-opus-4-8` (opus tier, xhigh effort). This is a **benchmark fidelity issue only** (no security/budget impact) — live WITH-path will measure DR via sonnet instead of opus, making cost/stage-latency deltas artificially lower than production. **Reconciliation needed for live fidelity**, but non-blocking for deterministic mode.

## References

- `planning-0.md#scope` — benchmark requirements (REQ-4 through REQ-7)
- `analyzing-0.md` — dual-path + live dispatch architecture
- `coordination-0.md` — 5-track DV partition (DV0d owns benchmark harness)
- `development-0.md#DV0d-Handoff` — delivered files + verification results
- `testing-0.md` — AC-5/6/7/8 test results
- `benchmark/lib/metrics.py` — BenchmarkRecord schema (frozen dataclass)
- `benchmark/lib/rotation.py` — per-mode latest-3 atomic rotation implementation
