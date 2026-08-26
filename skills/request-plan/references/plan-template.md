# Plan Template

Fill these sections in this exact order. Keep it tight — a scannable one-screen plan beats an
exhaustive document. Cut a section to one line when the request is small; never drop a section
header, so the shape stays predictable.

#### Template — context, goal, scope, phases

```markdown
# Plan: <one-line goal>

## Context
Why this is asked now and what's already true in the repo (1–3 sentences grounded in what you read —
name the in-flight work, file, or constraint you found). If nothing relevant exists, say so.

## Goal
The outcome in one or two sentences. What "done" looks like.

## Scope
**In:** the concrete things this work includes.
**Out:** what is deliberately excluded (prevents scope creep; cite the heavier command for the
excluded part).

## Phases
P0 / P1 / P2 per `skills/shared/three-stage-planning.md`. Each phase independently deliverable;
tests included inside the phase, not split out.

| Phase | Scope | Why this order |
|-------|-------|----------------|
| P0 — Required | … | … |
| P1 — Nice-to-have | … | … |
| P2 — v1.1 | … | … |
```

All three rows are required. With nothing deferrable, write `P2 — v1.1: none` rather than
omitting the row.

#### Template — effort, risks, next step

```markdown
<!-- …continued: Plan template — effort, risks, recommended next step -->

## Effort (rough)
T-shirt size + 5-factor complexity (0–25) per `skills/estimation-methodology/SKILL.md`. A range, not a point.

| Size | Complexity (0–25) | Notes |
|------|-------------------|-------|
| <XS–XL> | <score> | key drivers (new tech, integration points, unknowns) |

## Risks & Dependencies
The 2–4 things most likely to derail this, each with a one-line mitigation. Flag any
security-sensitive surface (auth / PII / payments) explicitly — it forces the worktask tier.

## Recommended next step
**Surface check:** the verdict, then why — e.g. `no credential, untrusted-input or live-failure
surface → standard tier`. Required, on its own line, immediately before the trigger.

A single ready-to-paste worktask trigger line + one sentence of rationale. See `handoff.md`.
```

##### Why the surface-check line is required

Required the same way `P2 — v1.1: none` is: it forces an existing check to produce visible output.
The tier rules in `skills/estimation-methodology/SKILL.md` are precise and were still skipped
silently, because skipping them cost nothing. A verdict that has to be written is a verdict that has
to be reached, and a wrong one is visible to a reviewer instead of inferable only from the flag.

It must agree with the flag on the trigger line — see `handoff.md` § "The flag must match what the
plan body argues".

## Notes on filling it

- **Context must be grounded.** A generic "this improves the product" line means the
  context-gathering step was skipped. Reference something real from the repo.
- **Phases sequence risk and value**, they don't chop the work into thirds. P0 is the smallest thing
  delivering the core outcome; P1/P2 are genuinely deferrable.
- **Effort is a rough cut.** Hours, budget, or CSV export are `/estimate`'s job — say so in the
  Recommended next step rather than over-computing here.
