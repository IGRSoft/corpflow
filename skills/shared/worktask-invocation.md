---
name: worktask-invocation
---

# Worktask Invocation

Single source of truth for how a worktask is launched and its invocation rule.

## BLOCKING

> When a user asks to run a worktask — via the `/worktask` command (or `/worktask --emergency` for the
> incident pipeline) or by invoking `Skill({skill:"corpflow:worktask"})` — the VERY FIRST action MUST
> be to launch the worktask pipeline via that canonical entry point. No file reads, no codebase
> exploration, and no agent delegation before that launch. Handling the request as a freeform
> instruction inline is a violation.

## Invocation

`/worktask "<task>"` (or `Skill({skill:"corpflow:worktask"})`) is the canonical entry point; add
`--secure` / `--full` for the 11-stage pipeline, `--emergency` for the incident pipeline. There are no
size-specific message prefixes — PL0 dynamic sizing selects which of the 9 stages actually run,
dropping stages for low complexity (`../worktask/SKILL.md § Dynamic Worktask Sizing`). The PR is the
review surface — see `../../commands/worktask.md` *EXECUTION MODEL (BINDING)*.

## Gate carriers

Two human checkpoints (PL gate after PL0, FN gate immediately before the FN delegation) plus one
gate-orthogonal decision carrier. All three live on `PL0.metadata`, and resume logic honors each
independently — see `../worktask/references/resume.md § State → Action Table`. `--auto` takes any
subset as an array: `--auto=[plan, decision, finalization]`; note `--auto=[plan]` does NOT bypass the
FN gate. A batch orchestrator (`/megatask`) stamps `plan_gate` and `fn_gate` `"bypass"` directly on
each per-issue PL0.

### Carrier table

| Carrier | Default | Stamped by | Effect |
|---|---|---|---|
| `plan_gate` | `"checkpoint"` | `--auto=[plan]`, `--emergency` → `"bypass"` | After PL0, STOP and present the plan for approval. On resume, tells the orchestrator to re-enter the stage loop immediately (`bypass`) or stop for approval (`checkpoint`). |
| `fn_gate` | `"checkpoint"` | `--auto=[finalization]`, `--emergency` → `"bypass"` | STOP before the FN `Task()` delegation, present the pre-FN summary, and delegate FN (commit/push/PR) only on `AskUserQuestion` approval; `bypass` finalizes unattended. Detail: `../worktask/references/fn-gate.md`. |
| `decision_gate` | `"user"` | `--auto=[decision]` → `"auto"` | WHO answers PL0's `open_questions[]`: the user at the plan gate, or a Fable-model decision pass. Bypasses neither gate. |

### Decision gate carrier (decision_gate)

Under `"auto"` the orchestrator re-dispatches the PM as a decision delegate on the Fable model, which
decides each question (default-biased) and applies the amendments to the plan's existing mandatory
anchors in one batch pass; the orchestrator then merges the calls into `state.json facts.decisions[]`
marked `(auto-decided)` and drops the resolved `facts.open_questions[]` entries — no new plan anchor
is created. Escalation-class questions (irreversible, scope-expanding, security-posture, spend) are
never auto-decided — they stop for the user even under `plan_gate: "bypass"`. Canon:
`../../commands/worktask.md § Step A.4`; mechanism: `../worktask/SKILL.md § Auto-Decision Delegation
(decision_gate)`.

## See also

- `../../commands/worktask.md` — command entry point, *EXECUTION MODEL (BINDING)*, Options.
- `stage-codes.md` — stage code ↔ agent ↔ model table and pipeline definitions.
