# Per-Stage Test Templates

## PL Stage: Test Strategy Definition

### What to Include in `<plan_file>` (e.g. `planning-0.md`)

Concatenate the two template parts below into the plan file's `## test-strategy` block — the
optional PL anchor; a `## Test Strategy` H2 fails the anchor lint.

#### Plan Template — Scope & Framework

```markdown
## test-strategy

### Test Scope
| Category | Description | Priority |
|----------|-------------|----------|
| Unit Tests | [Core logic, pure functions, isolated components] | Required |
| Integration Tests | [API calls, database ops, service interactions] | Required/Optional |
| E2E Tests | [Critical user journeys only] | If applicable |

### Testing Framework
Fill from the detected platform's row in `skills/shared/testing-strategy.md § Framework by
platform`; if the repo already uses another framework, the repo wins — note the deviation.
- Unit Tests: <framework + canonical syntax, e.g. Swift Testing (`@Suite`/`@Test`/`#expect`),
  JUnit 5 + MockK, Vitest, pytest>
- Integration Tests: <framework, e.g. Testcontainers, Robolectric, MSW>
- UI / E2E Tests: <framework, or "n/a — no UI layer">
  (Apple only: XCUITest requires XCTest, so UI tests stay on XCTest.)
```

#### Plan Template — Criteria, Existing Tests & Effort

```markdown
### Test Acceptance Criteria
One testable line per acceptance criterion:
- [ ] Given [precondition], when [action], then [expected result]
- [ ] [Edge case]: [Expected behavior]
- [ ] [Error case]: [Expected error handling]

### Existing Tests to Update
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

The `## Test Architecture` block holds the three tables `agents/software-architector.md § Test
Architecture Design` requires; the test data strategy its checklist asks for goes in the Test
Doubles or Test Boundaries rows. Concatenate the two template parts below.

#### Architecture Template — Decisions & Doubles

```markdown
## Test Architecture

### Testability Design Decisions
| Decision | Rationale | Test Impact |
|----------|-----------|-------------|
| Inject services into ViewModels | Swap real I/O for doubles | ViewModels unit-testable without network |
| Protocol boundary for Network and Storage | Isolate platform APIs | Doubles replace them in unit tests |
| Keep business logic in pure functions | No hidden state | Deterministic tests, no setup |

### Test Doubles Strategy
| Component | Double Type (mock/in-memory/stub) | Purpose |
|-----------|-----------------------------------|---------|
| API Client | mock | Verify requests, script responses |
| Database | in-memory | Real queries without disk state |
| Date/Time | stub | Fixed clock for time-dependent logic |
```

#### Architecture Template — Boundaries

~~~markdown
### Test Boundaries
| Layer (domain/data/UI) | What to Test | What to Mock |
|------------------------|--------------|--------------|
| domain | Business rules, edge cases | Nothing (pure) |
| data | Mapping, persistence, fixtures from `Tests/Fixtures/` | Network, clock |
| UI | State transitions in ViewModels | Services |
~~~

## DV Stage: Test Implementation

DV implements these specs per `agents/developer.md § D1.5 — Write unit tests` and
`§ Unit Test Implementation`; footer-marker grammar and examples live in
`skills/shared/test-selection-syntax.md § Footer Markers`. A plan can hold DV to this handoff
(DV → DR → QA):

- [ ] All unit tests from `<plan_file> § test-strategy` implemented
- [ ] All unit tests covering changed code pass locally (full-suite regression is QA's gate)
- [ ] Mock/stub implementations created as needed
- [ ] Test files documented in `development-N.md` as H3s under `## tests-added` (the DV anchor):

```markdown
### Unit Tests
| Test File | Tests For | Status |
|-----------|-----------|--------|
| Tests/UnitTests/Services/FooTests.swift | FooService | Pass |

### Test Summary
- Acceptance Criteria Covered: N/N
- Edge Cases Tested: [list]
- Mocks Created: [list]
```
