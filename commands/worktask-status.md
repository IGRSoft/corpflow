---
name: worktask-status
description: Show every task's current stage and status in one table, merging the local worktask ledger with active megatask groups; --watch polls it as a live board
argument-hint: '[--watch <seconds>] [--json] [--no-worktrees]'
allowed-tools: Bash(bash skills/worktask/scripts/status-view.sh:*), Read
model: haiku
related:
  - skills/worktask-status/SKILL.md
  - skills/worktask/scripts/status-view.sh
  - commands/context-status.md
---

# Worktask Status

Read-only status board over both worktask ledgers. Canon: `skills/worktask-status/SKILL.md`.

## Usage

```
/worktask-status
/worktask-status --watch 5
/worktask-status --json
/worktask-status --no-worktrees
```

## Behaviour

Run `bash skills/worktask/scripts/status-view.sh` with the arguments given and
show its output verbatim. Do not summarize the table away, and do not re-derive
any column by reading `state.json` yourself — the script is the single reader.

## Output

```
status-view: .context/state.json — worktask wt-demo   megatask groups: 1

TASK  STAGE  STATUS       AGENT                 BLOCKED BY  SOURCE
------------------------------------------------------------------
DV0   DV     in_progress  developer             —           state
QA0   QA     pending      —                     DV0         state
#42   —      blocked      —                     #41         milestone-9

read 2026-08-16T19:26:51Z · point-in-time snapshot, not live
```

`--watch` replaces the footer with the refresh time and poll interval and redraws
until Ctrl-C. Nothing pushes state changes, so that footer is the only signal
separating a live board from a frozen one — always leave it visible.

## Notes

- Exit `0` on any successful render, including "no active worktask here"; `2` on a usage error.
- `--watch` and `--json` are mutually exclusive.
- Wedged-stage triage is a different question — use `skills/worktask/scripts/stale-check.sh`.
