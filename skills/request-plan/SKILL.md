---
name: request-plan
description: Turn a free-form request into a context-aware plan (goal, scope, phases, effort, risks) and recommend `/worktask`. Use when the user asks for a plan, an approach, a breakdown, "how would you tackle this", or scoping — even without the word "plan".
effort: medium
version: 0.2.0
---

# Request Plan

Produce a **lightweight, grounded plan** from a free-form request plus the current repository
context, then hand off to the worktask system for execution. This is the missing bridge between
"I have an idea" and committing to a full worktask — it is intentionally lighter than a PRD
(`/pm-requirements`) and broader than a pure sizing estimate (`/estimate`).

The value is in being **grounded**: the plan reflects what is already in this repo (in-flight work,
recent commits, project memory, relevant code) rather than a generic template. Read context before
planning, and let the context change the plan — otherwise this is just a wishlist.

## Workflow

### 1. Restate the goal

State the goal in one line, in your own words, so the user can correct a misread cheaply.

#### Ask or plan — decide once, and default to planning

Asking is the exception. Apply in order:

1. **Found the surface? Plan it.** If context-gathering located the file, command, or mechanism the
   request is about, you have enough to plan — even if you can also think of a follow-up question.
   A question you could have answered by planning costs the user a round trip and delivers nothing.
2. **Ambiguity that changes the phases? Fold it into the plan.** Two reasonable readings usually
   become P0 and P1, or an explicit **Out:** line. Present the plan and name the assumption; do not
   stop and ask which one.
3. **No surface at all? Ask — and only ask.** If the request names a system this repo does not have,
   say so plainly and ask which one is meant. Do **not** produce a full plan for a codebase you
   cannot see: a template filled with plausible phases for a system nobody can point at reads as
   real work and is not.
4. **Genuinely incompatible readings, or no subject named? Ask 1–2 focused questions.**

Never emit both a question and a full plan for the same request — pick one. Don't invent scope to
fill silence; a wrong assumption propagates into every later section, but so does an unnecessary
question.

### 2. Gather context (lean)

Follow `references/context-gathering.md`. Read only what could actually change the plan: existing
`.context/` artifacts, project memory, recent git activity, and the specific code the request
touches. Prefer the `Explore` agent for open-ended "where does X live" questions over manual grep
sweeps. Stop gathering once more reading wouldn't move scope, phases, or effort.

**Confirm the file you found actually owns the behaviour before planning against it.** Open it and
check, rather than inferring ownership from a plausible name. A neighbouring file with a similar
name is the most common way a plan ends up specific, confident, and about the wrong thing — a
stage-ownership plan that never opened the stage-ownership doc, a cost-comparison plan that never
reached the module producing the costs. If you cannot confirm ownership, say which file you believe
owns it and that you did not verify.

### 3. Synthesize the plan

Fill the template in `references/plan-template.md` exactly (fixed section order). Key reuse — do not
reinvent these:

- **Phases** use the P0 Required / P1 Nice-to-have / P2 v1.1 model from
  `skills/shared/three-stage-planning.md`. Keep each phase independently deliverable. **All three
  rows always appear.** If the work genuinely has nothing deferrable, write `P2 — v1.1: none` —
  dropping the row reads as an oversight, and folding follow-ups you have already named into P0
  hides the fact that they are deferrable.
- **Effort** is a T-shirt size plus the 5-factor complexity score (0–25) from
  `skills/estimation-methodology/SKILL.md`. Give a range, not false precision — this is a rough cut, not a budget.
- **Tests live inside each phase's scope**, never as a separate phase (per the estimation skill).

### 4. Recommend the handoff

Follow `references/handoff.md`. Map the size + complexity to the right invocation using the canonical
**Worktask Tier Selection** logic in `skills/estimation-methodology/SKILL.md`, and emit a single, ready-to-paste
command line (e.g. `/worktask "<restated goal>"`). The surface check in that section decides
`--secure` and `--emergency` before size is considered.

**Every plan ends with exactly one `/worktask` line.** Naming a more specific command
(`/pm-prioritize`, `/estimate`) is useful context, never a replacement — recommending one *instead*
of the worktask leaves the user with no handoff. Mention it alongside the trigger, not in place of it.

### 5. Output

Print the plan inline. The default is **not** to write files — keep it conversational. Offer to
persist it to `.context/request-plan-0.md` (naming per `skills/task-folder-organization/SKILL.md`)
when the user wants it kept or when it will directly seed a worktask run.

## What this skill is not

- Not a PRD generator — if the user needs formal requirements, user stories, and acceptance criteria
  at scale, route to `/pm-requirements`.
- Not a budget/CSV estimator — if they need hours, rates, and exportable sizing, route to `/estimate`.
- Not a roadmap — multi-quarter planning belongs in `/pm-roadmap`.

Staying lightweight is the point; resist padding the output toward those heavier formats.

## Reference files

| File | Read when |
|------|-----------|
| `references/context-gathering.md` | Step 2 — deciding what context to read and when to stop |
| `references/plan-template.md` | Step 3 — the exact output structure to fill |
| `references/handoff.md` | Step 4 — mapping effort to a worktask trigger |
