# Workflow Testing Strategy Skill

Guidance for planning tests during P and A stages of the igrsoft workflow, before implementation begins.

Note: This skill focuses on workflow-integrated testing planning. For platform-specific testing patterns (Swift Testing, XCTest), see `apple-developer:testing-strategy`.

## Purpose

Ensure developers know WHAT tests to write before coding begins, so tests are developed alongside features, not as an afterthought.

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

## Handoff to Q Stage

Q stage receives:
1. **Test scope** from planning.md - WHAT to test
2. **Test architecture** from analyzing.md - HOW to structure tests
3. **Existing tests to update** list - WHERE changes needed

Q stage then:
- Creates detailed test plan (test-plan.md format)
- Implements tests following architecture
- Validates all acceptance criteria are tested

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

- `agents/product-manager.md` - P stage owner
- `agents/software-architector.md` - A stage owner
- `agents/qa-engineer.md` - Q stage owner
- `commands/test-plan.md` - Detailed test plan generation
- `skills/estimation-methodology.md` - Test effort estimation
