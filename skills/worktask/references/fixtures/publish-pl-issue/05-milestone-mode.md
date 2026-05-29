# Milestone-mode fixture — body content irrelevant

This fixture exists to satisfy --plan resolution while the helper short-circuits
on the milestone-mode guard (Guard 2.5) before sanitisation runs. The companion
state-json mock `05-state.json` carries `metadata.milestone: 7`.

## Summary

When the worktask runs under `--milestone:N`, the helper exits 0 immediately
with `result: "deferred"`, `reason: "milestone_mode"` — no `gh issue create`,
no `gh issue comment`, no API call of any kind.

## Requirements

- REQ-M1: Milestone-mode is detected via `state.json:metadata.milestone`
  non-empty, `workspace.json` presence, or `MILESTONE_MODE=1` env override.
- REQ-M2: Helper short-circuits before any sanitiser/gh invocation.
- REQ-M3: Audit row carries `reason: "milestone_mode"` and the canonical
  dedupe-key shape.

## Acceptance Criteria

- AC-M1: Running the helper with `MILESTONE_MODE=1` produces exactly one
  audit row with `result: "deferred"`, `metadata.reason: "milestone_mode"`.
- AC-M2: No `published_url=` line is emitted on stdout.
- AC-M3: No `gh` binary invocation occurs (verifiable via PATH-shim trace).

## Scope

In: detector, audit row schema, self-test coverage.
Out: changes to the publish path itself (which still creates issues when
milestone mode is absent).

## Complexity

5/50 (Low) — pure short-circuit guard with three OR-ed detection signals.
