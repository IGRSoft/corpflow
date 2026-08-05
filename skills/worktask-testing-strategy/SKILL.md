---
name: worktask-testing-strategy
description: Test strategy planning guidance for PL and AR worktask stages. Use when planning test strategy during Planning or Architecture stages before implementation.
effort: medium
related:
  - agents/product-manager.md
  - agents/software-architector.md
  - agents/qa-engineer.md
  - commands/test-plan.md
  - skills/estimation-methodology/SKILL.md
---

# Worktask Testing Strategy Skill

Guidance for planning tests during PL and AR stages of the company-workflow worktask, before implementation begins.

Note: This skill focuses on worktask-integrated test *planning*. Framework and syntax specifics
for every platform live in one place — `${CLAUDE_SKILL_DIR}/../shared/testing-strategy.md`
(§ Framework by platform). Deeper per-framework guidance is the dev plugin's job, reached via
`/<plugin>:gen-tests`.

For per-stage test templates (PL, AR, DV), see `${CLAUDE_SKILL_DIR}/references/stage-templates.md`

## Purpose

Ensure developers know WHAT tests to write before coding begins, so tests are developed alongside features, not as an afterthought.

## Testing Framework

For the per-platform framework matrix, AAA pattern, naming conventions, and DV/QA boundary, see `${CLAUDE_SKILL_DIR}/../shared/testing-strategy.md`. Name the concrete framework in the plan — never leave it implied.

## Test Strategy by Feature Type

| Feature Type | Required Tests | Integration | E2E |
|--------------|----------------|-------------|-----|
| New feature | 3+ unit tests | 1+ | Optional |
| Bug fix | Regression test | If root cause spans components | No |
| Refactor | Verify existing pass | No new | No |
| Logic update | Update affected + new edge cases | If boundaries change | No |
| API endpoint | Request/response validation | Contract tests | Optional |
| UI component | State-holder tests (view model, store, hook) | Snapshot tests | Optional |

### UI test selectors

Prefer a stable, explicitly-set identifier over brittle text or coordinate lookups, so tests
survive copy changes and layout shifts. Set the identifier in the view; never query by visible
label or screen position.

| Platform | Set in the view | Query by |
|----------|-----------------|----------|
| apple | `accessibilityIdentifier` | XCUITest element queries |
| android | `Modifier.testTag(...)` | `onNodeWithTag` (Compose), `withTagValue` (Espresso) |
| web | `data-testid` (or an ARIA role + accessible name) | `getByTestId` / `getByRole` |

## Multi-substate UI screens (camera / photo / result)

Screens that cycle a single view through several substates (e.g. capture → review → result, each with default/error/empty/loading variants) hide two defect classes that snapshot and state-machine tests miss: a control that overflows or is clipped in one substate, and a transition control that fails to return the prior state. Plan a **hittable-control-bounds UITest** for any such screen.

### Hittable-control-bounds pattern

For each substate the screen renders, assert:

1. Every primary control is present AND hittable — on-screen, within window bounds, not clipped or overlapped. Query by the platform's stable identifier (table above), then assert hittability, not mere existence: `element.isHittable` (XCUITest), `assertIsDisplayed()` + `assertHasClickAction()` (Compose), `toBeVisible()` + `toBeEnabled()` (Playwright).
2. Each substate-transition control performs its transition AND its inverse returns the prior state — e.g. a RETAKE control from the review state returns the live-capture state.

One method may sweep every substate or you may write one per substate; either way, assert every primary control hittable in every substate it should appear.

## Handoff to QA Stage

QA stage receives from DV:
1. **Test scope** from `<plan_file>` (resolved via `task.metadata.plan_file`; fallback: newest `.context/planning-*.md`) - WHAT was planned to test
2. **Test architecture** from architecture-N.md - HOW tests are structured (only when AR ran; AR is optional, so with no AR the plan's Test Strategy is the whole authority and DV owns the test shape)
3. **Implemented unit tests** from development-N.md - WHAT tests DV already wrote
4. **Existing tests to update** list - WHERE changes were made

QA stage then:
- **Reviews** developer's unit tests for quality and completeness
- **Identifies gaps** in test coverage (edge cases, boundaries)
- **Adds missing tests** for scenarios not covered by DV
- **Runs integration and E2E tests** as defined in `<plan_file>`
- **Validates** all acceptance criteria are tested
- **Reports** test metrics in testing.md

## Logic Change Handling

When logic changes, follow this process:

### 1. Identify Affected Tests (PL Stage)
```markdown
### Existing Tests to Update
| Test File | Reason | Action |
|-----------|--------|--------|
| CalculatorTests | Formula changed | Update expected values |
| IntegrationTests | API contract changed | Update mocks |
```

### 2. Update Test Architecture (AR Stage)
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
