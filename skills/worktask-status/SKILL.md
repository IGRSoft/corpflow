---
name: worktask-status
description: Show every task's current stage and status in one table — the local `.context/state.json` ledger merged with active `.worktrees/*` megatask groups. Use for "what is running right now", stage/blocker inspection, or a polled live board.
effort: low
version: 0.1.0
related:
  - ../worktask/scripts/status-view.sh
  - ../worktask/scripts/stale-check.sh
  - ../worktask/SKILL.md
  - ../megatask/SKILL.md
  - ../shared/state-ledger.md
---

# Worktask status board

One table answering *what is every task doing right now*, across both ledgers.

```bash
bash skills/worktask/scripts/status-view.sh              # snapshot
bash skills/worktask/scripts/status-view.sh --watch 5    # polled board
bash skills/worktask/scripts/status-view.sh --json       # machine-readable
```

## What it reads

| Source | Shape | Contributes |
|---|---|---|
| `.context/state.json` | `tasks{}` keyed by ledger id | `DV0`, `QA0` … rows, `source: state` |
| `.worktrees/<group>/orchestrator.json` | `issues[]` keyed by issue number | `#41` rows, `source: <group>` |
| `.worktrees/<group>/<issue#>/.context/state.json` | nested ledger | the **stage** column for an issue row |

An orchestrator issue records no stage of its own, so an issue's stage is read
from its own per-issue ledger — in-progress task if any, else the furthest
completed one. Absent nested ledger renders `—`, never a dropped row.

## Options

| Flag | Effect |
|---|---|
| `--state <path>` / `--context <dir>` | Point at a ledger elsewhere |
| `--root <dir>` | Repo root to scan for `.worktrees/` |
| `--no-worktrees` | Local ledger only; skip the megatask merge |
| `--json` | Emit rows as JSON instead of a table |
| `--watch <N>` | Redraw every N seconds until Ctrl-C |

Exit `0` on any successful render (an empty board included); `2` on a usage error.

## Polled, not pushed

Nothing in the worktask system broadcasts state changes, so `--watch` is a timer.
It always prints its refresh time and interval — a wedged redraw must stay
distinguishable from a board where nothing is happening. Treat a single-shot run
as a snapshot, which is what its footer says.

## Read-only

The script opens nothing for writing: no ledger, no audit row, no log. That holds
under `--watch` too. `state-patch.sh` writes `state.json` concurrently, so a poll
will eventually read mid-rename; that degrades to a `not readable right now`
notice on the affected source while every other row still renders.

## Related, not overlapping

- **`stale-check.sh`** answers *is anything wedged* by reconciling `in_progress`
  tasks against live agent sessions. This skill answers *what is where*; it makes
  no liveness claim.
- **`/context-status`** reports context-window utilization, not task status.
- **`/cost-report`**, **`/test-report`** cover historical and trend reporting.
