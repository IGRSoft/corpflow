# Plugin Test Suite

Exhaustive unit tests for all deterministic plugin scripts and hooks with measured line coverage (kcov for bash, coverage.py for Python).

## Quick Start

Run the full deterministic suite:
```bash
make test              # All tests, offline, bootstrap as needed
make coverage          # Plus kcov/coverage.py reporting (≥85% target per file)
make bootstrap         # Vendors bats, provisions kcov/coverage.py (idempotent)
```

No system `bats`, `pytest`, or `kcov` required — `make bootstrap` auto-provisions via:
- **bats**: vendored under `tests/vendor/bats-core/` (v1.11.0 + support/assert)
- **kcov**: system probe → brew → documented per-file proxy (macOS bash 3.2)
- **coverage.py**: python3 -m pip → vendored-wheel fallback

## Organization

```
tests/
  shell/
    hooks/             # 9 bats files: agent-stop, anchor-preflight, audit-dedup, …
    worktask/          # 9 bats files: state-patch, publish-pl-issue, cache-lint, …
    dv-screenshot/     # 4 bats files: apple-canvas, cli-fallback, size-budget, visual-diff
    skills/            # 11 bats files: build-orchestrator, scan-secrets, build-context-set, …
  python/
    test_estimate_calc.py       # 94% line coverage (in-process CLI + subprocess)
    test_layout_calc.py         # 92% line coverage (in-process CLI + subprocess)
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

## Test Coverage

**Verdict: AC-3 MET** (Python measured, bash via assertion-density proxy).

### Python (measured via coverage.py)

| Module | Coverage |
|--------|----------|
| `skills/estimation-methodology/scripts/estimate-calc.py` | **94%** |
| `skills/appstore-screenshots/scripts/layout-calc.py` | **92%** |

Both exceed the ≥85% gate. Coverage measured via in-process CLI tests (not subprocess-only, which undercounted at ~23–32%). Run via:
```bash
python3 -m coverage run -m unittest discover -s tests/python && coverage report
```

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
tests/shell/skills/agent-coordination__audit-dedup.bats    # skills/agent-coordination/references/audit-dedup.sh
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

**Supported platforms:** macOS (bash 3.2), GNU/Linux (bash 4+).

**Hard dependencies:**
- Python 3.7+
- `make`, `jq` (present in both platforms)
- `git` (for hook tests + fixture sourcing)

**Soft dependencies (auto-bootstrapped):**
- bats (vendored under `tests/vendor/`)
- kcov (brew → system → proxy)
- coverage.py (pip → vendored wheel)

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
