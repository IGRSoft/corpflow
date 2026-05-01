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

DV runs the **scoped/related test set** — new tests plus tests covering changed production files. QA runs the **full project test suite** as the regression gate. This division keeps the DV iteration loop fast while preserving regression coverage.

| DV Stage (Developer) | QA Stage (QA Engineer) |
|----------------------|------------------------|
| Unit tests per `<plan_file>` specs | Additional edge case tests |
| Mock implementations for dependencies | Coverage gap analysis |
| Happy path + known error cases | Boundary and stress tests |
| Test data builders/fixtures | Test quality review |
| **Run scoped tests** (changed/affected only) | **Run full test suite** (regression gate) |

## UI Test Gate

UI tests (XCUITest bundles, Visual QA / Design Comparison) are slow and simulator-bound. They run **only when explicitly requested** by the plan file — never by auto-detection.

### Contract

- **Flag**: `requires_ui_tests: <bool>` in `<plan_file>` frontmatter (`planning-N.md`).
- **Default**: `false`. Off-by-default keeps DV/QA fast on backend, refactor, and doc-only tasks.
- **Writer**: PL stage / `agents/product-manager.md` § Test Strategy Definition.
- **Readers**:
  - DV step D2 (`agents/developer.md`) — gates `test_sim` UI bundles.
  - QA step Q1 (`agents/qa-engineer.md`) — gates `test_sim` UI bundles in the full-suite run.
  - QA Design Comparison (`agents/qa-engineer.md` § Design Comparison) — gates the entire Visual QA section.
- **DR** (`agents/technical-lead.md`) does not run tests at all (read-only review); the flag does not apply there.

### When to set `requires_ui_tests: true`

At least one must apply:

- New SwiftUI/UIKit views or screens
- Visual design artifacts in `.context/designs/` that need verification
- Layout, styling, or animation changes that require a screen capture to validate
- Stakeholder explicitly requests UI verification

### Skip mechanics

When the flag is `false` or absent:

```bash
# XcodeBuildMCP equivalent — pass via test_sim args
xcodebuild test \
  -project MyApp.xcodeproj \
  -scheme MyApp \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skip-testing:MyAppUITests \
  -skip-testing:OtherUITestTarget
```

One `-skip-testing:<Target>` per UI test target on the scheme (discover via `mcp__XcodeBuildMCP__list_schemes`).

DV records `ui_tests_skipped: true` in `.context/development.md § Decisions`. QA records the same in `testing.md § Notes`, and writes `Skipped — requires_ui_tests=false in plan` in `testing.md § Design Comparison`.
