---
name: worktask-status
description: Use for "what is running right now", stage/blocker inspection, or a polled live board. Show every task's current stage and status in one table — the local `.context/state.json` ledger merged with active `.worktrees/*` megatask groups.
effort: low
version: 0.2.0
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

An orchestrator issue records no stage of its own, so an issue's stage comes from its
per-issue ledger: the in-progress task if any, else the furthest completed one. A
missing nested ledger renders `—`, never a dropped row.

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

Nothing broadcasts state changes, so `--watch` is a timer. It always prints its
refresh time and interval — a wedged redraw must stay distinguishable from a board
where nothing is happening. A single-shot run is a snapshot, as its footer says.

## Read-only

The script opens nothing for writing: no ledger, no audit row, no log — `--watch`
included. `state-patch.sh` writes `state.json` concurrently, so a poll will
eventually read mid-rename; that degrades to a `not readable right now` notice on
the affected source while every other row still renders.

## Related, not overlapping

- **`stale-check.sh`** answers *is anything wedged*, reconciling `in_progress` tasks
  against live agent sessions. This skill answers *what is where* — no liveness claim.
- **`/context-status`** reports context-window utilization, not task status.
- **`/cost-report`**, **`/test-report`** cover historical and trend reporting.
