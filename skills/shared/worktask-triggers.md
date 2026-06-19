---
name: worktask-triggers
description: Worktask trigger prefixes (/worktask, worktask:, fworktask:, quick:, micro:) — the BLOCKING invocation rule and per-trigger stage scope / unattended-vs-checkpoint behavior. Use when a user message starts with a worktask trigger or when resolving trigger semantics.
---

# Worktask Triggers

Single source of truth for worktask trigger prefixes and their invocation rule.

## BLOCKING

> When a user message begins with `/worktask`, `worktask:`, `fworktask:`, `quick:`, or `micro:`,
> the **VERY FIRST action MUST be to launch the worktask pipeline via its canonical entry point** —
> the `/worktask` command or `Skill({skill:"igrsoft:worktask"})`. No file reads, no codebase
> exploration, and no agent delegation before that launch. Handling the trigger as a freeform
> instruction inline is a violation.

`/worktask`, `worktask:`, and `fworktask:` run **fully unattended** end-to-end — there is no human
approval gate; the orchestrator proceeds from PL0 straight through FN/ST and the PR is the review
surface (see `../worktask/references/fn-gate.md` and `../../commands/worktask.md`
*UNATTENDED EXECUTION (BINDING)*). `micro:` and `quick:` keep a human checkpoint after the plan.

## Triggers

| Trigger | Stages | Behavior | Use For |
|---------|--------|----------|---------|
| `micro:` | Plan → approve → edit | Human checkpoint after plan | Single-file fixes, typos |
| `quick:` | PL → DV → DR → QA | Human checkpoint after plan | Small features, bug fixes |
| `worktask:` (= `/worktask`) | Full dynamically-sized pipeline | Fully unattended | Multi-file features |
| `fworktask:` | Same as `worktask:` | Fully unattended (trusted full run) | Trusted full runs |

`fworktask:` is identical to `worktask:` — both are unattended. The legacy `--auto-continue` flag is
a deprecated no-op (`../../commands/worktask.md` Options table). Dynamic sizing (PL0) selects which
of the 9 stages actually run — see `../worktask/SKILL.md § Dynamic Worktask Sizing`.

The `micro:`/`quick:` post-plan checkpoint is carried by `PL0.metadata.plan_gate == "checkpoint"`
(unattended triggers stamp `"bypass"`). On resume after interruption, this carrier tells the
orchestrator whether to re-enter the stage loop immediately or stop for user approval —
see `../worktask/references/resume.md § State → Action Table`.

## See also

- `../worktask/references/fn-gate.md` — FN gate is always bypassed (unattended finalization).
- `../../commands/worktask.md` — command entry point, *UNATTENDED EXECUTION (BINDING)*, Options.
- `stage-codes.md` — stage code ↔ agent ↔ model table and pipeline definitions.
