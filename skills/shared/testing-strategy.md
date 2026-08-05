---
name: testing-strategy
description: Cross-platform testing reference — testing pyramid, AAA pattern, per-platform framework and naming map, DV/QA boundary, and the Test Selection Gate. Reference when planning or implementing tests on any platform (apple, android, web, systems, backend, ai).
effort: low
version: 0.2.0
---

# Testing Strategy

Canonical testing reference for **every** platform a worktask routes to. The pyramid, AAA
pattern, DV/QA boundary, and Test Selection Gate below are platform-neutral and apply
everywhere. Framework and syntax specifics are gated per platform in § Framework by platform —
an Apple rule never applies off Apple, and vice versa. Platform→plugin routing is canonical in
`skills/shared/platform-detection.md`.

## Testing Pyramid

| Layer | Coverage | Scope | When |
|-------|----------|-------|------|
| Unit (70%) | Fast, isolated, deterministic | Single logic unit, mocked dependencies | Every commit |
| Integration (20%) | Component interactions | DB/API integration, service-to-service | PR and merge |
| E2E (10%) | Critical user journeys | Real browser/device | Before release |

## Framework by platform

Use the **project's established framework**. Detect it before writing a single test — test
directory layout, manifest dependencies, CI config. Never introduce a second framework into a
repo that already has one; when a repo has none, pick from the matrix below and record the
choice in `<plan_file> § Test Strategy`.

### Framework matrix — app platforms

| Platform | Unit | Integration | UI / E2E |
|----------|------|-------------|----------|
| `apple` | Swift Testing (`@Suite`/`@Test`/`#expect`) | Swift Testing + in-memory doubles | XCTest / XCUITest |
| `android` | JUnit 5 + MockK, Turbine for flows | JUnit + Robolectric, in-memory Room | Espresso / Compose UI test, Roborazzi screenshots |
| `web` | Vitest or Jest | Testing Library + MSW | Playwright (or Cypress) |

### Framework matrix — systems, backend, ai

| Platform | Unit | Integration | UI / E2E |
|----------|------|-------------|----------|
| `systems` | GoogleTest / Catch2 (C++), Unity / CMocka (C), pytest (Python), bats (Bash) | `ctest` targets driving real I/O | No UI layer — CLI transcripts are the evidence |
| `backend` | Stack-native: Go `testing`+testify, JUnit 5, Vitest/Jest, pytest | Testcontainers for DB/broker/cache | Contract tests (Pact/OpenAPI), k6 for load |
| `ai` | pytest for pipeline and tooling code | pytest + recorded fixtures / VCR | Eval harness (promptfoo, DeepEval, in-repo runner) with scored thresholds |

### Framework detail and test generation

Deeper per-framework guidance lives in the platform plugin, not here. Every registered dev
plugin exposes the same two entry points (`skills/shared/compatible-plugins.md`):

| Need | Command |
|------|---------|
| Generate tests in the project's framework | `/<plugin>:gen-tests` |
| Build and run the suite | `/<plugin>:build-test` |

Prefer delegating execution to `/<plugin>:build-test` over hand-rolling a runner invocation —
it already knows the repo's build system, and its output is the Build Evidence QA reads.

## Framework examples

One minimal example per UI platform. Systems, backend, and AI/ML use the same shapes in their
stack-native framework — see the matrix above and the plugin's `gen-tests` command.

### Apple — Swift Testing (unit)

On Apple platforms, unit tests use Swift Testing; XCTest is reserved for UI tests.

```swift
import Testing

@Suite("Feature Tests")
struct FeatureTests {
    @Test("happy path returns expected result")
    func happyPath() {
        #expect(feature.execute() == .success)
    }

    @Test("error cases throw appropriate error")
    func errorCase() {
        #expect(throws: FeatureError.self) {
            try feature.executeWithInvalidInput()
        }
    }

    @Test("parameterized test", arguments: [
        ("input1", "expected1"),
        ("input2", "expected2"),
    ])
    func parameterized(input: String, expected: String) {
        #expect(feature.transform(input) == expected)
    }
}
```

### Apple — MainActor-isolated suites

```swift
@Suite("ViewModel Tests")
@MainActor
struct ViewModelTests {
    let sut = ViewModel()

    @Test("state updates on action")
    func stateUpdates() {
        sut.performAction()
        #expect(sut.state == .updated)
    }
}
```

### Apple — XCTest (UI tests only)

XCUITest requires XCTest; this is the one place `test`-prefixed method names are mandatory.

```swift
import XCTest

final class FlowUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launch()
    }

    func testLoginFlow() {
        // XCUITest code
    }
}
```

### Android — JUnit 5 + MockK

```kotlin
class SessionStoreTest {
    private val repository = mockk<SessionRepository>()

    @Test
    fun `login with valid credentials returns session`() = runTest {
        coEvery { repository.authenticate(any()) } returns Session.valid

        val result = SessionStore(repository).login(Credentials.valid)

        assertEquals(SessionState.Active, result)
    }
}
```

### Web — Vitest + Testing Library

```ts
describe('SessionStore', () => {
  it('returns a session for valid credentials', async () => {
    const repository = { authenticate: vi.fn().mockResolvedValue(validSession) }

    const result = await new SessionStore(repository).login(validCredentials)

    expect(result.state).toBe('active')
  })
})
```

## AAA Pattern

Every test, in every framework, has three phases: **Arrange** the inputs and doubles, **Act**
once on the unit under test, **Assert** on the observable result. One logical act per test —
a test that acts twice is two tests. Blank lines (or explicit `// Arrange` / `// Act` /
`// Assert` comments in longer tests) keep the phases legible.

### AAA example — Swift

```swift
@Test("login with valid credentials succeeds")
func loginValid() {
    // Arrange
    let credentials = Credentials.valid

    // Act
    let result = authService.login(credentials)

    // Assert
    #expect(result == .success)
}
```

### AAA example — pytest

```python
def test_login_valid_credentials_returns_session():
    # Arrange
    credentials = Credentials.valid()

    # Act
    result = auth_service.login(credentials)

    # Assert
    assert result.state == "active"
```

## Test naming conventions

The **runner's collection rule wins** — it is not a style choice. Where the runner is agnostic,
prefer a descriptive sentence naming behavior and expected outcome, not the method called.

### Naming by framework

| Framework | Convention | Example |
|-----------|------------|---------|
| Swift Testing | Descriptive func name, **no** `test_` prefix; prose title in `@Test("…")` | `loginValidCredentialsReturnsSession()` |
| XCTest / XCUITest | `test` prefix **required** by the runner | `testLoginFlow()` |
| JUnit 5 (Kotlin/Java) | Backtick sentence (Kotlin) or camelCase + `@DisplayName` | `` `login with valid credentials returns session`() `` |
| Vitest / Jest | `describe` + `it` sentences | `it('returns a session for valid credentials')` |
| pytest | `test_` prefix **required** for collection | `test_login_valid_credentials_returns_session` |
| Go | Exported `Test<Thing>` **required** | `TestLoginValidCredentials` |
| Rust | snake_case `#[test] fn` inside `mod tests` | `fn login_valid_credentials()` |
| bats | `@test "<sentence>"` | `@test "login with valid credentials"` |

## Mutation Testing

A mutation test proves a guard is non-vacuous by breaking what it guards and requiring the guard
to fail. Its result carries no information unless the mutation actually landed.

**Assert the mutation was applied before trusting the pass/fail it produced.** Back the target up,
mutate, byte-compare against the backup (`diff -q` must report the files differ), and only then run
the test; restore afterwards. A mutation that silently no-ops — a `sed` pattern written for
`echo "…"` against a source that uses `printf '…'`, a line number that shifted — yields a passing
test indistinguishable from a weak guard, so the reviewer concludes the opposite of what the
evidence shows.

## Portable verification greps

A canon-sweep or acceptance-criteria count is evidence only if the command means the same thing on
every host: `grep` may resolve to GNU grep, BSD grep or `ugrep`, which differ in ways that change a
count silently instead of erroring.

- Put `--include=`/`--exclude-dir=` **before** the pattern, and use `-e` for any pattern containing
  `--` — past a `--` terminator ugrep stops parsing options and reads the filter as a filename.
- Never anchor an exclusion regex on a `./` prefix; ugrep omits it, so `^\./…` filters match
  nothing and the exclusion silently does not apply.
- Report the per-file decomposition, not only the total — a filter that stopped applying looks
  identical to one that found nothing to exclude.

## DV vs QA Boundary

DV produces the **build artifact + selected-test list**. QA executes the **selected tests** plus visual checks if gated on. This division keeps the DV iteration loop fast (build-only by default) while preserving regression coverage at QA.

| DV Stage (Developer) | QA Stage (QA Engineer) |
|----------------------|------------------------|
| Unit tests per `<plan_file>` specs | Additional edge case tests |
| Mock implementations for dependencies | Coverage gap analysis |
| Happy path + known error cases | Boundary and stress tests |
| Test data builders/fixtures | Test quality review |
| **Build verification + parse markers + emit Selected Tests** | **Run only the Selected Tests list** (plus full suite if `test_mode=full`) |

## Test-Execution Authority

Canonical, single-sourced statement of **who** may execute tests — orthogonal to `test_mode`
(§ Test Selection Gate), which governs **how much** runs. Every agent file and skill points here;
none restates the matrix or the runner list below.

Authority is a property of the **stage**, never of the agent file: a support agent (`designer`,
`ethics-reviewer`, `prompt-engineer`, `workflow-engineer`) inherits the authority of whichever
stage it is dispatched into — `workflow-engineer` acting as DV0 for plugin-infrastructure scope
holds DV's authority, not a fixed authority of its own.

### Definitions

**Test execution** — invoking a runner that evaluates test cases: `bats`, `swift test`, `pytest`,
`python3 -m unittest`, `ctest`, `go test`, `cargo test`, `jest`, `vitest`, `playwright`, `rspec`,
`dotnet test`, `gradle test` / `./gradlew test`, `npm`/`pnpm`/`yarn test`, `xcodebuild test`,
`mcp__*__test_*`; plus `./run-tests.sh`, `make test`, `make coverage`, `make test-ios` in this
repo; plus `/<plugin>:build-test` invoked *without* `--no-test`; plus delegating any of the above
to another agent.

**Build-only verification** — compile, link, type-check, lint, static analysis, and test
*collection without execution* (`bats --count`, `pytest --collect-only`, `--dry-run`). **Allowed
at every one of the 13 stages, always** — `/<plugin>:build-test --no-test` is the sanctioned
delegated form. The allowance is only *reachable* where the stage holds a build path (see
"Reachable how" below); nominal for stages with no test-capable Bash grant.

### Optional stages and authority

Rows describe a stage's authority *when that stage runs*. AR and TL are optional (`skills/estimation-methodology/SKILL.md § Stage Inclusion Criteria`); an excluded stage grants its authority to no one — in particular, an excluded AR does not transfer test-architecture authority to DV beyond the design ownership rule in `agents/developer.md § Architecture Ownership`.

### Authority matrix — DV, QA, AR, DR

| Stage | Build-only | Reachable how | Scoped exec | Full exec | Note |
|---|---|---|---|---|---|
| DV | allowed | own Bash | **required** | **forbidden** | full-suite deny is mechanical for the bare-runner form only (`hooks/test-execution-gate.sh`) — a trailing flag or argument (`swift test --parallel`, `pytest -v`) classifies scoped and is allowed; only a bare runner with nothing after it (`swift test`) is caught |
| QA | allowed | own Bash | allowed | **allowed — sole holder** | |
| AR | allowed | delegation only (no Bash grant) | forbidden | forbidden | |
| DR | allowed | `/<plugin>:build-test --no-test` | forbidden | forbidden | compile-check carve-out preserved verbatim (`agents/technical-lead.md`) |

### Authority matrix — SR, RE, IR

| Stage | Build-only | Reachable how | Scoped exec | Full exec | Note |
|---|---|---|---|---|---|
| SR | allowed | narrowed Bash, read-only introspection (git/jq/cat/head/tail) | forbidden | forbidden | no `Skill` tool → `build-test --no-test` is nominal, not reachable; scan capability is delegation-dependent (§ Mechanical enforcement) |
| RE | allowed | narrowed Bash, read-only introspection (git/jq/cat/head/tail) | forbidden | forbidden | same `Skill`-tool gap as SR — build-only is nominal, not reachable |
| IR | allowed | broad Bash (documented carve-out) | forbidden | forbidden | incident reproduction is not test execution (§ Escalation path) |

### Authority matrix — everyone else

| Stage | Build-only | Reachable how | Scoped exec | Full exec | Note |
|---|---|---|---|---|---|
| PL, TL, DC, FN, ST | allowed | delegation only (no test-capable Bash) | forbidden | forbidden | nominal allowance |
| Support (`designer`, `ethics-reviewer`, `prompt-engineer`, `workflow-engineer`) | allowed | per agent | inherits dispatched stage | inherits dispatched stage | authority follows the stage being acted for, not the agent name |

### Auto-promotion note

**DV's no-handler auto-promotion never widens to `full`.** See `test-selection-syntax.md §
Auto-promotion when no handler` — the cap is `module-scope`, an execution-only value recorded in
`development-N.md § Decisions`, never a `test_mode` value (that vocabulary stays exactly
`build-only | scoped | full`, unchanged and PL0-owned).

### Escalation path

A banned stage that believes runtime evidence is needed never self-serves. Ordered:

1. **Non-blocking need** — record `requests_test_evidence: <what and why>` in the stage's own
   artifact (`§ Findings` / `§ Notes`). QA ingests these the same way it ingests its own additions
   (`agents/qa-engineer.md § Q1 QA Additions`) and executes them.
2. **Blocking need** — the stage returns `verdict: blocked` with `error_escalated_to: "DV"`. The
   orchestrator re-opens DV through the existing error-handling loop
   (`skills/agent-coordination/SKILL.md § Error Handling`). No new machinery.
3. **Incident reproduction is not test execution** — running the app, a repro script, or hitting a
   failing endpoint is allowed for IR; its fix verification still routes through the emergency
   pipeline's own DV and QA stages.
4. **Compile-only checks are unaffected** — `/<plugin>:build-test --no-test` stays available to
   every stage regardless of authority.

### Mechanical enforcement

Three layers, cheapest first — see `skills/worktask/SKILL.md` step 4.8b and
`hooks/test-execution-gate.sh` for implementation:

- **Tool-grant narrowing** — `security-reviewer` and `release-engineer` drop bare `Bash` for
  scoped allow-lists, matching the `technical-lead`/`project-manager` idiom. `incident-responder`,
  `prompt-engineer`, and `workflow-engineer` keep broad Bash — documented carve-outs.
- **Orchestrator step 4.8b** — a NO-TEST-EXECUTION banner + `stage_test_ban_enforced` audit row
  injected into the composed prompt for every dispatched stage not in `{DV, QA}`.

### The `PreToolUse` hook layer

**`hooks/test-execution-gate.sh`** — a `PreToolUse` hook, fail-open on every ambiguity, that
resolves the acting stage from `.context/state.json` (never agent/payload identity) and denies
test-runner invocations outside `{DV, QA}` (and DV full-suite runs). Exit code is always 0; the
decision travels in the JSON `hookSpecificOutput.permissionDecision`. This is the only layer that
covers delegated calls and the orchestrator's own shell.

### SR/RE control layering

**For SR and RE specifically, the hook is not a backstop behind the grant narrowing — it is the
only control.** Both stages' platform-auditor delegates (e.g.
`Task(system-developer:sys-security-auditor)`) hold test-capable Bash grants of their own
(`ctest`, `make`, …) that are unaffected by narrowing SR's/RE's own grant. The hook denies the
delegate's leaf call via the same state.json stage resolution, which is why the design is correct
— but it means a regression in stage resolution is a complete loss of enforcement for SR/RE, not a
degradation of a defense-in-depth layer.

### Escape-hatch honesty

`COMPANY_WORKFLOW_TEST_GATE=off` and `CLAUDE_PROJECT_DIR` (pointed at a directory
with no `.context/state.json`) are both **agent-writable across sessions**, not agent-proof:
`.claude/settings.json` `env` can be written by any stage holding `Write`/`Edit`, and takes effect
on the next session or resume. Within a single live session neither is reachable from inside a
command string — the hook reads process env, not payload text — which is what makes the hatch
usable as a human relief valve without being agent-serviceable mid-retry. Across sessions it is a
human-intent-scoped control, not a hard boundary; layers 1 (grants) and 2 (the 4.8b banner) do not
share this property. The hook logs a `test_gate_disabled` audit row the first time either vector is
observed disabled per `.context/`, so the disable is reviewable rather than silent.

## Test Selection Gate

Tests are slow (especially UI/simulator bundles). The gate decides — per worktask run — **how much of the test pyramid runs and where**. Defaults are tightened so backend, refactor, and doc-only tasks do not pay simulator-startup cost.

### Three test modes

| Mode | DV behaviour | QA behaviour | When PL sets it |
|------|--------------|--------------|-----------------|
| `build-only` | Build + run **smoke set only** (`@test-required` ∪ `metadata.always_required_tests`). Parse `@depends-on:` markers. Emit Selected Tests list for QA. | Run **only Selected Tests** (always-required ∪ dependency-matched). Visual comparison gated on `ui_visual_check`. | Repos that have completed marker migration. Refactors, dep updates, doc-only changes. **Opt-in** via explicit `test_mode: build-only` in plan. |

#### `scoped` and `full` modes

| Mode | DV behaviour | QA behaviour | When PL sets it |
|------|--------------|--------------|-----------------|
| `scoped` (effective default) | Build + run Selected Tests + tests in any module the diff touches. | Selected Tests + module-level tests + any QA-added edge-case tests. Visual comparison gated on `ui_visual_check`. | Bug fixes, small features. Default for plans that omit `test_mode` (avoids silent coverage blackout on untagged repos). |
| `full` | Build + run Selected Tests at DV. | **Full project test suite** as regression gate. Visual comparison gated on `ui_visual_check`. | Release candidates, multi-module features, post-major-dep-upgrade. |

#### Effective default

When `<plan_file>` omits `metadata.test_mode`, agents resolve to `scoped` (not `build-only`). This preserves today's "DV runs scoped tests, QA runs the unit+integration suite" semantics for untagged repositories. To unlock `build-only` speedup, a plan must opt in by writing `test_mode: build-only` explicitly **and** the repo should have meaningful marker coverage (parser logs a warning if `< 50%` of test files lack any marker).

#### Auto-promotion safety nets

DV/QA enforce these even if PL set a tighter mode:
- Selected Tests list is empty AND `test_mode = build-only` → DV warns and runs the smoke set; QA promotes to `scoped` with a logged note in `testing-N.md § Notes`.
- Platform has no wired marker-parser handler (every platform except Apple today — see `test-selection-syntax.md § Identifier grammar by platform`) AND `test_mode ∈ {build-only, scoped}` → DV auto-promotes to **module-scope** (never `full` — see `§ Test-Execution Authority`) for that platform with a logged warning. The mode stays as the PL-declared value in metadata; the promotion is recorded in `development-N.md § Decisions` with `auto_promoted_mode: module-scope`. If module scope cannot be computed, DV runs the smoke set instead and records `deferred_to_qa: full_regression` — it does not widen further.

### Contract

- **Flag**: `metadata.test_mode: build-only | scoped | full` in `<plan_file>` frontmatter.
- **Effective default when absent**: `scoped` (see *Effective default* note above). `build-only` is opt-in.
- **Companion flags**:
  - `metadata.always_required_tests: [<test ID>...]` — explicit override, included in every Selected Tests list regardless of mode.
  - `metadata.ui_visual_check: <bool>` — default `false`. When `true` AND `.context/designs/` exists, QA performs Design Comparison. Independent of `test_mode`.
- **Writer**: PL stage (`agents/product-manager.md` § Test Strategy Definition).

#### Readers

- DV step D2 (`agents/developer.md`) — parses markers, computes Selected Tests, runs only when `test_mode ∈ {scoped, full}`.
- QA step Q1 (`agents/qa-engineer.md`) — three-mode dispatcher.
- QA Design Comparison (`agents/qa-engineer.md` § Design Comparison) — gated on `ui_visual_check=true` (NOT `test_mode`).

#### DR test-execution exclusion

- **DR** (`agents/technical-lead.md`) does not run tests; the gate does not apply. Authority is
  canonical in `§ Test-Execution Authority` above — not restated here. If DR thinks runtime
  verification is needed, it records `requests_test_evidence:` for QA — it never executes.

### DV Executed vs Selected (scope split)

DV's `Selected Tests` is the **handoff artifact** consumed by QA; DV's `Executed Tests (DV)` is the **subset DV actually runs**.

- **Selected Tests** = full algorithm output (smoke ∪ dependency-matched ∪ covers-changed-files ∪ module-level ∪ `metadata.always_required_tests`). Always written to `development-N.md § Selected Tests`. QA executes this list.
- **Executed Tests (DV)** = (Selected ∩ test files Added/Modified in `git diff --diff-filter=AMR <base>...HEAD`) ∪ `metadata.always_required_tests`. Only this subset runs at DV.

#### Empty-set safety net and rationale

- **Empty-set safety net**: if Executed Tests (DV) is empty AND Selected Tests is non-empty (production changed without touching tests), DV runs only the smoke set and records `auto_executed: smoke_set` in `§ Decisions`. QA still executes the full Selected list.
- **Rationale**: DV's job is to verify the code+tests it just wrote/modified compile and pass. Broader regression (dep-matched, covers, module-level) belongs to QA so DV stays fast and QA owns the regression gate. See `agents/developer.md § D2` for the canonical derivation.

### When to choose each mode

`build-only` (opt-in — requires marker coverage; see Effective default note above):
- Refactor without behavior change
- Doc-only updates
- Backend changes with full test markers maintained (rely on `@depends-on:` graph)
- Internal-tool / dev-only changes

`scoped`:
- Bug fix touching a known set of modules
- Feature work that doesn't span subsystems
- Diff touches files with weak `@depends-on:` coverage (defensive — runs more)

`full`:
- Release candidate (RE stage prep)
- Multi-module feature (e.g., new auth flow touching networking + UI + persistence)
- Stakeholder requested full regression
- First run after a major dependency upgrade

### `ui_visual_check`

Set to `true` when at least one applies:
- New user-facing views or screens (SwiftUI/UIKit, Compose, React/Vue/Svelte/Angular components)
- Visual design artifacts in `.context/designs/` need verification
- Layout/styling/animation changes require screen capture
- Stakeholder requests UI verification

`ui_visual_check` is independent of `test_mode` — a `build-only` plan can still set `ui_visual_check: true` if the diff is purely visual (rare but legal).

### Selected Tests — production by DV

DV's D2 step parses test sources for the markers documented in `skills/shared/test-selection-syntax.md` and produces:

```markdown
## Selected Tests

| Mode | build-only |
| Reason | metadata.test_mode default |

### Always Required
- AppLaunchTests.testLaunchSucceeds — `@test-required`
- AuthSmokeTests.testLoginRoundtrip — `metadata.always_required_tests`

### Dependency-Matched
| Test | Matched on | Source |
| ---- | ---------- | ------ |
| PaymentRefundTests.testRefundFlow | `PaymentService` (changed in `PaymentService.swift:42`) | `// @depends-on: PaymentService` at `PaymentRefundTests.swift:8` |

### Excluded (with reason)
| Test | Reason |
| ---- | ------ |
| OrderHistoryTests.testListRender | No marker matches diff; `test_mode != full` |
```

QA reads this section verbatim. If QA adds new tests during QA-stage edge-case review, it appends them to a `## Selected Tests (QA additions)` section in `testing-N.md`.

### Design↔result image comparison (wired flow)

When the Design Comparison gate is open (`ui_visual_check: true` AND `.context/designs/`
artifacts present), QA's **primary** comparison reuses the DV-captured result images and
runs an objective RMSE pixel-diff pre-pass before multimodal vision — it no longer always
re-captures a fresh live screenshot. The canonical per-row algorithm, the verdict
reconciliation matrix, and the reporting `RMSE` column all live in
`agents/qa-engineer.md § Design Comparison` (not duplicated here).

#### Join key (Option A)

DV's `.context/images/<worktask_id>/screenshots.md` manifest
carries an optional trailing `Design Ref` column populated with the matching
`figma-registry.md` row `ID` (see `skills/dv-screenshot-capture/SKILL.md § Registry
tagging`). QA joins `screenshots.md.Design Ref → figma-registry.md.ID` by ID equality;
the mapped DV image is both the RMSE `--candidate` (`scripts/visual-diff.sh`) and the
vision input. Live re-capture is the fallback only — used when no DV image maps.

#### Verdict reconciliation (by reference)

RMSE is a **one-way escalator** — it may raise
severity, never lower it (RMSE is blind to copy/semantic errors). The full 6-row matrix is
in `agents/qa-engineer.md § Verdict reconciliation`.

#### Degradation invariants (by reference)

The design↔result reuse is strictly additive; the full invariant list (gate unchanged, absent DV
images → live-capture, `magick` absent → vision-only non-blocking, no registry → Glob Discovery,
manifest without a `Design Ref` column) is canonical in
`skills/worktask/references/visual-qa.md § Degradation invariants`.

### Skip mechanics — positive selection everywhere

Every platform translates the Selected Tests list into **positive** include flags, never negative
excludes: an exclude list silently grows stale as tests are added, an include list fails loudly.
The per-platform flag syntax and identifier grammar are tabulated in
`test-selection-syntax.md § Platform handlers`; the two sections below cover the mechanics that
differ enough to matter.

### Skip mechanics — Apple platforms

When DV/QA runs Selected Tests via XcodeBuildMCP, the list is translated to positive `-only-testing:` arguments (one per owning suite, deduplicated), not negative `-skip-testing:`:

```bash
# Selected Tests = [PaymentRefundTests.testRefundFlow, AppLaunchTests.testLaunchSucceeds]
# → flags collapse to the owning suite (suite-terminal); never per-function
xcodebuild test \
  -project MyApp.xcodeproj \
  -scheme MyApp \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:MyAppTests/PaymentRefundTests \
  -only-testing:MyAppTests/AppLaunchTests
```

#### Skip mechanics — granularity, full mode, recording

Identifiers are **suite-terminal** (`<Target>/<Suite>`) per `test-selection-syntax.md § Apple
identifier grammar — suite-terminal`. A per-function segment selects nothing under Swift Testing.

When `test_mode=full`, the entire suite runs without `-only-testing:`. UI test bundles run unless explicitly excluded (no implicit `-skip-testing:` — UI tests run because `ui_visual_check` or `test_mode=full` opted into them).

### Skip mechanics — other platforms

Same rule, different flag. Drop the filter entirely for `test_mode=full`; the full suite is the
regression gate. Prefer `/<plugin>:build-test`, which applies the correct form for the repo.

| Platform / runner | Include flag |
|-------------------|--------------|
| Android (Gradle + JUnit) | `./gradlew test --tests 'com.app.SessionStoreTest'` (repeatable) |
| Web (Vitest / Jest) | `vitest run <path>` + `-t '<name pattern>'`; `jest <path> -t '<pattern>'` |
| Web E2E (Playwright) | `npx playwright test <file>` + `-g '<title pattern>'` |
| Python (pytest) | `pytest tests/test_session.py::test_login` (nodeid) or `-k '<expr>'` |
| Go | `go test ./pkg/session -run '^TestLogin'` |
| Rust | `cargo test session::login` (substring match on the test path) |
| C/C++ (CTest / GoogleTest) | `ctest -R '<regex>'`; `./suite --gtest_filter='SessionStore.*'` |
| Bash (bats) | `bats tests/session.bats -f '<name regex>'` |

### Recording the resolved selection

DV records `test_mode`, `selected_tests_count`, and `ui_visual_check` in `.context/development-N.md § Decisions`. QA records the resolved mode and any `Selected Tests (QA additions)` in `testing-N.md § Notes`. This applies on every platform, including runs auto-promoted to `module-scope` (§ Test-Execution Authority).

### Marker grammar reference

See `skills/shared/test-selection-syntax.md` for the full marker grammar (`@test-required`, `@depends-on:`, `@test-tag:`), parser pseudocode, and Swift Testing trait equivalents.

### Footer markers (bidirectional traceability)

Source files carry a `Test Info` footer block with `@test-file:` (primary test path), `@related-tests:` (cross-dependency tests), and `@test-coverage:` (description). Test files carry a `Source Info` footer with `@source-file:` (source path) and `@doc-refs:` (documentation links). The sentinel words are fixed; the comment decoration around them is language-native (`// MARK: -` on Swift, `# region` on Python, a plain banner elsewhere). These are advisory — they do not affect test selection — but enable reviewers and tooling to verify coverage intent bidirectionally. See `test-selection-syntax.md § Footer Markers` for grammar, platform variants, and examples.
