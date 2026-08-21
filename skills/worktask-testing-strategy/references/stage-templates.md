# Per-Stage Test Templates

## PL Stage: Test Strategy Definition

### What to Include in `<plan_file>` (e.g. `planning-0.md`)

Concatenate the two template parts below into the plan file's `## Test Strategy` block.

#### Plan Template — Scope & Framework

```markdown
## Test Strategy

### Test Scope
| Category | Description | Priority |
|----------|-------------|----------|
| Unit Tests | [Core logic, pure functions, isolated components] | Required |
| Integration Tests | [API calls, database ops, service interactions] | Required/Optional |
| E2E Tests | [Critical user journeys only] | If applicable |

### Testing Framework
Fill from the detected platform's row in `skills/shared/testing-strategy.md § Framework by
platform`; if the repo already uses another framework, the repo wins — note the deviation.
- **Unit Tests**: <framework + canonical syntax, e.g. Swift Testing (`@Suite`/`@Test`/`#expect`),
  JUnit 5 + MockK, Vitest, pytest>
- **Integration Tests**: <framework, e.g. Testcontainers, Robolectric, MSW>
- **UI / E2E Tests**: <framework, or "n/a — no UI layer">
  (Apple only: XCUITest requires XCTest, so UI tests stay on XCTest.)
```

#### Plan Template — Criteria, Existing Tests & Effort

```markdown
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

### Test Effort Estimate
| Type | Hours |
|------|-------|
| New unit tests | X |
| New integration tests | Y |
| Update existing tests | Z |
| **Total** | **X+Y+Z** |
```

## AR Stage: Test Architecture

### What to Include in architecture.md

Concatenate the two template parts below into the `## Test Architecture` block.

#### Architecture Template — Patterns & Doubles

```markdown
## Test Architecture

### Testability Patterns
| Pattern | Applied To | Benefit |
|---------|------------|---------|
| Dependency Injection | Services, ViewModels | Mockable dependencies |
| Protocol / interface abstractions | Network, Storage | Swappable implementations |
| Pure Functions | Business logic | Deterministic testing |

### Test Doubles Strategy
| Component | Strategy | Implementation |
|-----------|----------|----------------|
| API Client | Mock | Protocol with mock implementation |
| Database | In-memory | SQLite in-memory or mock store |
| File System | Temporary directory | Create in setUp, clean in tearDown |
| Date/Time | Injectable | Clock protocol |
```

#### Architecture Template — Data & Organization

~~~markdown
### Test Data Management
- Fixtures location: `Tests/Fixtures/`
- Factory pattern for test objects, shared test data builders

### Test Organization
`Tests/` → `UnitTests/{Domain,Services}`, `IntegrationTests/{API,Storage}`, `Fixtures/`
~~~

## DV Stage: Test Implementation

The developer MUST implement unit tests alongside production code during the DV stage.

### Developer Responsibilities

1. **Read test specs** from `.context/<plan_file> § Test Strategy` (resolve `<plan_file>` via `task.metadata.plan_file`; fallback: newest `.context/planning-*.md`)
2. **Read test architecture** from `.context/architecture-N.md § Test Architecture` (when AR ran — AR is optional per PL0's Stage Inclusion Criteria; N from `task.metadata.run_index`)
3. **Create test files** in the specified framework, following the architecture's patterns (DI, mocking strategy)
4. **Run tests scoped to changed code** (the new/updated tests plus any tests covering modified production files) and verify they pass before completing DV stage. Full project-suite regression is deferred to QA.
5. **Document test files** in `.context/development-N.md`

### Handoff Requirements (DV → DR → QA)

- [ ] All unit tests from `<plan_file> § Test Strategy` implemented
- [ ] All unit tests covering changed code pass locally (zero failures in the scoped/related test set; full-suite regression is QA's gate)
- [ ] Test file paths listed in development.md
- [ ] Mock/stub implementations created as needed

### What DV Writes vs What QA Adds

See `skills/shared/testing-strategy.md § DV vs QA Boundary` — canonical, not restated here.

### Footer Marker Examples (DV Output)

After implementing tests at D1.5, DV appends footer blocks to modified files. Grammar defined in `skills/shared/test-selection-syntax.md § Footer Markers`. Shown below in Swift — the `Test Info` / `Source Info` sentinel words are fixed, but the comment decoration is language-native (`# region` in Python, `// #region` in TypeScript, …); take it from § Platform Variants.

**Production source file** (`Sources/Services/PaymentService.swift`):

```swift
// MARK: - Test Info
// @test-file: Tests/Services/PaymentServiceTests.swift
// @related-tests: Tests/Integration/PaymentFlowTests.swift, Tests/Services/NetworkClientTests.swift
// @test-coverage: Unit tests for charge(), refund(), and validateCard(). Integration tests for end-to-end payment flow.
```

The mirror block in the **test file** carries `// MARK: - Source Info` with `@source-file:` (the production path) and optional `@doc-refs:` (upstream documentation URLs).

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
