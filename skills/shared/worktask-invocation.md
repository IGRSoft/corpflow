---
name: worktask-invocation
description: How a worktask is launched (the /worktask command or Skill({skill:"igrsoft:worktask"})), the BLOCKING first-action rule, PL0 dynamic stage sizing, and the PL/FN gate execution model. Use when launching a worktask or resolving worktask semantics.
---

# Worktask Invocation

Single source of truth for how a worktask is launched and its invocation rule.

## BLOCKING

> When a user asks to run a worktask — via the `/worktask` command (or `/worktask --emergency` for the
> incident pipeline) or by invoking `Skill({skill:"igrsoft:worktask"})` — the VERY FIRST action MUST
> be to launch the worktask pipeline via that canonical entry point. No file reads, no codebase
> exploration, and no agent delegation before that launch. Handling the request as a freeform
> instruction inline is a violation.

`/worktask` (or `Skill({skill:"igrsoft:worktask"})`) is the canonical entry point. After PL0 it STOPs
at the PL gate (the one human checkpoint) and presents the plan for approval, unless `--auto-plan` or
`--milestone:N` is set (both stamp `plan_gate: "bypass"`). The FN gate always runs unattended
(`fn_gate: "bypass"`) and the PR is the review surface — see `../worktask/references/fn-gate.md` and
`../../commands/worktask.md` *EXECUTION MODEL (BINDING)*.

## Invocation

Launch via `/worktask "<task>"` (add `--secure` / `--full` for the 11-stage pipeline, `--emergency`
for the incident pipeline) or `Skill({skill:"igrsoft:worktask"})`. There are no size-specific message
prefixes — PL0 dynamic sizing selects which of the 9 stages actually run, dropping stages for low
complexity. See `../worktask/SKILL.md § Dynamic Worktask Sizing`.

The post-plan checkpoint is carried by `PL0.metadata.plan_gate`, default `"checkpoint"`.
`--auto-plan` and `--milestone:N` stamp `"bypass"`. On resume after interruption, this carrier
tells the orchestrator whether to re-enter the stage loop immediately (`bypass`) or stop for user
approval (`checkpoint`) — see `../worktask/references/resume.md § State → Action Table`.

## See also

- `../worktask/references/fn-gate.md` — FN gate is always bypassed (unattended finalization).
- `../../commands/worktask.md` — command entry point, *EXECUTION MODEL (BINDING)*, Options.
- `stage-codes.md` — stage code ↔ agent ↔ model table and pipeline definitions.
