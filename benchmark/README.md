# Plugin Benchmark — Dual-Path Tic-Tac-Toe A/B Test (Python harness)

Measures plugin overhead via a real, runnable **SwiftUI multiplatform Tic-Tac-Toe
app** (macOS 15+ / iOS 18+) built two ways: **WITH the plugin's staged worktask
pipeline** (staged scaffold driven by the real `estimate-calc.py`) vs **WITHOUT
it** (single-shot baseline). Each generated app ships its own passing **Swift
Testing** suite; the harness runs the tests, captures all metrics, and stores the
latest 3 results per mode as a rolling history.

The harness itself is Python (stdlib-only package `benchmark/harness/` —
`benchmarkkit` + `benchmarklive` + `bin/` entrypoints + `tests/`, zero external
dependencies, no build step). It still subprocesses `swift build` / `swift test`
against the generated apps and the `ttt-template` — that Swift toolchain call IS
the measurement instrument, so swift stays a hard host prerequisite alongside
python3, jq, and make. The plugin's skill scripts (`skills/**/scripts/*.py`) stay
Python and are exercised in-process by the Python skill-script test suite.

## Quick Start

```bash
# Deterministic default (offline, CI-safe, process-overhead comparison)
make benchmark

# Live full-pipeline (opt-in, credential-gated, measures real tokens/cost)
make benchmark-live
make benchmark-live BUDGET=10.00 STAGES=PL,AR,DV   # subset probe

# Render an HTML report (auto-run after a benchmark)
make report        # -> benchmark/results/result.html

# Render an evidence-backed markdown analysis of the latest live run
./benchmark/harness/bin/bench-analyze   # -> benchmark/results/analysis.md

# Or explicitly:
./benchmark/run-benchmark.sh                        # deterministic
./benchmark/run-benchmark.sh --live                 # live, --budget 50.00 default
./benchmark/run-benchmark.sh --live --budget 2.50
./benchmark/run-benchmark.sh --live --stages PL,AR,DV   # targeted stage subset
./benchmark/run-benchmark.sh --live --without-arm skip  # force-skip the WITHOUT baseline
```

## What It Does

1. **Builds a REAL SwiftUI Tic-Tac-Toe app** two ways:
   - **WITH plugin**: staged scaffold — one stage per `Sources/TicTacToeKit/<module>`
     + executable + tests, complexity score from the real `estimate-calc.py`
   - **WITHOUT plugin**: single-shot copy baseline (1 stage, score 0)

2. **Each generated app includes** (from `benchmark/ttt-template/`):
   - SwiftUI views: main menu, animated 3x3 game board with winning-line
     highlight, leaderboard, settings — plus a `--cli` text loop
   - Engine: move validation, win/draw detection, AI opponent (easy random /
     hard minimax); Codable leaderboard + settings persistence; protocol-based
     sound (headless-safe)
   - A passing Swift Testing suite (48 tests) the harness actually runs

3. **Captures ALL metrics** (real, never fabricated):
   - `loc_produced` — non-blank, non-comment `*.swift` lines (excl. `.build`)
   - `test_count` — parsed from the Swift Testing summary (`Test run with N tests`)
   - `pass_fail` — from the `swift test` exit code ONLY
   - `wall_clock_s` — monotonic, per arm (see wall-clock note below)
   - `estimate_complexity_score` / `stage_count` — process-overhead signals
   - `tokens` (in/out/total/cache_read/cache_creation) / `cost_usd` — null in
     deterministic, real in live
   - per-stage `stages[]` attribution + NEW per-stage `coverage` manifest (live)

4. **Computes deltas**: WITH-vs-WITHOUT `comparison` block (`with`/`without`/
   `delta` per metric; live adds `tokens_total` + `cost_usd`).

5. **Stores rolling history**: latest 3 per mode in
   `benchmark/results/history.json`, newest last, atomic tmp→fsync→rename; the
   other mode's bucket stays byte-identical. Existing (pre-Swift) records still
   decode — back-compat is pinned by `HistoryBackCompatTests` against a vendored
   copy of the real file.

## Wall-clock semantics (Swift migration boundary)

The harness release build and one `ttt-template` warm-up build run **before any
timing**; the per-arm app **builds + test runs stay inside the Timer**. SwiftPM
builds cost far more than the old Python file-copy, so **cross-boundary
wall-clock comparisons (Python-era records vs Swift-era records) are invalid** —
compare wall-clock only within records produced by the same harness generation.
Token/cost fields are unaffected by the boundary.

## Modes

### Deterministic (Default)

```bash
make benchmark
```

- Fully offline (zero network; AC-8 is **link-level**: `bench-deterministic`
  cannot even link the live module — asserted by a Package.swift graph test)
- CI-safe (no credential, no randomness)
- `tokens` / `cost_usd` = `null`; all other metrics real
- Exit codes: 0 success, 1 a generated app's tests failed, 64 bad argv

### Live (Opt-In)

```bash
make benchmark-live
./benchmark/run-benchmark.sh --live --budget 3.00
./benchmark/run-benchmark.sh --live --stages DV,QA   # rc=4 tail re-probe
```

- **NEVER CI** — credential-gated, real spend
- Full pipeline PL→AR→TL→DV→DR→SR→QA→DC→FN→ST (10 stages — SR is in the
  benchmark's live pipeline even when a given worktask drops it as a stage),
  one headless `claude -p` dispatch per stage, frozen argv (BOTH arms identical except `--agent`):
  `claude -p --model <m> --effort <e> --permission-mode bypassPermissions
  --settings benchmark/live/settings/benchmark-settings.json
  --output-format <json|stream-json> --agent <agent>`; prompt fed on stdin as
  the assembled `[1][2][3][4][5]` cache-prefix layout
- `--stages CODE[,CODE…]` (or `make benchmark-live STAGES=…`) dispatches a
  validated subset in canonical order — unknown code exits 64
- Default capture is `stream-json`, which additionally yields the per-stage
  **coverage manifest**; `--capture json` (bench-live flag) keeps the legacy
  single-object capture

**Credentials — machine `claude` login is the PREFERRED source;
`ANTHROPIC_API_KEY` is an optional override.** The credential gate accepts
EITHER: (1) an active `claude` login on the machine (checked via
`claude auth status --json`, cheap and non-interactive — no key export needed),
or (2) `ANTHROPIC_API_KEY` in the environment, checked FIRST when present.
**Pitfall:** an `ANTHROPIC_API_KEY` that is actually an OAuth-token-shaped value
(not a real `sk-ant-api…` key) will 401 when used as an API key AND overrides a
working machine login if exported — do NOT `export`/source such a value. If you
rely on the machine login, leave `ANTHROPIC_API_KEY` unset in the invoking
shell. The key VALUE and any CLI-login identity (email/org) are never logged,
echoed, or persisted — presence is the only thing probed. Missing both →
frozen stderr message, rc=3, no dispatch, no record.

**Budget enforcement** (HARD CAP):
- Pre-flight projection via the real `estimate-calc.py` — rc=2, dispatches
  NOTHING when the projection exceeds `--budget`
- Running-tally gate before EACH stage — aborts BEFORE the breaching stage
- Partial record (`live_partial=true`, `pass_fail="fail"`, partial
  `stage_count`) is **written to disk BEFORE rc=4 returns** — read rc=4
  granularity from `results/runs/live/*.json`, not from the shell exit
  (run-benchmark.sh collapses any non-zero adapter rc to exit 1 cosmetically)

**bench-live exit codes:** 0 success · 2 pre-flight decline · 3 no credential ·
4 running-tally breach/degraded (partial record on disk) · 64 bad usage.

## Paired ±agent runner (live)

A live run dispatches **both a WITH-agent arm and a WITHOUT-agent arm**, each executing
the full **10-stage prompt sequence** (PL→AR→TL→DV→DR→SR→QA→DC→FN→ST) in parallel:

- **Symmetric arm folders**: each arm runs under its own dedicated `benchmark/workdirs/<run_id>/{with,without}/`
  directory; generated app, test results, and stage-context logs live inside each arm's folder
- **Shared prompt files**: both arms consume the identical ordered 10-stage prompt files
  (`benchmark/live/prompts/{pl,ar,tl,dv,dr,sr,qa,dc,fn,st}.txt`). Plugin-surface leakage
  (e.g. agent IDs like `apple-developer:ios-developer` or commands like `/swiftui-review`) is
  neutralized from the prompt text so the bare WITHOUT arm sees a fair identical ask
- **Dispatch difference**: WITH arm adds `--agent <stage_name>` to each stage dispatch; WITHOUT
  arm dispatches each stage bare (no `--agent`, no plugin dir) — otherwise frozen argv is identical
- **Policy default**: `real` on a full pipeline run, `skip` on a `--stages` subset — `--without-arm real|skip`
  (`run-benchmark.sh --live` or `bench-live`) overrides the default either way
- **Dispatch order**: the WITHOUT arm is dispatched **FIRST** (all 10 stages), followed by the WITH arm;
  the WITHOUT record is flushed to disk immediately — a later WITH-stage budget breach still leaves a
  real WITH-vs-WITHOUT comparison point on disk
- **Budget**: counts as 10 extra dispatches in the pre-flight projection (`2 * len(stages)`)
  when `real`; the running-tally gate applies to each dispatch exactly like any WITH stage
- **Measurement**: wall-clock and `loc_produced`/`test_count`/`pass_fail`/`stage_count`/tokens are
  measured **per arm** from each arm's own generated app and run record, stored in separate
  `paths.with` and `paths.without` objects in the metric schema
- **Failure handling**: a `DispatchFailure` from an arm is tolerated (the other arm still runs);
  a degraded/failed arm sets `live_partial` and that arm's `pass_fail` to `"fail"`
- **Per-call token accounting**: input and output token counts are persisted for every prompt
  execution in both arms, stored in each arm's run record and captured log, enabling per-prompt
  WITH-vs-WITHOUT token comparison in the analysis output
- **`without_arm="skip"` (mechanism default)**: reproduces the deterministic WITHOUT placeholder
  byte-for-byte — WITHOUT tokens/cost `null`, `wall_clock_s: 0.0`, `stage_count: 1`,
  `pass_fail: "pass"`, `app_path: null`

## Coverage manifest (live, per stage)

With `stream-json` capture, each dispatched stage's `stages[]` entry may carry
an additive `coverage` object **after** `cost_usd` (omitted when nothing was
captured — never fabricated):

```json
{
  "stage": "DV", "fresh_in": 37652, "cache_creation": 56772,
  "cache_read": 207310, "out": 4227, "cost_usd": 0.5,
  "coverage": {
    "agents":   ["apple-developer:macos-developer"],
    "skills":   ["swiftui-skills", "swift-testing-entry"],
    "commands": ["/swiftui-review"],
    "tool_calls": 42
  }
}
```

`make report` rolls distinct agents/skills/commands up per record and computes a
plugin-surface coverage ratio (exercised/declared) at report time from
`agents/*.md`, `commands/*.md`, and `skills/*/SKILL.md` counts. Capture is
layered and degrades honestly: stage stdout (stream-json events or single JSON
object) → `.context/logs/audit.jsonl` → nulls + `live_partial`.

Two runtime guarantees back this chain: the stream-json exit drain scales with
queued bytes (no flat 2s cap), so a slow-reading consumer no longer sees
truncated terminal `result` lines; and SIGTERM during a running Bash tool in a
print/SDK dispatch kills the command's process tree and exits 143, so an
interrupted `claude -p` surfaces as a clean rc=143 rather than an orphaned
tree with a false timeout. The defensive line-skip in Coverage parsing stays
as defense-in-depth.

## Layout

```
benchmark/
  run-benchmark.sh              # Orchestrator (deterministic default, --live opt-in)
  harness/                      # Python package "benchmark harness" (stdlib-only)
    benchmarkkit/               #   deterministic world: metrics/rotation/genlib/
                                #   generators/deterministic_run/report/analysis (7 modules)
    benchmarklive/              #   live world: preamble/dispatch/credentials/
                                #   budget/capture/baseline (6 modules, depends on benchmarkkit)
    bin/
      bench-deterministic       # frozen-argv entrypoint (links benchmarkkit only, AC-8)
      bench-report              # frozen-argv entrypoint (links benchmarkkit only)
      bench-analyze              # frozen-argv entrypoint (links benchmarkkit only)
      bench-live                # frozen-argv entrypoint (only live-world linker)
    tests/                      # 131 test methods (schema/rotation/generators/report/
                                #   history back-compat/import-isolation + live-gate/
                                #   budget/credentials/prompt-assembly/SSOT/coverage/
                                #   app-measure/without-arm/analysis)
      __init__.py               # makes tests/ a package (importlib discovery)
      _helpers.py               # test fakes: Tripwire/RecordingFake/ThrowAtStage/Sequenced
      fixtures/history.json     # vendored real history (byte-compat oracle)
      test_*.py                 # 19 test modules
  ttt-template/                 # Canonical SwiftUI TTT fixture (SwiftPM package
                                # "TicTacToe": TicTacToeKit + tictactoe exe,
                                # 48 Swift Testing tests; macOS 15+ / iOS 18+)
  live/prompts/                 # pl.txt … st.txt — section [5] task bodies only
                                # ([1]-[4] prepended by Preamble at dispatch);
                                # without.txt — WITHOUT-arm prompt, sent verbatim
                                # (no preamble, no --agent)
  results/
    history.json                # Rolling latest-3 per mode (tracked in git)
    analysis.md                 # bench-analyze output (evidence-backed markdown)
    runs/{deterministic,live}/  # Per-run detail records (rotated, latest-3)
  workdirs/<run_id>/{with,without}/   # Generated apps per run (gitignored)
```

## Metric Schema (on-disk, key-for-key)

Top-level: `run_id, timestamp_utc, mode, git_sha, budget_usd, paths, comparison
[, live_partial][, stages]` — `live_partial` only when true, `stages` only when
non-empty. `paths.with` / `paths.without`:

```json
{
  "tokens": {"in": null, "out": null, "total": null,
             "cache_read": null, "cache_creation": null},
  "cost_usd": null,
  "wall_clock_s": 1.9086,
  "loc_produced": 1524,
  "test_count": 48,
  "coverage_pct": 0.0,
  "estimate_complexity_score": 15,
  "stage_count": 9,
  "pass_fail": "pass",
  "app_path": "benchmark/workdirs/<run_id>/with"
}
```

All 5 token keys are ALWAYS emitted (value or null); cache figures are additive
siblings, never summed into `total`. `comparison.<metric>` =
`{"with": …, "without": …, "delta": …}` (`delta` null when either side null).
Legacy records (3 token keys, no `app_path`) still decode.

## bench-analyze (evidence-backed markdown)

```bash
./benchmark/harness/bin/bench-analyze                       # latest live record -> results/analysis.md
./benchmark/harness/bin/bench-analyze --run <record.json>    # analyze a specific record
./benchmark/harness/bin/bench-analyze --reference <record.json>  # flag cross-era comparisons
./benchmark/harness/bin/bench-analyze --history <path> --out <md path>
```

Pure, offline, `benchmarkkit`-only (never imports `benchmarklive` — AC-8). Reads
the latest `live`-mode record (from `--history`, default
`benchmark/results/history.json`; falls back to the newest file under
`results/runs/live/` when history has no live entries yet) and renders
`## totals` (tokens/cost with WITH-vs-WITHOUT premium %), `## per-stage` (arm,
cost share, out-token share, cache-hit %), `## cache-economics` (top
`cache_creation` stages, per arm), `## quality-delta` (loc/tests/pass_fail/
tokens-per-LOC per arm, plus coverage % when measured — omitted when absent),
`## validity-caveats` (`live_partial`, placeholder-WITHOUT, cross-era
token payload, n=1), and a closing `## improvement-candidates` checklist built
**only** from mechanical, threshold-based flags (stage cost/out-token >1.5×
median, a failing arm, degraded capture) — never a fabricated recommendation.
No live records yet → prints a message and exits 0.

## Generated Project Surfacing (U2 visible output)

After a live run, the analysis Markdown (`benchmark/results/analysis.md`) and HTML report
(`benchmark/results/result.html`) each contain a **per-arm "Generated project" section**
showing the Swift file tree, per-file LOC counts, and total LOC for each arm:

```markdown
### with arm — `/Users/…/benchmark/workdirs/live-20260722T053500Z/with`
_total LOC: 165_

| file | LOC |
|---|---|
| Sources/TicTacToeKit/AIOpponent.swift | 68 |
| Sources/TicTacToeKit/Board.swift | 42 |
| Sources/TicTacToeKit/GameViewModel.swift | 55 |

### without arm — `/Users/…/benchmark/workdirs/live-20260722T053500Z/without`
_total LOC: 91_

| file | LOC |
|---|---|
| Sources/TicTacToeKit/AIOpponent.swift | 51 |
| Sources/TicTacToeKit/Board.swift | 40 |
```

The arm folder path (`workdirs/<run_id>/{with,without}`) is the canonical location to inspect
the full generated source and test suite post-run. A zero-spend fixture-driven test sample is
committed to `benchmark/results/samples/analysis-paired-sample.md` demonstrating the rendering.

## Test suites

- `benchmark/ttt-template` — 48 Swift Testing fixture tests (engine/AI/
  leaderboard/settings/router/view-model), also run on iOS Simulator via
  `make test-ios` (SKIPs cleanly on hosts without an iOS runtime)
- `benchmark/harness` — 156 Python harness self-tests (19 modules), zero real
  LLM calls (all dispatchers injected with fakes/tripwires), incl. schema
  byte-compat (vendored real history.json), rotation, generators (real `swift test`
  on generated apps), deterministic/live pipelines, budget/credential gates,
  prompt assembly, stage attribution, app measurement, the paired ±agent arms,
  per-call token accounting, arm symmetry, and offline analysis

**Total:** 48 Swift TTT artifact tests + 131 Python harness tests + 37 Python
skill-script tests = 216 tests green.

**Reference:** `tests/COVERAGE.md` for the Swift/Python coverage story (Python
opportunistic via coverage.py; Swift jq ≥85% line gate with `Sources/TicTacToeKit/Views/`
excluded from the denominator).

## Known Issues

**P1: Temp directory leaks in live mode** — The harness does not clean up temporary workdirs under `$TMPDIR` when a live run completes. Directories matching `ttt_test_with_*`, `ttt_test_without_*`, and `bats-run-*` accumulate and may consume significant disk space over repeated `make benchmark-live` runs. Workaround: manually clean with `rm -rf $TMPDIR/ttt_test_* $TMPDIR/bats-run-*` after benchmark runs. A fix is pending that will atomically clean all artifacts on normal exit (issue tracked in harness/Sources/BenchmarkLive/Budget.swift).

## References

**Findings & evidence:**
- `benchmark/results/token-findings-1.md` — foundational findings (cache_read dominance, ~74%)
- `benchmark/results/token-findings-2.md` — live A/B measurement (n=1, honesty rule)
- `benchmark/results/runs/live/` — raw per-stage live records (token attribution + coverage manifests)

**Implementation references:**
- `benchmark/harness/Sources/BenchmarkKit/Metrics.swift` — BenchmarkRecord schema (ordered JSON)
- `benchmark/harness/Sources/BenchmarkKit/Rotation.swift` — per-mode latest-3 atomic rotation
- `benchmark/harness/Sources/BenchmarkLive/Preamble.swift` — cache-prefix assembly ([1]-[5])
- `benchmark/harness/Sources/BenchmarkLive/Dispatch.swift` — headless `claude -p` dispatcher + STAGE_TABLE
- `benchmark/harness/Sources/BenchmarkLive/Coverage.swift` — dual-mode stream-json/json capture parser
