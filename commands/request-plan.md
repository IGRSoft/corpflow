---
name: request-plan
description: Turn a free-form request into a lightweight, context-aware plan (goal, scope, phases, rough effort, risks) and recommend the worktask trigger to execute it
argument-hint: '<request> [--save]'
model: sonnet
allowed-tools: Read, Glob, Grep, Write, Task
related:
  - skills/request-plan/SKILL.md
  - skills/estimation-methodology/SKILL.md
  - skills/shared/three-stage-planning.md
---

# Request Plan Command

Produce a **lightweight, grounded plan** from a free-form request plus current repository
context, then hand off to the worktask system — lighter than a PRD (`/pm-requirements`),
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

## Workflow

1. Load the `request-plan` skill (`skills/request-plan/SKILL.md`) and follow its 5 steps:
   restate the goal → gather context (lean) → synthesize the plan → recommend the handoff → output.
2. Keep it lightweight. If the user actually needs formal requirements, route to `/pm-requirements`;
   if they need hours and budget, route to `/estimate`.
3. End with a single ready-to-paste `/worktask` command line (PL0 dynamic sizing handles small tasks
   by dropping stages). Exception: for XL-sized work, emit no command — instead list 2–3 sub-tasks to
   split into per `references/handoff.md`.

## Output Format

`skills/request-plan/references/plan-template.md` — `# Plan: <one-line goal>` then
Context · Goal · Scope · Phases · Effort (rough) · Risks & Dependencies ·
Recommended next step (the single `/worktask` command line).

## Integration

- `/worktask` — execute the recommended tier
- `/estimate` — when hours, budget, or CSV export are needed instead of a rough cut
- `/pm-requirements` — when a full PRD is needed instead of a lightweight plan
