---
name: request-plan
description: Turn a free-form request into a lightweight, context-aware plan (goal, scope, phases, rough effort, risks) and recommend the worktask trigger to execute it
argument-hint: '<request> [--save]'
allowed-tools: Read, Glob, Grep, Write, Task, Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/request-plan/scripts/capability-registry.sh *)
related:
  - skills/request-plan/SKILL.md
  - skills/estimation-methodology/SKILL.md
  - skills/shared/three-stage-planning.md
---

# Request Plan Command

Produce a **lightweight, grounded plan** from a free-form request plus current repository
context, then hand off to the worktask system — lighter than a PRD (`/product-requirements`),
broader than a sizing estimate (`/estimate`).

Thin entry point to the **`request-plan` skill**, which holds the full workflow and templates.

## Usage

```
/request-plan "we keep getting duplicate push notifications, help me plan a fix"
/request-plan --save "add CSV export to the estimates feature"
```

## Options

- `--save` — persist the plan to `.context/request-plan-0.md` (naming per
  `skills/task-folder-organization/SKILL.md`). Default is inline output only.

## Examples

```
/request-plan "we keep getting duplicate push notifications, help me plan a fix"
/request-plan --save "add CSV export to the estimates feature"
/request-plan "split the 4k-line sync manager into testable units"
/request-plan --save "migrate the app from UIKit to SwiftUI"
```

- Line 1 — a bug with no known cause: context gathering reads the failing area before scoping.
- Line 2 — `--save` writes `.context/request-plan-0.md` as well as printing the plan.
- Line 3 — a refactor: no new behaviour, so Scope carries the seams and Risks the regression surface.
- Line 4 — XL work: the plan names 2-3 sub-tasks per `skills/request-plan/references/handoff.md` and still emits one
  ready-to-paste `/worktask` line, for the first of them.

## Workflow

1. Load the `request-plan` skill (`skills/request-plan/SKILL.md`) and follow its 5 steps:
   restate the goal → gather context (lean) → synthesize the plan → recommend the handoff → output.
2. Keep it lightweight. A heavier sibling command may be named **alongside** the handoff, never in
   place of it — `SKILL.md § 4` holds the list and is the authority. Naming one here is what made
   this file go stale twice; a looser restatement of that rule licensed the punts § 4 forbids.
3. End with a single ready-to-paste `/worktask` command line (PL0 dynamic sizing handles small tasks
   by dropping stages) — exactly one, with the single narrow exception `SKILL.md § 4` states and no
   other. XL-sized work still gets its trigger: name the 2–3 sub-tasks per `skills/request-plan/references/handoff.md`
   and emit the line for the first of them. "For XL, emit no command" leaves the user nothing to
   paste — the `no-handoff-trigger` failure wearing a size label.

## Output Format

`skills/request-plan/references/plan-template.md` — `# Plan: <one-line goal>` then
Context · Goal · Scope · Phases · Effort (rough) · Risks & Dependencies ·
Recommended next step (the single `/worktask` command line).

## Integration

- `/worktask` — execute the recommended tier
- `/estimate` — when hours, budget, or CSV export are needed instead of a rough cut
- `/product-requirements` — when a full PRD is needed instead of a lightweight plan
