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

### Entry point and gates

`/worktask` (or `Skill({skill:"igrsoft:worktask"})`) is the canonical entry point. There are two human
checkpoints. After PL0 it STOPs at the PL gate and presents the plan for approval, unless `--auto=[plan]`
(legacy alias `--auto-plan`) or `--emergency` is set (both stamp `plan_gate: "bypass"`). Then, immediately before the
FN delegation, it STOPs at the FN gate and presents a pre-FN summary for finalization approval, unless
`--auto=[finalization]` (legacy alias `--auto-finalization`) or `--emergency` is set (both stamp `fn_gate: "bypass"`). A batch orchestrator
(`/megatask`) stamps both `plan_gate` and `fn_gate` `"bypass"` directly on each per-issue PL0. The PR
is the review surface — see `../worktask/references/fn-gate.md` and `../../commands/worktask.md`
*EXECUTION MODEL (BINDING)*.

#### The gate-orthogonal `decision` value

A third `--auto` value — `--auto=[decision]`, stamping `decision_gate: "auto"` — delegates PL0's
open questions to a Fable-model decision pass instead of the user (escalation-class questions still
stop for a human). `--auto` takes any subset as an array: `--auto=[plan, decision, finalization]`.

## Invocation

Launch via `/worktask "<task>"` (add `--secure` / `--full` for the 11-stage pipeline, `--emergency`
for the incident pipeline) or `Skill({skill:"igrsoft:worktask"})`. There are no size-specific message
prefixes — PL0 dynamic sizing selects which of the 9 stages actually run, dropping stages for low
complexity. See `../worktask/SKILL.md § Dynamic Worktask Sizing`.

### PL gate carrier (plan_gate)

The post-plan checkpoint is carried by `PL0.metadata.plan_gate`, default `"checkpoint"`.
`--auto=[plan]` (legacy `--auto-plan`) and `--emergency` stamp `"bypass"` (a `/megatask` batch run stamps it per-issue). On resume after interruption, this carrier
tells the orchestrator whether to re-enter the stage loop immediately (`bypass`) or stop for user
approval (`checkpoint`) — see `../worktask/references/resume.md § State → Action Table`.

### Decision gate carrier (decision_gate)

WHO answers PL0's `open_questions[]` is carried by `PL0.metadata.decision_gate`, default `"user"`
(questions surface at the plan gate). `--auto=[decision]` stamps `"auto"`: the orchestrator
re-dispatches the PM as a decision delegate on the Fable model, which decides each question
(default-biased) and applies the amendments to the plan's existing mandatory anchors in one batch
pass; the orchestrator then merges the calls into `state.json facts.decisions[]` marked
`(auto-decided)` and drops the resolved `facts.open_questions[]` entries — no new plan anchor is
created. Escalation-class questions (irreversible,
scope-expanding, security-posture, spend) are never auto-decided — they stop for the user even
under `plan_gate: "bypass"`. This carrier bypasses neither gate. Canon:
`../../commands/worktask.md § Step A.4`; mechanism: `../worktask/SKILL.md § Auto-Decision
Delegation (decision_gate)`.

### FN gate carrier (fn_gate)

The pre-finalization checkpoint is carried by `PL0.metadata.fn_gate`, default `"checkpoint"`.
`--auto=[finalization]` (legacy `--auto-finalization`) and `--emergency` stamp `"bypass"` (a `/megatask` batch run stamps it per-issue; note: `--auto=[plan]` does NOT
bypass the FN gate — it is orthogonal). On the `checkpoint` path the orchestrator STOPs before the FN
`Task()` delegation, presents the pre-FN summary, and delegates FN (commit/push/PR) only on
`AskUserQuestion` approval; on `bypass` it finalizes unattended. All three carriers live on PL0 and resume
logic honors each independently — see `../worktask/references/fn-gate.md` and
`../worktask/references/resume.md § State → Action Table`.

## See also

- `../worktask/references/fn-gate.md` — FN gate (default `checkpoint`); bypassed by `--auto=[finalization]` / `--emergency`.
- `../../commands/worktask.md` — command entry point, *EXECUTION MODEL (BINDING)*, Options.
- `stage-codes.md` — stage code ↔ agent ↔ model table and pipeline definitions.
