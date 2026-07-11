# Plugin Test Suite

Exhaustive unit tests for all deterministic plugin scripts and hooks: bats for
bash, **Swift Testing** for the three Swift packages (TTT fixture, benchmark
harness, PluginScriptsTests) — with kcov (bash) + `swift test
--enable-code-coverage` (Swift) line-coverage gating.

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
    hooks/             # 9 bats files: agent-stop, anchor-preflight, audit-dedup, …
    worktask/          # 9 bats files: state-patch, publish-pl-issue, cache-lint, …
    dv-screenshot/     # 4 bats files: apple-canvas, cli-fallback, size-budget, visual-diff
    skills/            # 11 bats files: build-orchestrator, scan-secrets, build-context-set, …
  swift/               # SwiftPM package "PluginScriptsTests"
    Sources/PluginScripts/          # subprocess + JSON helpers
    Tests/PluginScriptsTests/
      EstimateCalcTests.swift       # 21 behaviors (estimate-calc.py via python3)
      LayoutCalcTests.swift         # 17 behaviors (layout-calc.py via python3)
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
    README.md          # Fixture collision-safety index (audit-dedup.sh path-keyed names)
  COVERAGE.md          # Per-file coverage report + proxy exemptions (AC-3 gate)
```

The two other Swift suites live with their packages:
`benchmark/ttt-template/Tests/TicTacToeKitTests` (48 fixture tests) and
`benchmark/harness/Tests/{BenchmarkKitTests,BenchmarkLiveTests}` (140 harness
tests, zero LLM calls). `make test` runs all three via `run-tests.sh`.

## Test Coverage

**Verdict: AC-3 MET** (Swift measured via llvm-cov, bash via assertion-density proxy).

### Skill scripts (behavioral parity via tests/swift)

The plugin's skill runtime scripts STAY Python and are exercised by
`tests/swift` PluginScriptsTests — 38 Swift Testing behaviors shelling
`python3` at the unchanged scripts:

| Script | Behaviors |
|--------|-----------|
| `skills/estimation-methodology/scripts/estimate-calc.py` | **21** (band boundaries, ai_cost arithmetic, hours, CLI shape, self-test) |
| `skills/appstore-screenshots/scripts/layout-calc.py` | **17** (proportional geometry, full-bleed, errors, CLI shape, self-test) |

The retired in-process coverage.py measurement (94%/92%) went away with the
Python test suite; the scripts themselves are unchanged and their documented
contracts are pinned 1:1 by the subprocess behaviors above plus each script's
built-in `--self-test`.

### Swift packages (measured via swift test --enable-code-coverage)

`make coverage` runs each package with coverage enabled and gates aggregate
line coverage at **≥85%** via jq over the llvm-cov export JSON.
`Sources/TicTacToeKit/Views/` is excluded from the denominator (SwiftUI view
bodies are exercised structurally, not unit-covered — see
`tests/COVERAGE.md`).

### Bash (via assertion-density proxy)

kcov **cannot run on macOS bash 3.2** (mis-parses `BASH_VERSINFO` guards; >2 min/file). Per the locked q3 resolution, coverage is validated via the **q3 assertion-density proxy**: every shell script has a dedicated test file with ≥3 real scenarios (happy / edge / failure-exit), asserting its documented contracts.

- **35/35** total deterministic targets covered (9 hooks + 24 skill shell + 2 Python)
- **33 bats files** covering 33 shell scripts/hooks
- **~198 `@test`** assertions across the suite
- **Min 3 / avg ~6 / max 14** scenarios per file

High-logic-density targets (14+ scenarios):
- `scan-secrets` (14) — exit code, pattern format, real vs synthetic secrets
- `post-compact-recovery`, `milestone-helpers`, `map-and-filter`, `agent-coordination__audit-dedup` (9 each)
- `state-patch`, `build-orchestrator`, `changelog-from-git` (8 each)

**Real bash line coverage** is obtainable on a **GNU/Linux host** (bash ≥4 + kcov). The `make coverage` kcov stem sed bug was fixed; on Linux it now works end-to-end.

### Swift (measured, per package)

- `benchmark/ttt-template` — 48 Swift Testing tests (engine, AI, models, router, view-model); the iOS slice runs via `make test-ios` (xcodebuild, iPhone simulator; SKIPs cleanly without a runtime)
- `benchmark/harness` — 140 tests incl. schema byte-compat against the real `history.json`, AC-8 package-graph, budget/credential/prompt-assembly gates (all dispatchers injected — zero LLM calls)
- `tests/swift` — 38 PluginScriptsTests behaviors

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

For the two `audit-dedup.sh` files (hook vs skill), use full paths:
```
tests/shell/hooks/audit-dedup.bats                          # hooks/audit-dedup.sh
tests/shell/skills/agent-coordination__audit-dedup.bats    # skills/agent-coordination/scripts/audit-dedup.sh
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

## Environment & Dependencies

**Supported platforms:** macOS (bash 3.2), GNU/Linux (bash 4+). The Swift
packages need macOS 15+ (or a matching Swift 6 toolchain).

**Hard dependencies:**
- Swift 6 toolchain (`swift test` for the three packages)
- Python 3 (the skill runtime scripts stay Python; PluginScriptsTests shells to them)
- `make`, `jq` (present in both platforms)
- `git` (for hook tests + fixture sourcing)

**Soft dependencies (auto-bootstrapped):**
- bats (vendored under `tests/vendor/`)
- kcov (brew → system → proxy)

**Clean-clone guarantee:** `make test` passes on a fresh checkout without manual install of bats/kcov/pytest.

## Known Issues

Per QA findings (AC-3 resolution):

1. **kcov macOS bash 3.2** (DOCUMENTED PROXY) — kcov cannot instrument bash 3.2's `BASH_VERSINFO` guards; bash line coverage measured via assertion-density proxy (≥3 scenarios/script). Real line numbers obtainable on GNU/Linux host.

2. **`audit-tooluse.bats` environment coupling (P1, FIXED)** — Originally asserted `.effort == "max"` for absent-effort fixture, but script default is `"unknown"` (via `env.CLAUDE_EFFORT // "unknown"`). Test now pins `CLAUDE_EFFORT=off` and asserts `"unknown"` deterministically.

3. **`build-orchestrator.sh:146` false-cycle bug (KNOWN-BUG, report-not-fix)** — Regex `(?i)blocks?\s*:?` matches "Blocked by" (intended only for "blocks:" dependency), adding spurious reverse edge → false cycle (exit 5). Test faithfully asserts this as a known bug.

4. **`scan-secrets.sh` database-url regex broken (KNOWN-BUG, report-not-fix)** — ERE corrupted by `${entry##*|}` greedy last-pipe strip (pipes interior to regex cause invalid pattern). DB-URL secrets never fire. Test asserts non-firing.

5. **`build-context-set.sh:59` BSD-sed `\s` issue (KNOWN-BUG, macOS cross-platform)** — GNU-only `\s` whitespace escape mangles leading space on BSD/macOS → agent path missing → `set -e` pipeline exits 1. Test asserts both branches (GNU pass, BSD fail).

6. **AC-2 completeness gate command (non-portable, FIXED in runbook)** — Original `ls tests/ -R` fails on BSD/macOS (flag-after-operand). QA uses portable `ls -R tests/` variant + hyphen↔underscore normalization + vendored-file exclusion. All 35 targets covered.

Refer to `tests/COVERAGE.md#ac-3-resolution` for full coverage details.

## References

- `planning-0.md` — original exhaustive coverage & dual-path benchmark scope
- `analyzing-0.md` — architecture & 5-track DV partition design
- `tests/COVERAGE.md` — per-file coverage report + proxy exemptions
- `Makefile` — `bootstrap`, `test`, `coverage` targets
- `run-tests.sh` — deterministic suite entrypoint
