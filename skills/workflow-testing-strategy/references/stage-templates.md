# Per-Stage Test Templates

## P Stage: Test Strategy Definition

### What to Include in `<plan_file>` (e.g. `planning-0.md`)

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

## DV Stage: Test Implementation

The developer MUST implement unit tests alongside production code during the DV stage.

### Developer Responsibilities

1. **Read test specs** from `.context/<plan_file> § Test Strategy` (resolve `<plan_file>` via `task.metadata.plan_file`; fallback: newest `.context/planning-*.md`, then legacy `.context/planning.md`)
2. **Read test architecture** from `.context/analyzing-N.md § Test Architecture` (if available; N from `task.metadata.run_index`)
3. **Create test files** using the specified testing framework
4. **Follow test patterns** defined in the architecture (DI, mocking strategy, etc.)
5. **Run tests scoped to changed code** (the new/updated tests plus any tests covering modified production files) and verify they pass before completing DV stage. Full project-suite regression is deferred to QA.
6. **Document test files** in `.context/development-N.md`

### Handoff Requirements (DV → DR → QA)

- [ ] All unit tests from `<plan_file> § Test Strategy` implemented
- [ ] All unit tests covering changed code pass locally (zero failures in the scoped/related test set; full-suite regression is QA's gate)
- [ ] Test file paths listed in development.md
- [ ] Mock/stub implementations created as needed

### What DV Writes vs What QA Adds

| DV Stage (Developer) | QA Stage (QA Engineer) |
|----------------------|------------------------|
| Unit tests per `<plan_file>` specs | Additional edge case tests |
| Mock implementations | Coverage gap analysis |
| Happy path + known error cases | Boundary and stress tests |
| Test data builders/fixtures | Integration and E2E tests |
| Tests for acceptance criteria | Test quality review and metrics |

### Footer Marker Examples (DV Output)

After implementing tests at D1.5, DV appends footer blocks to modified files. Grammar defined in `skills/shared/test-selection-syntax.md § Footer Markers`.

**Production source file** (`Sources/Services/PaymentService.swift`):

```swift
// ... existing code ...

// MARK: - Test Info
// @test-file: Tests/Services/PaymentServiceTests.swift
// @related-tests: Tests/Integration/PaymentFlowTests.swift, Tests/Services/NetworkClientTests.swift
// @test-coverage: Unit tests for charge(), refund(), and validateCard(). Integration tests for end-to-end payment flow.
```

**Test file** (`Tests/UnitTests/Services/PaymentServiceTests.swift`):

```swift
// ... existing tests ...

// MARK: - Source Info
// @source-file: Sources/Services/PaymentService.swift
// @doc-refs: https://developer.apple.com/documentation/storekit
```

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
