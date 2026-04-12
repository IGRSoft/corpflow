---
name: workflow-testing-strategy
description: Test strategy planning guidance for PL and AR workflow stages. Use when planning test strategy during Planning or Architecture stages before implementation.
effort: medium
---

# Workflow Testing Strategy Skill

Guidance for planning tests during P and AR stages of the igrsoft workflow, before implementation begins.

Note: This skill focuses on workflow-integrated testing planning. For platform-specific testing patterns (Swift Testing, XCTest), see `apple-developer:testing-strategy`.

For per-stage test templates (PL, AR, DV), see `${CLAUDE_SKILL_DIR}/references/stage-templates.md`

## Purpose

Ensure developers know WHAT tests to write before coding begins, so tests are developed alongside features, not as an afterthought.

## Testing Framework

For Swift Testing and XCTest framework syntax, AAA pattern, and DV/QA boundary, see `${CLAUDE_SKILL_DIR}/../shared/testing-strategy.md`.

## Test Strategy by Feature Type

| Feature Type | Required Tests | Integration | E2E |
|--------------|----------------|-------------|-----|
| New feature | 3+ unit tests | 1+ | Optional |
| Bug fix | Regression test | If root cause spans components | No |
| Refactor | Verify existing pass | No new | No |
| Logic update | Update affected + new edge cases | If boundaries change | No |
| API endpoint | Request/response validation | Contract tests | Optional |
| UI component | ViewModel tests | Snapshot tests | Optional |

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

### 3. Implementation (DV Stage)
- Update tests BEFORE or WITH code changes
- Run tests frequently during development
- Ensure no regressions introduced

## Integration with Estimation

Test effort is embedded in subtask estimates:

**Correct:**
| Subtask | SP Min | SP Max | Hours Min | Hours Max |
|---------|--------|--------|-----------|-----------|
| Implement login + tests | 5 | 8 | 30 | 48 |
| Add OAuth support + tests | 3 | 5 | 18 | 30 |

**Incorrect:**
| Subtask | SP Min | SP Max |
|---------|--------|--------|
| Implement login | 4 | 6 |
| Write login tests | 1 | 2 |

## Related

- `agents/product-manager.md` - PL stage owner
- `agents/software-architector.md` - AR stage owner
- `agents/qa-engineer.md` - QA stage owner
- `commands/test-plan.md` - Detailed test plan generation
- `${CLAUDE_SKILL_DIR}/../estimation/SKILL.md` - Test effort estimation
