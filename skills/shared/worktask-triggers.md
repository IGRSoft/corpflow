---
name: worktask-triggers
description: The single worktask trigger (/worktask, worktask:) — the BLOCKING invocation rule, PL0 dynamic stage sizing, and the PL-gate-vs-FN-gate execution model. Use when a user message starts with the worktask trigger or when resolving worktask semantics.
---

# Worktask Triggers

Single source of truth for worktask trigger prefixes and their invocation rule.

## BLOCKING

> When a user message begins with `/worktask` or `worktask:`, the VERY FIRST action MUST be to
> launch the worktask pipeline via its canonical entry point —
> the `/worktask` command or `Skill({skill:"igrsoft:worktask"})`. No file reads, no codebase
> exploration, and no agent delegation before that launch. Handling the trigger as a freeform
> instruction inline is a violation.

`/worktask` (= `worktask:`) is the only trigger. After PL0 it STOPs at the PL gate (the
one human checkpoint) and presents the plan for approval, unless `--auto-plan` or `--milestone:N`
is set (both stamp `plan_gate: "bypass"`). The FN gate always runs unattended (`fn_gate: "bypass"`)
and the PR is the review surface — see `../worktask/references/fn-gate.md` and
`../../commands/worktask.md` *EXECUTION MODEL (BINDING)*.

## Triggers

| Trigger | Stages | Behavior | Use For |
|---------|--------|----------|---------|
| `worktask:` (= `/worktask`) | Full dynamically-sized pipeline (PL0 drops stages for low complexity) | PL gate (plan approval) after PL0; FN unattended. `--auto-plan` / `--milestone:N` bypass the PL gate. | Any task — single-file fix to multi-file feature |

Dynamic sizing (PL0) selects which of the 9 stages actually run — the old shortcuts are subsumed by
PL0 dropping stages for low complexity. See `../worktask/SKILL.md § Dynamic Worktask Sizing`.

The post-plan checkpoint is carried by `PL0.metadata.plan_gate`, default `"checkpoint"`.
`--auto-plan` and `--milestone:N` stamp `"bypass"`. On resume after interruption, this carrier
tells the orchestrator whether to re-enter the stage loop immediately (`bypass`) or stop for user
approval (`checkpoint`) — see `../worktask/references/resume.md § State → Action Table`.

## See also

- `../worktask/references/fn-gate.md` — FN gate is always bypassed (unattended finalization).
- `../../commands/worktask.md` — command entry point, *EXECUTION MODEL (BINDING)*, Options.
- `stage-codes.md` — stage code ↔ agent ↔ model table and pipeline definitions.
