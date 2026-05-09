---
name: testing-strategy
description: Swift Testing and XCTest framework syntax, AAA pattern, testing pyramid, and DV/QA boundary. Reference when implementing or planning unit/UI tests on Apple platforms.
effort: low
---

# Testing Strategy

## Testing Pyramid

| Layer | Coverage | Scope | When |
|-------|----------|-------|------|
| Unit (70%) | Fast, isolated, deterministic | Single logic unit, mocked dependencies | Every commit |
| Integration (20%) | Component interactions | DB/API integration, service-to-service | PR and merge |
| E2E (10%) | Critical user journeys | Real browser/device | Before release |

## Swift Testing (Primary — Unit Tests)

All unit tests MUST use Swift Testing framework:

```swift
import Testing

@Suite("Feature Tests")
struct FeatureTests {
    @Test("happy path returns expected result")
    func happyPath() {
        let result = feature.execute()
        #expect(result == .success)
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

### @MainActor for MainActor-Isolated Tests

```swift
@Suite("ViewModel Tests")
@MainActor
struct ViewModelTests {
    let sut: ViewModel

    init() {
        sut = ViewModel()
    }

    @Test("state updates on action")
    func stateUpdates() {
        sut.performAction()
        #expect(sut.state == .updated)
    }
}
```

## XCTest (UI Tests Only)

XCUITest requires XCTest framework:

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

## AAA Pattern

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

Test method names: descriptive, no `test_` prefix. Example: `loginValidCredentialsReturnsSession()`.

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

Tests are slow (especially UI/simulator bundles). The gate decides — per workflow run — **how much of the test pyramid runs and where**. Defaults are tightened so backend, refactor, and doc-only tasks do not pay simulator-startup cost.

### Three test modes

| Mode | DV behaviour | QA behaviour | When PL sets it |
|------|--------------|--------------|-----------------|
| `build-only` | Build + run **smoke set only** (`@test-required` ∪ `metadata.always_required_tests`). Parse `@depends-on:` markers. Emit Selected Tests list for QA. | Run **only Selected Tests** (always-required ∪ dependency-matched). Visual comparison gated on `ui_visual_check`. | Repos that have completed marker migration. Refactors, dep updates, doc-only changes. **Opt-in** via explicit `test_mode: build-only` in plan. |
| `scoped` (effective default) | Build + run Selected Tests + tests in any module the diff touches. | Selected Tests + module-level tests + any QA-added edge-case tests. Visual comparison gated on `ui_visual_check`. | Bug fixes, small features. Default for plans that omit `test_mode` (avoids silent coverage blackout on untagged repos). |
| `full` | Build + run Selected Tests at DV. | **Full project test suite** as regression gate. Visual comparison gated on `ui_visual_check`. | Release candidates, multi-module features, post-major-dep-upgrade. |

**Effective default**: when `<plan_file>` omits `metadata.test_mode`, agents resolve to `scoped` (not `build-only`). This preserves today's "DV runs scoped tests, QA runs the unit+integration suite" semantics for untagged repositories. To unlock `build-only` speedup, a plan must opt in by writing `test_mode: build-only` explicitly **and** the repo should have meaningful marker coverage (parser logs a warning if `< 50%` of test files lack any marker).

**Auto-promotion safety nets** (DV/QA enforce these even if PL set a tighter mode):
- Selected Tests list is empty AND `test_mode = build-only` → DV warns and runs the smoke set; QA promotes to `scoped` with a logged note in `testing-N.md § Notes`.
- Platform has no marker parser handler (e.g., Android/Web until handlers ship) AND `test_mode ∈ {build-only, scoped}` → DV auto-promotes to `full` for that platform with a logged warning. The mode stays as the PL-declared value in metadata; the promotion is recorded in `development-N.md § Decisions` with `auto_promoted_mode: full`.

### Contract

- **Flag**: `metadata.test_mode: build-only | scoped | full` in `<plan_file>` frontmatter.
- **Effective default when absent**: `scoped` (see *Effective default* note above). `build-only` is opt-in.
- **Companion flags**:
  - `metadata.always_required_tests: [<test ID>...]` — explicit override, included in every Selected Tests list regardless of mode.
  - `metadata.ui_visual_check: <bool>` — default `false`. When `true` AND `.context/designs/` exists, QA performs Design Comparison (was previously bundled into `requires_ui_tests`). Independent of `test_mode`.
- **Writer**: PL stage (`agents/product-manager.md` § Test Strategy Definition).
- **Readers**:
  - DV step D2 (`agents/developer.md`) — parses markers, computes Selected Tests, runs only when `test_mode ∈ {scoped, full}`.
  - QA step Q1 (`agents/qa-engineer.md`) — three-mode dispatcher.
  - QA Design Comparison (`agents/qa-engineer.md` § Design Comparison) — gated on `ui_visual_check=true` (NOT `test_mode`).
- **DR** (`agents/technical-lead.md`) does not run tests; the gate does not apply.

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
- New SwiftUI/UIKit views or screens
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

QA reads this section verbatim. If QA adds new tests during Q-stage edge-case review, it appends them to a `## Selected Tests (QA additions)` section in `testing-N.md`.

### Backward compatibility (one release cycle)

If `<plan_file>` has the legacy `requires_ui_tests` flag and no `test_mode`:

| Legacy | Mapped to | Rationale |
|--------|-----------|-----------|
| `requires_ui_tests: true` | `test_mode: full`, `ui_visual_check: true` | Preserves today's "run everything including UI bundles + visual compare" |
| `requires_ui_tests: false` (or absent) | `test_mode: scoped`, `ui_visual_check: false` | Preserves today's "DV scoped tests, QA full unit+integration with UI skipped". **Does NOT map to `build-only`** — that would silently drop unit-test execution at QA on legacy plans. |

PL/DV/QA emit one deprecation note in their artifact's `§ Notes`:

> `requires_ui_tests` is deprecated; use `test_mode` + `ui_visual_check`. See `skills/shared/testing-strategy.md § Test Selection Gate`. Removed next minor release.

### Skip mechanics — Apple platforms

When DV/QA runs Selected Tests via XcodeBuildMCP, the list is translated to positive `-only-testing:` arguments (one per test ID), not negative `-skip-testing:`:

```bash
# Selected Tests = [PaymentRefundTests/testRefundFlow, AppLaunchTests/testLaunchSucceeds]
xcodebuild test \
  -project MyApp.xcodeproj \
  -scheme MyApp \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:MyAppTests/PaymentRefundTests/testRefundFlow \
  -only-testing:MyAppTests/AppLaunchTests/testLaunchSucceeds
```

When `test_mode=full`, the entire suite runs without `-only-testing:`. UI test bundles run unless explicitly excluded (no implicit `-skip-testing:` — UI tests run because `ui_visual_check` or `test_mode=full` opted into them).

DV records `test_mode`, `selected_tests_count`, and `ui_visual_check` in `.context/development-N.md § Decisions`. QA records the resolved mode and any `Selected Tests (QA additions)` in `testing-N.md § Notes`.

### Marker grammar reference

See `skills/shared/test-selection-syntax.md` for the full marker grammar (`@test-required`, `@depends-on:`, `@test-tag:`), parser pseudocode, and Swift Testing trait equivalents.
