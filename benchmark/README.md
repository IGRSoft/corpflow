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

5. **Stores history**: `benchmark/results/history.json`, newest last, atomic
   tmp→fsync→rename; the other mode's bucket stays byte-identical. Retention is
   per mode (`rotation.RETENTION`): **deterministic keeps 3** (free to reproduce),
   **live keeps everything** — a live record costs real spend and is the only
   evidence of the run that produced it, so rotating it away would destroy the
   samples a variance envelope needs. Live per-run detail files under
   `results/runs/live/` are tracked in git for the same reason; deterministic ones
   stay ignored. Existing records still decode — back-compat is pinned by
   `HistoryBackCompatTests` against a vendored copy of the real file.

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
  **coverage manifest**; `--capture json` (bench-live flag) keeps the
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

**Budget enforcement** — `--budget` bounds what dispatch will START, not what a
run realizes. Both gates decide *before* a stage; a dispatch already in flight
has no cost ceiling, so realized spend can exceed the cap by one stage. Treat
`--budget` as a ceiling on commitments with a one-stage tolerance, and read the
realized figure off the record.

- Pre-flight projection via the real `estimate-calc.py` — rc=2, dispatches
  NOTHING when the projection exceeds `--budget`. Projected per stage from
  `budget.STAGE_EXPECTED_TOKENS`: DV runs an order of magnitude heavier than
  the rest, so one flat figure across the pipeline halves the projection and
  admits budgets that cannot finish. A full paired run projects **~$39**
- Running-tally gate before EACH stage — aborts BEFORE the breaching stage,
  reserving the larger of the next stage's projection and the heaviest stage
  that arm has actually run. Once a stage beats its projection the gate
  reserves the observed figure instead, so only a stage heavier than every
  predecessor can still overshoot
- **Per-arm shares**: a paired run splits `--budget` in half and gives each arm
  its own tally. One shared purse let the arm dispatched first spend the run
  and leave the second truncated, which compares an agent against a budget
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
- **Budget**: the pre-flight projects the stage list once per arm when `real`; each arm
  then runs under its own running-tally gate holding half of `--budget`
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

## Comparability eras

Every record carries an `era` block naming what its numbers can be compared
against — harness generation, prompt-contract version, and the per-stage model
pins read straight from `STAGE_TABLE`:

```json
"era": {"harness": "python-1", "prompt_contract": "scripted-cli-v2",
        "model_pins": {"PL": "claude-opus-5", "DC": "claude-haiku-4-5", …}}
```

`bench-analyze` compares the analyzed record's era against the previous live
record **automatically** and emits a `## validity-caveats` entry naming each
differing dimension — no `--reference` flag required. A record with no `era`
block is itself caveated as unverifiable. Bump `PROMPT_CONTRACT` in
`benchmarklive/dispatch.py` whenever the graded task text changes; a workload
change invalidates comparisons just as surely as a model repin.

**Known era boundaries:**

- **v3.37.1** — `STAGE_TABLE` repinned from the prior Opus/Sonnet generation to
  `claude-opus-5` / `claude-sonnet-5`. Runs from that version on are **not
  comparable** to the stored baselines in `results/history.json`,
  `results/analysis.md`, or `results/token-findings-*.md`. `DC` still dispatches
  `claude-haiku-4-5`, unchanged.
- **Python → Swift → Python harness** — see the wall-clock note above.
- **`scripted-cli-v1`** — the graded CLI contract was added to `dv.txt` and
  `without.txt`, changing the workload for both arms.
- **`scripted-cli-v2`** — the contract now states that stdout stays empty on
  exit 1 and 2. The five reject cases had been grading that silently, so a
  reasonable arm that printed the board before erroring lost them without ever
  being told. Stamped as an era because it is a prompt change, though it only
  narrows what was already being graded.

The first three predate era stamping, so records from before it must be compared
by hand against this list.

## Held-out oracle (quality metric)

Each arm writes its own implementation **and** its own tests, so `swift test`
inside an arm grades nothing an evaluator controls — across every live record
ever stored it has never once returned `fail` for either arm. The oracle
supplies the signal the arm cannot author.

After measurement (outside the arm's Timer, so it never inflates
`wall_clock_s`), the harness release-builds the arm's `tictactoe` product and
drives it through the **scripted CLI contract** — `tictactoe --moves 0,4,1`
prints a board plus a `result:` line, exit 0/1/2. Each of the 30 cases in
`benchmark/oracle/cases.json` is compared on stdout and exit code:

```json
"oracle": {"built": true, "cases_total": 30, "cases_passed": 27, "pass_rate": 0.9,
           "tiers": {"implied":   {"total": 6,  "passed": 3,  "pass_rate": 0.5},
                     "specified": {"total": 24, "passed": 24, "pass_rate": 1.0}}}
```

### Two tiers, two questions

The contract is fully written out in the prompt, so restating it in cases asks
only whether the arm can follow a precise spec — which it can. On the first
paired live run both arms swept every case, and the metric separated nothing.
Cases are therefore tiered:

- **`specified`** (24) — behaviour the prompt enumerates. A failure is
  non-conformance with the contract the arm was handed. This is a floor, not a
  discriminator, and **`pass_fail` reads this tier alone** — an arm is never
  failed for behaviour nobody described to it.
- **`implied`** (6) — behaviour the contract's rules determine without spelling
  out, e.g. that a move listed after the game already ended is never played and
  so is never rejected, or that `--moves` is parsed whole before play so a bad
  token outranks an early stop. Deriving these is the engineering judgement the
  benchmark is trying to detect, so this is the discriminating tier — reported
  beside the verdict, never folded into it.

Two deliberately-wrong reference variants (validating moves before honouring the
early stop; parsing tokens lazily while playing) both score `specified` 24/24 —
the untiered set would have called them perfect — and land at `implied` 0.50 and
0.83. `test_oracle.py` builds the first of them and asserts that separation.

- **Goldens are generated, never hand-written** — `oracle.capture_goldens` runs
  each case against `ttt-template`, the reference implementation. A test
  regenerates them and fails on any drift. This is what keeps the `implied` tier
  honest: the goldens record what the reference *does*, not what anyone assumed.
- **Behaviour, not API shape** — an arm may name its types anything; only the
  CLI contract is graded. stderr wording is deliberately not pinned.
- **Fairness** — `live/prompts/_cli-contract.txt` is the SSOT for the contract
  text, and both `dv.txt` (WITH) and `without.txt` (WITHOUT) must embed it
  verbatim; a lint test fails on drift.
- **`pass_fail` follows the oracle** wherever it ran. Records written before the
  oracle existed keep their self-graded verdict and omit the `oracle` key; those
  written against an untiered case set fall back to the overall rate.

Adding the contract to the prompts changed the workload — runs from that point
are not comparable to earlier stored records.

## Coverage manifest (live, per stage)

With `stream-json` capture, each dispatched stage's `stages[]` entry may carry
an additive `coverage` object **after** `cost_usd` (omitted when nothing was
captured — never fabricated). Nested subagents at depth 2+ are visible in the
stream when `--forward-subagent-text` is set, keyed by their spawning Agent
`tool_use` id — Tier-2 specialist work can be attributed to the stage that
spawned it rather than disappearing into the parent's totals:

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
    tests/                      # 205 test methods (schema/rotation/generators/report/
                                #   history back-compat/import-isolation + live-gate/
                                #   budget/credentials/prompt-assembly/SSOT/coverage/
                                #   app-measure/without-arm/analysis)
      __init__.py               # makes tests/ a package (importlib discovery)
      _helpers.py               # test fakes: Tripwire/RecordingFake/ThrowAtStage/Sequenced
      fixtures/history.json     # vendored real history (byte-compat oracle)
      test_*.py                 # 27 test modules
  oracle/
    cases.json                  # 30 scripted CLI cases (24 specified / 6 implied)
                                # + goldens captured from ttt-template
                                # (regenerated, never hand-written)
  ttt-template/                 # Canonical SwiftUI TTT fixture (SwiftPM package
                                # "TicTacToe": TicTacToeKit + tictactoe exe,
                                # 48 Swift Testing tests; macOS 15+ / iOS 18+)
  live/prompts/                 # _cli-contract.txt — SSOT for the graded CLI contract,
                                # embedded verbatim by dv.txt and without.txt;
                                # pl.txt … st.txt — section [5] task bodies only
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
[, live_partial][, stages][, era]` — `live_partial` only when true, `stages` only
when non-empty, `era` only when stamped. `paths.with` / `paths.without`:

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

`pass_fail` is **fail-closed**: an arm is `"pass"` only when app measurement
succeeded on a non-degraded run. An arm that dispatched but produced nothing
measurable records `"fail"` with `app_path: null` — it is never green by default.
`coverage_pct` is `null` when unmeasured; a literal `0.0` means measured-zero.
Records predating this rule are listed in `results/KNOWN-BAD-RECORDS.md`.

All 5 token keys are ALWAYS emitted (value or null); cache figures are additive
siblings, never summed into `total`. `comparison.<metric>` =
`{"with": …, "without": …, "delta": …}` (`delta` null when either side null).
A present `tokens` block MUST carry all 5 keys; a partial block is rejected. `app_path` stays optional.

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
- `benchmark/harness` — 205 Python harness self-tests (27 modules), zero real
  LLM calls (all dispatchers injected with fakes/tripwires), incl. schema
  byte-compat (vendored real history.json), rotation, generators (real `swift test`
  on generated apps), deterministic/live pipelines, budget/credential gates,
  prompt assembly, stage attribution, app measurement, the paired ±agent arms,
  per-call token accounting, arm symmetry, and offline analysis

**Total:** 48 Swift TTT artifact tests + 205 Python harness tests + 37 Python
skill-script tests = 290 tests green.

**Reference:** `tests/COVERAGE.md` for the Swift/Python coverage story (Python
opportunistic via coverage.py; Swift jq ≥85% line gate with `Sources/TicTacToeKit/Views/`
excluded from the denominator).

## Known Issues

**P1: Temp directory leaks in live mode** — The harness does not clean up temporary workdirs under `$TMPDIR` when a live run completes. Directories matching `ttt_test_with_*`, `ttt_test_without_*`, and `bats-run-*` accumulate and may consume significant disk space over repeated `make benchmark-live` runs. Workaround: manually clean with `rm -rf $TMPDIR/ttt_test_* $TMPDIR/bats-run-*` after benchmark runs. A fix is pending that will atomically clean all artifacts on normal exit (`harness/benchmarklive/budget.py`).

## References

**Findings & evidence:**
- `benchmark/results/token-findings-1.md` — foundational findings (cache_read dominance, ~74%)
- `benchmark/results/token-findings-2.md` — live A/B measurement (n=1, honesty rule)
- `benchmark/results/runs/live/` — raw per-stage live records (token attribution + coverage manifests)
- `benchmark/results/KNOWN-BAD-RECORDS.md` — stored records that must be excluded from comparisons

**Implementation references:**
- `benchmark/harness/benchmarkkit/metrics.py` — BenchmarkRecord schema (ordered JSON)
- `benchmark/harness/benchmarkkit/rotation.py` — per-mode latest-3 atomic rotation
- `benchmark/harness/benchmarklive/preamble.py` — cache-prefix assembly ([1]-[5])
- `benchmark/harness/benchmarklive/dispatch.py` — headless `claude -p` dispatcher + STAGE_TABLE
- `benchmark/harness/benchmarklive/capture.py` — dual-mode stream-json/json capture parser
