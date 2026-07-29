---
name: testing-strategy
description: Cross-platform testing reference — testing pyramid, AAA pattern, per-platform framework and naming map, DV/QA boundary, and the Test Selection Gate. Reference when planning or implementing tests on any platform (apple, android, web, systems, backend, ai).
effort: low
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

## DV vs QA Boundary

DV produces the **build artifact + selected-test list**. QA executes the **selected tests** plus visual checks if gated on. This division keeps the DV iteration loop fast (build-only by default) while preserving regression coverage at QA.

| DV Stage (Developer) | QA Stage (QA Engineer) |
|----------------------|------------------------|
| Unit tests per `<plan_file>` specs | Additional edge case tests |
| Mock implementations for dependencies | Coverage gap analysis |
| Happy path + known error cases | Boundary and stress tests |
| Test data builders/fixtures | Test quality review |
| **Build verification + parse markers + emit Selected Tests** | **Run only the Selected Tests list** (plus full suite if `test_mode=full`) |

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
- Platform has no wired marker-parser handler (every platform except Apple today — see `test-selection-syntax.md § Identifier grammar by platform`) AND `test_mode ∈ {build-only, scoped}` → DV auto-promotes to `full` for that platform with a logged warning. The mode stays as the PL-declared value in metadata; the promotion is recorded in `development-N.md § Decisions` with `auto_promoted_mode: full`.

### Contract

- **Flag**: `metadata.test_mode: build-only | scoped | full` in `<plan_file>` frontmatter.
- **Effective default when absent**: `scoped` (see *Effective default* note above). `build-only` is opt-in.
- **Companion flags**:
  - `metadata.always_required_tests: [<test ID>...]` — explicit override, included in every Selected Tests list regardless of mode.
  - `metadata.ui_visual_check: <bool>` — default `false`. When `true` AND `.context/designs/` exists, QA performs Design Comparison (was previously bundled into `requires_ui_tests`). Independent of `test_mode`.
- **Writer**: PL stage (`agents/product-manager.md` § Test Strategy Definition).

#### Readers

- DV step D2 (`agents/developer.md`) — parses markers, computes Selected Tests, runs only when `test_mode ∈ {scoped, full}`.
- QA step Q1 (`agents/qa-engineer.md`) — three-mode dispatcher.
- QA Design Comparison (`agents/qa-engineer.md` § Design Comparison) — gated on `ui_visual_check=true` (NOT `test_mode`).

#### DR test-execution exclusion

- **DR** (`agents/technical-lead.md`) does not run tests; the gate does not apply. DR's tool list and constraints explicitly forbid test execution — see `agents/technical-lead.md § Constraints` and § Bash Scope (DR) for the canonical forbidden-commands list (`xcodebuild test`, `swift test`, `xcrun simctl … test`, `npm/pnpm/yarn test`, `jest`, `vitest`, `pytest`, `go test`, `cargo test`, `rspec`, `mcp__XcodeBuildMCP__test_*`, `mcp__XcodeBuildMCP__swift_package_test`, `mcp__XcodeBuildMCP__build_run_*`). If DR thinks runtime verification is needed, it records a finding for QA — it never executes.

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

### `ui_visual_check` (was: `requires_ui_tests` for visual QA)

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

### Backward compatibility (deprecated `requires_ui_tests` flag)

Legacy `requires_ui_tests` (one-release-cycle compat alias; removed next minor release). When a `<plan_file>` has `requires_ui_tests` and no `test_mode`, map: `true` → `test_mode: full` + `ui_visual_check: true`; `false`/absent → `test_mode: scoped` + `ui_visual_check: false` (NOT `build-only` — that would silently drop QA unit-test execution on legacy plans). PL/DV/QA emit one deprecation note in their artifact `§ Notes` when it fires.

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

#### Backward-compat guarantees

The change is strictly additive:
- Top-level gate unchanged (`ui_visual_check: true` AND `.context/designs/` artifacts).
- `requires_screenshots: false` → no DV images → 100% live-capture fallback = today's output.
- `magick` absent → `visual-diff.sh` self-degrades (`skipped`/`imagemagick_not_found`, exit 0)
  → QA proceeds vision-only, non-blocking.
- No registry → existing Glob Discovery fallback untouched, vision-only.
- Old manifest lacking the `Design Ref` column parses fine (missing ≡ `—` → live-capture).

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

DV records `test_mode`, `selected_tests_count`, and `ui_visual_check` in `.context/development-N.md § Decisions`. QA records the resolved mode and any `Selected Tests (QA additions)` in `testing-N.md § Notes`. This applies on every platform, including runs auto-promoted to `full`.

### Marker grammar reference

See `skills/shared/test-selection-syntax.md` for the full marker grammar (`@test-required`, `@depends-on:`, `@test-tag:`), parser pseudocode, and Swift Testing trait equivalents.

### Footer markers (bidirectional traceability)

Source files carry a `Test Info` footer block with `@test-file:` (primary test path), `@related-tests:` (cross-dependency tests), and `@test-coverage:` (description). Test files carry a `Source Info` footer with `@source-file:` (source path) and `@doc-refs:` (documentation links). The sentinel words are fixed; the comment decoration around them is language-native (`// MARK: -` on Swift, `# region` on Python, a plain banner elsewhere). These are advisory — they do not affect test selection — but enable reviewers and tooling to verify coverage intent bidirectionally. See `test-selection-syntax.md § Footer Markers` for grammar, platform variants, and examples.
