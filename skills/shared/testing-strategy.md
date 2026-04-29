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

| DV Stage (Developer) | QA Stage (QA Engineer) |
|----------------------|------------------------|
| Unit tests per `<plan_file>` specs | Additional edge case tests |
| Mock implementations for dependencies | Coverage gap analysis |
| Happy path + known error cases | Boundary and stress tests |
| Test data builders/fixtures | Test quality review |
