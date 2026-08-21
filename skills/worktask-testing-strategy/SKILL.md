---
name: worktask-testing-strategy
description: Use when planning test strategy during Planning or Architecture stages before implementation. Test strategy planning guidance for PL and AR worktask stages.
effort: medium
related:
  - agents/product-manager.md
  - agents/software-architector.md
  - agents/qa-engineer.md
  - commands/test-plan.md
  - skills/estimation-methodology/SKILL.md
---

# Worktask Testing Strategy Skill

Worktask-integrated test *planning* for the PL and AR stages, before implementation begins, so
developers know WHAT to test while coding rather than after.

- Framework matrix, AAA pattern, naming conventions, DV/QA boundary:
  `${CLAUDE_SKILL_DIR}/../shared/testing-strategy.md`. Name the concrete framework in the plan —
  never leave it implied. Deeper per-framework guidance is the dev plugin's job, via `/<plugin>:gen-tests`.
- Per-stage test templates (PL, AR, DV): `${CLAUDE_SKILL_DIR}/references/stage-templates.md`.

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
survive copy changes and layout shifts. Set it in the view; never query by visible label or
screen position.

| Platform | Set in the view | Query by |
|----------|-----------------|----------|
| apple | `accessibilityIdentifier` | XCUITest element queries |
| android | `Modifier.testTag(...)` | `onNodeWithTag` (Compose), `withTagValue` (Espresso) |
| web | `data-testid` (or an ARIA role + accessible name) | `getByTestId` / `getByRole` |

## Multi-substate UI screens (camera / photo / result)

Screens that cycle one view through several substates (capture → review → result, each with
default/error/empty/loading variants) hide two defect classes that snapshot and state-machine tests
miss: a control clipped or overflowing in one substate, and a transition control that fails to
return the prior state. Plan a **hittable-control-bounds UITest** for any such screen.

### Hittable-control-bounds pattern

For each substate the screen renders, assert:

1. Every primary control is present AND hittable — on-screen, within window bounds, not clipped or overlapped. Query by the platform's stable identifier (table above), then assert hittability, not mere existence: `element.isHittable` (XCUITest), `assertIsDisplayed()` + `assertHasClickAction()` (Compose), `toBeVisible()` + `toBeEnabled()` (Playwright).
2. Each substate-transition control performs its transition AND its inverse returns the prior state — e.g. a RETAKE control from the review state returns the live-capture state.

One method may sweep every substate or you may write one per substate; coverage is the rule, not shape.

## Handoff to QA Stage

| QA receives from DV | Source | QA then |
|---|---|---|
| Test scope — WHAT was planned | `<plan_file> § Test Strategy` (resolve via `task.metadata.plan_file`; fallback: newest `.context/planning-*.md`) | Runs integration + E2E as the plan defines; validates every acceptance criterion is tested |
| Test architecture — HOW tests are structured | `architecture-N.md`, only when AR ran (AR is optional; with no AR the plan's Test Strategy is the whole authority and DV owns the test shape) | Reviews DV's unit tests for quality and completeness |
| Implemented unit tests + the existing-tests-to-update list (WHERE changes landed) | `development-N.md` | Fills coverage gaps (edge cases, boundaries) and reports metrics in `testing.md` |

## Logic Change Handling

| Stage | Action on a logic change |
|-------|--------------------------|
| PL | List affected tests in an `### Existing Tests to Update` table — test file, reason, action (formula changed → update expected values; API contract changed → update mocks) |
| AR | New dependencies → define test doubles; new patterns → document the testability approach; changed boundaries → update test organization |
| DV | Update tests BEFORE or WITH the code change, run them frequently, prove no regressions |

## Integration with Estimation

Test effort is embedded in each subtask estimate, never a line of its own:
`Implement login + tests | SP 5–8 | 30–48h` — never `Implement login` plus a separate
`Write login tests` row.
