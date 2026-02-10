# Workflow Testing Strategy Skill

Guidance for planning tests during P and AR stages of the igrsoft workflow, before implementation begins.

Note: This skill focuses on workflow-integrated testing planning. For platform-specific testing patterns (Swift Testing, XCTest), see `apple-developer:testing-strategy`.

## Purpose

Ensure developers know WHAT tests to write before coding begins, so tests are developed alongside features, not as an afterthought.

## Testing Framework

### Swift Testing (Required - Unit Tests)

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

### XCTest (UI Tests Only)

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

### @MainActor for MainActor-Isolated Tests

When testing code that requires MainActor:

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

## P Stage: Test Strategy Definition

### What to Include in planning.md

```markdown
## Test Strategy

### Test Scope
| Category | Description | Priority |
|----------|-------------|----------|
| Unit Tests | [Core logic, pure functions, isolated components] | Required |
| Integration Tests | [API calls, database ops, service interactions] | Required/Optional |
| E2E Tests | [Critical user journeys only] | If applicable |

### Testing Framework
- **Unit Tests**: Swift Testing (`@Suite`, `@Test`, `#expect`)
- **UI Tests**: XCTest (XCUITest requirement)

### Test Acceptance Criteria
Derived from acceptance criteria - each should be testable:
- [ ] Given [precondition], when [action], then [expected result]
- [ ] [Edge case]: [Expected behavior]
- [ ] [Error case]: [Expected error handling]

### Existing Tests to Update
When changing existing logic, identify affected tests:
| Test File | Reason for Update | Impact |
|-----------|-------------------|--------|
| tests/UserServiceTests.swift | Login logic changed | Update mocks |
| tests/AuthFlowTests.swift | New OAuth parameter | Add test case |

### Test Effort Estimate
| Type | Hours |
|------|-------|
| New unit tests | X |
| New integration tests | Y |
| Update existing tests | Z |
| **Total** | **X+Y+Z** |
```

### Test Strategy by Feature Type

| Feature Type | Required Tests | Integration | E2E |
|--------------|----------------|-------------|-----|
| New feature | 3+ unit tests | 1+ | Optional |
| Bug fix | Regression test | If root cause spans components | No |
| Refactor | Verify existing pass | No new | No |
| Logic update | Update affected + new edge cases | If boundaries change | No |
| API endpoint | Request/response validation | Contract tests | Optional |
| UI component | ViewModel tests | Snapshot tests | Optional |

## A Stage: Test Architecture

### What to Include in analyzing.md

```markdown
## Test Architecture

### Testability Patterns
| Pattern | Applied To | Benefit |
|---------|------------|---------|
| Dependency Injection | Services, ViewModels | Mockable dependencies |
| Protocol Abstractions | Network, Storage | Swappable implementations |
| Pure Functions | Business logic | Deterministic testing |

### Test Doubles Strategy
| Component | Strategy | Implementation |
|-----------|----------|----------------|
| API Client | Mock | Protocol with mock implementation |
| Database | In-memory | SQLite in-memory or mock store |
| File System | Temporary directory | Create in setUp, clean in tearDown |
| Date/Time | Injectable | Clock protocol |

### Test Data Management
- Fixtures location: `Tests/Fixtures/`
- Factory pattern for test objects
- Shared test data builders

### Test Organization
```
Tests/
├── UnitTests/
│   ├── Domain/
│   └── Services/
├── IntegrationTests/
│   ├── API/
│   └── Storage/
└── Fixtures/
```
```

## D Stage: Test Implementation

The developer MUST implement unit tests alongside production code during the DV stage.

### Developer Responsibilities

1. **Read test specs** from `.context/planning.md § Test Strategy`
2. **Read test architecture** from `.context/analyzing.md § Test Architecture` (if available)
3. **Create test files** using the specified testing framework
4. **Follow test patterns** defined in the architecture (DI, mocking strategy, etc.)
5. **Run all tests** and verify they pass before completing DV stage
6. **Document test files** in `.context/development.md`

### Handoff Requirements (DV → QA)

- [ ] All unit tests from planning.md § Test Strategy implemented
- [ ] All unit tests pass locally (zero failures)
- [ ] Test file paths listed in development.md
- [ ] Mock/stub implementations created as needed

### What DV Writes vs What QA Adds

| DV Stage (Developer) | QA Stage (QA Engineer) |
|----------------------|------------------------|
| Unit tests per planning.md specs | Additional edge case tests |
| Mock implementations | Coverage gap analysis |
| Happy path + known error cases | Boundary and stress tests |
| Test data builders/fixtures | Integration and E2E tests |
| Tests for acceptance criteria | Test quality review and metrics |

### Development.md Test Documentation Template

```markdown
## Tests Implemented

### Unit Tests
| Test File | Tests For | Status |
|-----------|-----------|--------|
| Tests/UnitTests/Services/FooTests.swift | FooService | Pass |

### Test Summary
- Acceptance Criteria Covered: N/N
- Edge Cases Tested: [list]
- Mocks Created: [list]
```

## Handoff to Q Stage

QA stage receives from DV:
1. **Test scope** from planning.md - WHAT was planned to test
2. **Test architecture** from analyzing.md - HOW tests are structured
3. **Implemented unit tests** from development.md - WHAT tests DV already wrote
4. **Existing tests to update** list - WHERE changes were made

QA stage then:
- **Reviews** developer's unit tests for quality and completeness
- **Identifies gaps** in test coverage (edge cases, boundaries)
- **Adds missing tests** for scenarios not covered by DV
- **Runs integration and E2E tests** as defined in planning.md
- **Validates** all acceptance criteria are tested
- **Reports** test metrics in testing.md

## Logic Change Handling

When logic changes, follow this process:

### 1. Identify Affected Tests (P Stage)
```markdown
### Existing Tests to Update
| Test File | Reason | Action |
|-----------|--------|--------|
| CalculatorTests | Formula changed | Update expected values |
| IntegrationTests | API contract changed | Update mocks |
```

### 2. Update Test Architecture (A Stage)
- If new dependencies added: define test doubles
- If new patterns introduced: document testability approach
- If boundaries changed: update test organization

### 3. Implementation (D Stage)
- Update tests BEFORE or WITH code changes
- Run tests frequently during development
- Ensure no regressions introduced

## Integration with Estimation

Test effort is embedded in subtask estimates:

**Correct:**
| Subtask | Estimate |
|---------|----------|
| Implement login + tests | 8 SP (48h) |
| Add OAuth support + tests | 5 SP (30h) |

**Incorrect:**
| Subtask | Estimate |
|---------|----------|
| Implement login | 6 SP |
| Write login tests | 2 SP |

## Related

- `agents/product-manager.md` - PL stage owner
- `agents/software-architector.md` - AR stage owner
- `agents/qa-engineer.md` - QA stage owner
- `commands/test-plan.md` - Detailed test plan generation
- `skills/estimation-methodology.md` - Test effort estimation
