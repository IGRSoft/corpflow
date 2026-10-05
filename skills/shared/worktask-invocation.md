---
name: worktask-invocation
---

# Worktask Invocation

How a worktask is launched, and the rule that it goes through its entry point.

## BLOCKING

When the user asks to run a worktask, the first action is launching it through its entry point:
`/worktask` (`/worktask --emergency` for the incident pipeline) or `Skill({skill:"corpflow:worktask"})`.
No file reads, codebase exploration or agent delegation before that launch; handling the request
inline as a freeform instruction does not count as running it.

## Invocation

`/worktask "<task>"` runs the 9-stage pipeline; `--secure` / `--full` select the 11-stage one,
`--emergency` the incident pipeline. There are no size-specific prefixes: PL0 dynamic sizing drops
the stages a low-complexity task does not need (`../worktask/SKILL.md § Dynamic Worktask Sizing`).
Every worktask is worktree-isolated, so the PR is the review surface.

## Gate carriers

Three independent carriers on `PL0.metadata`, each honored on resume
(`../worktask/references/resume.md § State → Action Table`):

| Carrier | Default | Alternate |
|---|---|---|
| `plan_gate` | `checkpoint`: stop after PL0 for plan approval | `bypass`: `--auto=[plan]`, `--emergency` |
| `fn_gate` | `checkpoint`: stop before the FN delegation for approval (`../worktask/references/fn-gate.md`) | `bypass`: `--auto=[finalization]`, `--emergency` |
| `decision_gate` | `user`: the user answers open questions | `auto`: `--auto=[decision]` |

`--auto` takes any subset, e.g. `--auto=[plan, decision, finalization]`. `--auto=[plan]` leaves the
FN gate in place, and `decision_gate: auto` bypasses neither gate; escalation-class questions always
go to the user. `/megatask` stamps the carriers directly on each per-issue PL0.

## See also

- `../../commands/worktask.md`: command entry point, the canonical *Execution model* carrier
  table, § Step A.4 and Options.
- `../worktask/SKILL.md § Auto-Decision Delegation (decision_gate)`: decision delegate mechanics.
- `stage-codes.md`: stage code ↔ agent ↔ model table and pipeline definitions.
