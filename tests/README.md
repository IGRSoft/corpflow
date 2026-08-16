# Plugin Test Suite

Exhaustive unit tests for all deterministic plugin scripts and hooks: bats for
bash, stdlib Python unittest for skill-script tests and benchmark harness, and
Swift Testing for the TTT artifact package — with kcov (bash), opportunistic
coverage.py (Python), and `swift test --enable-code-coverage` (Swift)
line-coverage gating.

## Quick Start

Run the full deterministic suite:
```bash
make test              # All tests, offline, bootstrap as needed
make coverage          # Plus kcov + swift coverage gating (≥85% target)
make test-ios          # TicTacToeKit on an iOS Simulator (SKIPs w/o runtime)
make bootstrap         # Vendors bats, checks swift toolchain, probes kcov
```

No system `bats` or `kcov` required — `make bootstrap` auto-provisions via:
- **bats**: vendored under `tests/vendor/bats-core/` (v1.11.0 + support/assert)
- **swift**: hard host prerequisite (Swift 6 toolchain; checked, not installed)
- **kcov**: system probe → brew → documented per-file proxy (macOS bash 3.2)

## Organization

```
tests/
  shell/
    hooks/             # 11 bats files: agent-stop, anchor-preflight, state-merge, …
    worktask/          # 16 bats files: state-patch, publish-pl-issue, cache-lint, …
    dv-screenshot/     # 6 bats files: apple-canvas, cli-fallback, size-budget, visual-diff,
                       #               web-capture, android-capture
    skills/            # 15 bats files: build-orchestrator, scan-secrets, build-context-set, …
    benchmark/         # 2 bats files: run-benchmark, canvas-e2e-guards
    lib/               # 1 bats file: test-helper (self-test for the shared helper API)
    meta/              # 1 bats file: coverage-proxy (the standing coverage gate)
  python/              # Skill-script tests (stdlib unittest)
    _scriptimport.py   # importlib loader for hyphenated scripts + JSON helpers
    test_estimate_calc.py   # 21 behaviors via in-process import + CLI smoke
    test_layout_calc.py     # 16 behaviors via in-process import + CLI smoke
  vendor/
    bats-core/         # v1.11.0 — pinned tag, no network after vendor
    bats-support/      # v0.3.0
    bats-assert/       # v2.1.0
  lib/
    test_helper.bash   # Frozen API for all .bats files (see below)
  fixtures/
    hooks/             # JSON/markdown fixtures: audit payloads, plan frontmatter, issues
    worktask/          # state.json samples, development.md snippets
    skills/            # Secret fixtures (synthetic), estimate inputs, TTT spec
    README.md          # Fixture collision-safety index (path-keyed names)
  COVERAGE.md          # Per-file coverage report + proxy exemptions (AC-3 gate)
```

Two other test suites live with their packages:
`benchmark/ttt-template/Tests/TicTacToeKitTests` (48 fixture tests, Swift artifact)
and `benchmark/harness/tests/` (350 Python harness self-tests, zero real LLM calls).
`make test` runs all via `run-tests.sh`: bats + Python skill-script tests + Python
harness tests + Swift ttt-template artifact tests.

**`benchmark/ttt-template/` is the single source for the TicTacToe fixture.** The hand-maintained
duplicate at `examples/tictactoe/` (30 files, 1817 lines) was deleted — every source file was
verified byte-identical to its `ttt-template` counterpart, and its own README admitted it had to be
regenerated after each fixture change. A README stub remains at that path pointing here; add fixture
tests to `benchmark/ttt-template/Tests/` only.

## Test Coverage

**Verdict: AC-3 MET** (Python measured via opportunistic coverage.py, Swift via
llvm-cov, bash via assertion-density proxy).

### Skill scripts (in-process import + CLI smoke via tests/python)

The plugin's skill runtime scripts STAY Python and are exercised by
`tests/python` via importlib in-process import (asserting real contracts) plus
CLI smoke tests:

| Script | Tests | Coverage approach |
|--------|-------|-------------------|
| `skills/estimation-methodology/scripts/estimate-calc.py` | **21** in-process behaviors | importlib + CLI argparse smoke |
| `skills/appstore-screenshots/scripts/layout-calc.py` | **16** in-process behaviors | importlib + CLI argparse smoke |

In-process testing asserts true contracts (unknown-model → sonnet fallback,
unknown-layout → ValueError) rather than approximating via subprocess; each
script's built-in `--self-test` provides additional validation. Coverage
measurement via coverage.py is opportunistic (present on host → reported,
absent → behavioral gates remain the hard requirement).

### Python harness tests (stdlib unittest via benchmark/harness/tests)

Benchmark harness self-tests (202 methods across 16 modules) exercise schema
byte-compat, rotation, generators, deterministic/live pipelines, budget/credential
gates, and prompt assembly — all with injected fakes, zero real LLM calls. Measured
via opportunistic coverage.py.

### Swift packages (measured via swift test --enable-code-coverage)

`make coverage` runs each package with coverage enabled and gates aggregate
line coverage at **≥85%** via jq over the llvm-cov export JSON.
`Sources/TicTacToeKit/Views/` is excluded from the denominator (SwiftUI view
bodies are exercised structurally, not unit-covered — see
`tests/COVERAGE.md`).

### Bash (via assertion-density proxy)

kcov **cannot run on macOS bash 3.2** (mis-parses `BASH_VERSINFO` guards; >2 min/file). Per the locked q3 resolution, coverage is validated via the **q3 assertion-density proxy**: every shell script has a dedicated test file with ≥3 real scenarios (happy / edge / failure-exit), asserting its documented contracts.

- Every deterministic target is covered, zero exemptions on file. The target set and its
  per-file verdict are enumerated by `meta/coverage-proxy.bats`, which globs `hooks/*.sh`
  and `skills/**/scripts/*` at run time — read its failure output for the current roster
  rather than a hand-maintained count here, which drifts silently between releases.
- **60 bats files**, split between files dedicated to one script and meta / repo-invariant
  files that guard a contract instead (`meta/{coverage-proxy,test-selection}`,
  `lib/test-helper`, `skills/{test-authority-matrix,cross-plugin-refs,plugin-root-refs,skill-refs}`,
  `worktask/{artifact-map-parity,manifest-parity,gh-issue-dedup}`,
  `benchmark/{run-benchmark,canvas-e2e-guards}`).
- **924 `@test`** assertions across those 60 files.
- **Min 3 / avg ~15 / max 90** scenarios per file. The ≥3 rule now has **no exceptions** — the one
  standing exception (`comment-hooks-self-test.bats`, 2 self-delegating tests) was deleted, and
  `meta/coverage-proxy.bats` enforces the rule as an executable gate with an empty exemption list.

**Do not increment these numbers — re-derive them.** They were hand-tracked for several releases and
drifted badly (this document claimed 36/36 targets, 46 files and 466 tests while `COVERAGE.md`
simultaneously claimed 34/34; the 53/680 figures they were corrected to had themselves drifted by well over a hundred tests by the time selection landed). The commands below are the contract; they
exclude the vendored bats trees, which contain their own `.bats` suites:

```bash
# 60 — test files
find tests -name '*.bats' -not -path '*/vendor/*' | wc -l

# 924 — test cases (every declaration is column-0 `^@test `)
grep -rh --include='*.bats' '^@test ' tests --exclude-dir=vendor | wc -l

# independent cross-check of the same 924
find tests -name '*.bats' -not -path '*/vendor/*' -exec grep -c '^@test ' {} + \
  | awk -F: '{s+=$NF} END {print s}'
```

Provenance, so the figures are not over-claimed: QA measured **677** across two consecutive full runs
with byte-identical TAP streams. The final **3** were added afterwards by the documentation pass
itself (`worktask/manifest-parity.bats`, 3 → 6, covering frontmatter-wired hooks), so 680 is the
re-derived tree total for that release; the current figure is 924 and is re-derived, never incremented.

High-logic-density targets (14+ scenarios):
- `branch-name.sh` (90), `test-execution-gate` (85), `branch-lib` (54), `fn-preflight` (52)
- `refine-branch-target` (31), `state-patch` (25), `test-helper` (23), `pr-body-lint` (19)
- `attach-visual-evidence`, `milestone-helpers` (18 each), `scan-secrets` (17)
- `publish-pl-issue`, `handoff-harness` (14 each)

**Real bash line coverage** is obtainable on a **GNU/Linux host** (bash ≥4 + kcov). The `make coverage` kcov stem sed bug was fixed; on Linux it now works end-to-end.

### Swift (measured, per package)

- `benchmark/ttt-template` — 48 Swift Testing tests (engine, AI, models, router, view-model); the iOS slice runs via `make test-ios` (xcodebuild, iPhone simulator; SKIPs cleanly without a runtime)

**Total deterministic suite:** 924 bats tests + 52 Python skill-script tests + 350 Python harness
tests + 48 Swift ttt-template tests = **1374 test methods** green (`./run-tests.sh` rc 0).

See `tests/COVERAGE.md` for per-file details and proxy exemption policy.

## Test Helper API (Frozen)

All `.bats` files load a shared frozen API from `tests/lib/test_helper.bash`:

```bash
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"
```

**Exposed after load:**
- `$PLUGIN_ROOT` — absolute repo root (parent of `tests/`). Use for all file paths.
- `$FIXTURES` — `$PLUGIN_ROOT/tests/fixtures`.
- `run_script <relpath> [args…]` — runs target under bats `run` (sets `$status`/`$output`/`$lines`). Dispatch by extension: `*.py`→python3, `*.sh`→bash, else direct exec. Example: `run_script skills/worktask/scripts/state-patch.sh --self-test`.
- `mk_tmpworkdir` — prints an `mktemp -d` dir under `BATS_TMPDIR`; auto-removed by default `teardown()`. If you define your own `teardown()`, call `_test_helper_cleanup` to keep auto-cleanup.
- **bats-support + bats-assert** pre-loaded: `assert_success`, `assert_failure`, `assert_output`, `assert_line`, etc. available directly.

## Adding a New Test

Path-keyed naming: if testing `skills/self-improvement/scripts/build-context-set.sh`, the test file is:
```
tests/shell/skills/build-context-set.bats  # Not "self-improvement__build-context-set"
```

**Minimum test template:**
```bash
#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

@test "happy path: script succeeds with valid input" {
  run_script skills/self-improvement/scripts/build-context-set.sh --input /path/to/dir
  assert_success
}

@test "edge case: empty context directory" {
  tmpdir=$(mk_tmpworkdir)
  run_script skills/self-improvement/scripts/build-context-set.sh --input "$tmpdir"
  assert_success
}

@test "failure: missing input file" {
  run_script skills/self-improvement/scripts/build-context-set.sh --input /nonexistent
  assert_failure
}
```

Each script should have ≥3 scenarios (happy / edge / failure) asserting its documented contract (exit codes, JSON output, file format, idempotency, self-test behavior).

## Running Tests

```bash
# Deterministic suite (default)
make test

# With coverage measurement (kcov + coverage.py)
make coverage

# Specific test file
bats tests/shell/hooks/agent-stop.bats

# Single test by name
bats tests/shell/hooks/agent-stop.bats --filter "happy path"

# Verbose (show all assertions)
bats tests/shell/hooks/agent-stop.bats --verbose
```

## Test Selection

`./run-tests.sh --changed` runs only the `.bats` your change can affect. It is
**opt-in**: a bare `./run-tests.sh` is the same full suite it has always been.

```bash
make test-changed              # scoped run against the default base
make test-changed BASE=master  # pick the diff base
make test-select               # print the plan, run nothing
```

Selection is a union of three layers, and its only permitted error is
over-selection:

| Layer | Source | What it catches |
|---|---|---|
| L1 | computed live — every repo path a `.bats` names literally, plus the `X.sh` → `X.bats` convention resolver | 13 scripts have more than one consumer; convention alone returns one of them |
| L2 | `tests/selection/matrix.tsv` | dependencies that are a *pattern*, not a path — the glob lives inside the script the test invokes |
| L3 | a constant in `tests/lib/select_lib.bash` | the ALWAYS floor: `lib/test-helper`, `meta/coverage-proxy`, `skills/plugin-root-refs`, `worktask/manifest-parity` (48 of 924 tests) |

**Fail-closed.** An unrecognised path, an unresolvable base, an empty changed
set, a delete under `tests/`, `hooks/`, `.claude/hooks/` or a skill `scripts/`
directory, a change to the runner or the selector itself, and an unparseable
matrix all yield a `FULL` verdict and run everything. `--print-selection` shows
the trigger id (`F1`–`F7`).

Editing `tests/selection/matrix.tsv` requires a rationale on every row —
`tests/shell/meta/test-selection.bats` refuses a row without one, refuses a glob
that matches no tracked path, and refuses a `.bats` that no layer can reach.

**DV is capped.** A selection over 50% of the file count emits `WIDE`; if
`.context/state.json` shows the DV stage in progress the run exits **65** and
hands off to QA. Everyone else sees `WIDE` as informational.

Set `CORPFLOW_TEST_SELECT=0` to disable selection entirely.

## Environment & Dependencies

**Supported platforms:** macOS (bash 3.2), GNU/Linux (bash 4+). The Swift
packages need macOS 15+ (or a matching Swift 6 toolchain).

**Hard dependencies:**
- **`python3` >= 3.10** — NOT merely "Python 3". `skills/csv-export-templates/scripts/validate-export.sh`
  embeds a validator using PEP 604 `X | None` annotations evaluated at runtime, which raises a
  `TypeError` on 3.9. macOS ships 3.9.6 as `/usr/bin/python3`, so on a stock Mac the suite is red
  until a newer `python3` is first on `PATH` (`brew install python@3.12`, or any 3.10+). See Known
  Issue 8.
- `make`, `jq` (present on both platforms)
- `git` (for hook tests + fixture sourcing)

**Optional:**
- Swift 6 toolchain — the `benchmark/ttt-template` phase **skips cleanly** when `swift` is absent and
  `run-tests.sh` still exits 0, reporting `SKIPPED PHASES: 1`. Set `RUN_TESTS_REQUIRE_SWIFT=1` to make
  that skip a failure instead (opt-in; the default exit status is unchanged).

**Soft dependencies (auto-bootstrapped):**
- bats (vendored under `tests/vendor/`)
- kcov (brew → system → proxy)

**Clean-clone guarantee:** `make test` passes on a fresh checkout without manual install of
bats/kcov/pytest — **given `python3` >= 3.10 on `PATH`**. That prerequisite is real, not defensive
wording: under macOS system python3.9 the suite returns 1.

## Known Issues

Per QA findings (AC-3 resolution):

1. **kcov macOS bash 3.2** (DOCUMENTED PROXY) — kcov cannot instrument bash 3.2's `BASH_VERSINFO` guards; bash line coverage measured via assertion-density proxy (≥3 scenarios/script). Real line numbers obtainable on GNU/Linux host.

2. **`audit-tooluse.bats` environment coupling (P1, FIXED)** — Originally asserted `.effort == "max"` for absent-effort fixture, but script default is `"unknown"` (via `env.CLAUDE_EFFORT // "unknown"`). Test now pins `CLAUDE_EFFORT=off` and asserts `"unknown"` deterministically.

3. **`build-orchestrator.sh:146` false-cycle bug (FIXED)** — `blocks?` matched "Blocked by" (intended only for the `blocks:` dependency), adding a spurious reverse edge → false cycle (exit 5). Now `\bblocks?\b`; the test asserts the correct wave order and the absence of a reverse edge.

4. **`scan-secrets.sh` database-url regex broken (FIXED — see the disclosure in `CHANGELOG.md`)** — the ERE was corrupted by a greedy `${entry##*|}` last-pipe strip, so credentials in `mysql://` / `postgres://` / `mongodb://` URLs were **never** detected by the built-in scanner, on any grep dialect, for the whole life of the pattern. Now a two-step field strip; the test asserts all three schemes fire independently.

5. **`build-context-set.sh` BSD-sed `\s` issue (FIXED)** — the GNU-only `\s` escape mangled leading whitespace on BSD/macOS. All **7** affected sites now use `[[:space:]]`, and the tests assert one exact output on every sed dialect instead of branching on the host.

6. **AC-2 completeness gate command (non-portable, FIXED in runbook)** — Original `ls tests/ -R` fails on BSD/macOS (flag-after-operand). QA uses portable `ls -R tests/` variant + hyphen↔underscore normalization + vendored-file exclusion. All 43 shell targets covered.

7. **`make coverage` is unreachable on macOS (PRE-EXISTING, out of scope, filed)** — two independent blockers: the kcov branch runs away (measured: 352 MB of output in 90 s without completing), and behind it `benchmark/ttt-template` sits at 84.5 % against an 85 % gate. The binding green criterion is `./run-tests.sh` rc 0; `make coverage` has never been claimed green.

8. **`validate-export.sh` fails under Python < 3.10 (PRE-EXISTING, out of scope, filed)** — its embedded validator uses PEP 604 `X | None` annotations that are evaluated at runtime, raising `TypeError: unsupported operand type(s) for |: 'type' and 'NoneType'` on Python 3.9. Under stock macOS system `python3` (3.9.6) this reds 6 tests and `./run-tests.sh` returns 1. Proved pre-existing rather than assumed: the file is untouched by the hardening work, and HEAD's own `validate-export.bats` fails 4 of 6 under 3.9 while passing 6 of 6 under 3.14. **This is why the clean-clone guarantee below names `python3 >= 3.10`.**

Refer to `tests/COVERAGE.md#ac-3-resolution` for full coverage details.

## References

- `planning-0.md` — original exhaustive coverage & dual-path benchmark scope
- `analyzing-0.md` — architecture & 5-track DV partition design
- `tests/COVERAGE.md` — per-file coverage report + proxy exemptions
- `Makefile` — `bootstrap`, `test`, `coverage` targets
- `run-tests.sh` — deterministic suite entrypoint
