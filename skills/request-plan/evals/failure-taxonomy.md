# request-plan failure taxonomy — v0.1.0 baseline

Open-coded from the 96 human-labelled v0.1.0 traces (`evals/labels/request-plan-human.jsonl`),
not brainstormed. Every category came out of an annotation the reviewer wrote while reading a
trace; nothing was added to round the list out.

This is **not** the plugin-wide `evals/failure-taxonomy.md` described in `evals/README.md` —
that one is open-coded from `failure-labels.jsonl` and is still blocked on its inputs. This file
covers one skill's eval set only.

## Scope

**These rates describe v0.1.0.** `skills/request-plan` is now v0.3.0 and
`skills/estimation-methodology` carries a new tier surface check, all written against these
categories. The table below is the **pre-registered baseline** the next re-capture gets compared
against, per category — not a description of current behaviour.

**Attribution warning.** v0.3.0 bundles eight changes: the seven category rules below plus the
§ 2 search-depth rewrite. They will be measured in a single capture, by explicit choice. A flat
or mixed result therefore cannot say which rule moved which category — only the per-category
rates in this table can narrow it, and only where a category maps to exactly one rule.

## Categories

Traces carry more than one label where more than one thing went wrong: 19 failures have one
category, 12 have two, 1 has three.

### Definitions

| Category | Definition |
|---|---|
| `missed-the-real-surface` | Planned confidently against a file that does not own the behaviour, while the file that does was never opened. |
| `asked-instead-of-planning` | Returned clarifying questions when the surface was located or locatable, producing no plan. |
| `no-handoff-trigger` | Emitted no pasteable `/worktask` line — zero triggers, a hedge, or a different command recommended in its place. |
| `over-escalation` | Routed `--secure` or `--emergency` for work touching no protected asset and failing nothing right now. |
| `under-escalation` | Routed standard tier where the surface owed `--secure`, or a live failure owed `--emergency`. |
| `planned-instead-of-asking` | Produced a full plan for a system this repo does not contain. |

#### Format and effort

| Category | Definition |
|---|---|
| `dropped-phase-rows` | Phases table missing the P1 and/or P2 row rather than writing the row as empty. |
| `unverified-absence-claim` | Asserted an absence, a completeness, or a count it never ran the search to establish. |
| `malformed-effort` | Effort section missing the T-shirt size or the 0–25 complexity score, or substituting a severity table for one. |

## Rates

Denominator is all 96 traces; 32 failed.

| Category | n | rate | share of failures | cases |
|---|---:|---:|---:|---|
| `missed-the-real-surface` | 11 | 11.5% | 34% | 23, 27, 28, 33, 57, 65, 66, 67, 73, 75, 90 |
| `asked-instead-of-planning` | 9 | 9.4% | 28% | 10, 24, 67, 69, 73, 75, 79, 82, 83 |
| `no-handoff-trigger` | 5 | 5.2% | 16% | 6, 24, 70, 79, 83 |
| `over-escalation` | 4 | 4.2% | 12% | 8, 29, 68, 81 |
| `under-escalation` | 4 | 4.2% | 12% | 12, 15, 61, 64 |
| `planned-instead-of-asking` | 4 | 4.2% | 12% | 36, 40, 94, 95 |
| `dropped-phase-rows` | 4 | 4.2% | 12% | 6, 52, 57, 61 |
| `unverified-absence-claim` | 3 | 3.1% | 9% | 27, 28, 95 |
| `malformed-effort` | 2 | 2.1% | 6% | 40, 61 |

## What the dimensions say

Failure rate by repo grounding — how findable the surface is:

| Grounding | Rate |
|---|---|
| `buried` | **17/34 — 50%** |
| `absent` | 4/14 — 29% |
| `obvious` | 9/36 — 25% |
| `adjacent` | 2/12 — 17% |

Several categories are **pure** in a single dimension value, which is what makes them
actionable rather than descriptive:

- `planned-instead-of-asking` — 4/4 `absent`
- `dropped-phase-rows` — 4/4 `obvious`
- `under-escalation` — 4/4 `obvious`
- `missed-the-real-surface` — 8/11 `buried`
- `asked-instead-of-planning` — 8/9 `buried`

By request type, `refactor` never failed (0/13) while `docs` (6/7) and `incident` (7/10) failed
most; both of those have small denominators and the eval set should carry more of each before
those rates are trusted.

## The finding that matters

**Half of all failures are one root cause wearing two faces.** The two largest categories are
overwhelmingly `buried`-grounding cases: 8 `missed-the-real-surface` + 8 `asked-instead-of-planning`
= 16 of 32 failures. Both are the same deficit — the search stopped before it reached the file
that owns the behaviour. The categories differ only in what the plan did next: assert against the
wrong file, or give up and ask.

### Why a prompt rule may not close it

That reframes the fix. `dropped-phase-rows`, `no-handoff-trigger`, and `malformed-effort` are
format failures a prompt rule genuinely closes. The buried cluster is a **search-depth** failure,
and a prompt rule telling the model to confirm ownership only helps if it already suspects it is
in the wrong place — which, by construction, it does not.

Through v0.2.0, `SKILL.md § 2. Gather context (lean)` ended with:

> Stop gathering once more reading wouldn't move scope, phases, or effort.

The condition is unknowable from inside the failure: a model that has not yet found the real
surface cannot tell that more reading would move the plan. The same section only *preferred* the
`Explore` agent. Both were candidate causes of the 50% `buried` rate, and neither was touched by
v0.2.0 — those rules govern what to do *after* context-gathering ends, not when it may end.
v0.3.0 rewrites the stop condition; whether that closes the cluster is unmeasured.

## Category → applied rule

Every category has a rule written against it. Coverage is not evidence the rule works; that is
what the re-capture measures.

### Mapping

| Category | Rule |
|---|---|
| `asked-instead-of-planning`, `planned-instead-of-asking` | `SKILL.md § Ask or plan — decide once, and default to planning` |
| `missed-the-real-surface` | `SKILL.md § Confirm ownership before planning against a file` |
| `unverified-absence-claim` | `SKILL.md § Do not assert what you did not check` |
| `dropped-phase-rows` | `SKILL.md § Key reuse` — all three rows always appear, `P2 — v1.1: none` |
| `no-handoff-trigger` | `SKILL.md § Exactly one /worktask line` |
| `over-escalation`, `under-escalation` | `skills/estimation-methodology/SKILL.md § Worktask Tier Selection` — surface check above the size logic |
| `malformed-effort` | `SKILL.md § Effort` — both parts required for every request type |
| `missed-the-real-surface`, `asked-instead-of-planning` (the `buried` cluster) | **v0.3.0** — `SKILL.md § Search by behaviour, not by filename` + `§ When you may stop searching` |
