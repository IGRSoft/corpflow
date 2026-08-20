---
name: request-plan
description: Turn a free-form request into a context-aware plan (goal, scope, phases, effort, risks) and recommend `/worktask`. Use when the user asks for a plan, an approach, a breakdown, "how would you tackle this", or scoping — even without the word "plan".
effort: medium
version: 0.3.0
---

# Request Plan

Produce a **lightweight, grounded plan** from a free-form request plus current repository context,
then hand off to the worktask system. It bridges "I have an idea" and a full worktask: lighter than
a PRD (`/pm-requirements`), broader than a sizing estimate (`/estimate`).

The value is being **grounded** — the plan reflects this repo (in-flight work, recent commits,
project memory, relevant code), not a generic template. Read context before planning and let it
change the plan; otherwise this is a wishlist.

## Workflow

### 1. Restate the goal

State the goal in one line, in your own words, so the user can correct a misread cheaply.

#### Ask or plan — decide once, and default to planning

Asking is the exception. Apply in order:

1. **Found the surface? Plan it.** If context-gathering located the file, command, or mechanism the
   request is about, that is enough to plan — even if a follow-up question also comes to mind. A
   question you could have answered by planning costs a round trip and delivers nothing.
2. **Ambiguity that changes the phases? Fold it into the plan.** Two reasonable readings usually
   become P0 and P1, or an explicit **Out:** line. Present the plan and name the assumption.
3. **No surface at all? Ask — and only ask.** Available only once § 2's search has run and found
   nothing. Say so plainly and ask which system is meant. Never produce a full plan for a codebase
   you cannot see: plausible phases for a system nobody can point at read as real work and are not.
4. **Genuinely incompatible readings, or no subject named? Ask 1–2 focused questions.**

##### Never both

Never emit both a question and a full plan for one request — pick one. Don't invent scope to fill
silence; a wrong assumption propagates into every later section, but so does a needless question.

### 2. Gather context (lean)

Follow `references/context-gathering.md`. Read only what could change the plan: existing
`.context/` artifacts, project memory, recent git activity, and the code the request touches.

#### Search by behaviour, not by filename

Half of all graded failures were one mistake: the search stopped at a file whose *name* fit, in the
first directory that hit, while the file owning the behaviour sat in another subtree. **"Lean"
governs how much you read, never how hard you look.**

- **Use `Explore` for every "where does X live" question** — not a preference. A grep sweep anchored
  on a guessed filename only reproduces the guess.
- **Search for what the code does, not what it would be called.** Grep the symbols, strings, and
  error text the behaviour must produce. A filename is a hypothesis; a matching symbol is evidence.
- **One hit is not a finding.** Continue until a repo-wide search for the behaviour turns up nothing
  further, or until you hold two candidates — then open both and decide which owns it.

#### When you may stop searching

Stop on evidence, not on satisfaction: when you can **name the owning file and say what in it you
read**. "More reading wouldn't change the plan" is not a stop condition — a search that has not
reached the right file cannot tell that from the inside, which is how a confident plan ends up about
the wrong module.

The "no surface at all" branch below is available **only after this search has actually run**.
Asking which system is meant is right when the repo genuinely lacks it, wrong as the exit from a
search that got hard.

#### Confirm ownership before planning against a file

**Confirm the file you found actually owns the behaviour** — open it and check rather than inferring
ownership from a plausible name. A neighbouring file with a similar name is the most common way a
plan ends up specific, confident, and about the wrong thing (a stage-ownership plan that never
opened the stage-ownership doc; a cost-comparison plan that never reached the module producing the
costs). If you cannot confirm ownership, name the file you believe owns it and say you did not verify.

#### Do not assert what you did not check

**Do not assert absence or completeness you did not check.** "No other path exists", "that mapping
is already complete", or a count of things you did not enumerate are the claims most likely to be
wrong and least likely to be questioned, because they sound like the product of a search. Without
the search, write what you did look at and mark the rest unverified.

### 3. Synthesize the plan

Fill the template in `references/plan-template.md` exactly (fixed section order).

#### Key reuse — do not reinvent these

- **Phases** use the P0 Required / P1 Nice-to-have / P2 v1.1 model from
  `skills/shared/three-stage-planning.md`, each independently deliverable. **All three rows always
  appear.** With nothing deferrable, write `P2 — v1.1: none` — dropping the row reads as an
  oversight. Any follow-up you name anywhere in the plan belongs in P1 or P2; naming it and then
  folding it into P0 hides that it is deferrable and collapses a three-phase plan to one.
- **Tests live inside each phase's scope**, never as a separate phase (per the estimation skill).

##### Effort

A T-shirt size plus the 5-factor complexity score (0–25) from
`skills/estimation-methodology/SKILL.md`, as a range — a rough cut, not a budget. **Both parts are
required for every request type**, incidents included: a severity or priority table is not an effort
estimate and does not replace one. Naming the factors behind a surprising score helps, but the size
and the number are what the section owes.

### 4. Recommend the handoff

Follow `references/handoff.md`. Map size + complexity to an invocation with the canonical **Worktask
Tier Selection** logic in `skills/estimation-methodology/SKILL.md`, and emit one ready-to-paste
command line (e.g. `/worktask "<restated goal>"`). The surface check in that section decides
`--secure` and `--emergency` before size is considered.

#### Exactly one `/worktask` line

**Every plan ends with exactly one `/worktask` line.** Naming a more specific command
(`/pm-prioritize`, `/estimate`) is useful context, never a replacement — recommending one *instead*
of the worktask leaves the user with no handoff. Mention it alongside the trigger, not in place of it.
**Disputing the premise does not suspend the line.** A plan concluding the reported defect is
misdiagnosed, unreproducible, or absent from the file it was blamed on still emits one — triage is
work, and on a present-tense report `--emergency` is the tier that triages it. Prose naming the tier
("route this to incident response") is not the line; the line is a command the user can paste.

### 5. Output

Print the plan inline; the default is **not** to write files. Offer to persist it to
`.context/request-plan-0.md` (naming per `skills/task-folder-organization/SKILL.md`) when the user
wants it kept or it will directly seed a worktask run.

## What this skill is not

- Not a PRD generator — formal requirements, user stories, and acceptance criteria at scale route to
  `/pm-requirements`.
- Not a budget/CSV estimator — hours, rates, and exportable sizing route to `/estimate`.
- Not a roadmap — multi-quarter planning belongs in `/pm-roadmap`.

Staying lightweight is the point; resist padding the output toward those heavier formats.

## Reference files

| File | Read when |
|------|-----------|
| `references/context-gathering.md` | Step 2 — deciding what context to read and when to stop |
| `references/plan-template.md` | Step 3 — the exact output structure to fill |
| `references/handoff.md` | Step 4 — mapping effort to a worktask trigger |
