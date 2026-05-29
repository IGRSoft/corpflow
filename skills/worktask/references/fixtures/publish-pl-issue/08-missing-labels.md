# Missing-labels fixture — first-run repo, all 4 labels auto-provisioned

This fixture documents the contract exercised by the `08-missing-labels`
and `08-idempotent` blocks of `publish-pl-issue.sh --self-test`. The
self-test mocks `gh label list` to return an empty list (no existing
labels) and `gh label create` to succeed.

## Summary

On the first run against a pristine repo (no workflow labels exist), the
helper MUST auto-create each canonical label (`workflow`,
`planning-approved`, `complexity:<tier>`, optionally `ticket:<PREFIX>`)
before invoking `gh issue create`. A second run must no-op cleanly
(idempotency) because all labels now exist.

## Requirements

- REQ-L1: `ensure_labels()` queries `gh label list --json name --jq '.[].name'`
  once per invocation; for each requested label not in the existing set, it
  calls `gh label create <name> --color <hex> --description <text>`.
- REQ-L2: Colour and description per spec §4.1: `workflow` blue (`0366d6`),
  `planning-approved` green (`0e8a16`), `complexity:low/moderate/medium`
  amber/pale-green, `complexity:high` deep-orange, `complexity:critical`
  red, `ticket:*` purple (`5319e7`).
- REQ-L3: `ensure_labels()` is idempotent — a second invocation with the
  same labels MUST issue zero `gh label create` calls.
- REQ-L4: If `gh label create` fails for a label, the helper appends that
  label name to `DROPPED_LABELS` (space-separated) and drops it from the
  `--label` argument passed to `gh issue create`. The success audit row
  carries `metadata.labels_dropped: [<names>]` when non-empty.

## Acceptance Criteria

- AC-L1: Given a fresh repo with no labels, when the helper runs
  end-to-end against a mocked `gh` that succeeds on every `label create`,
  then `DROPPED_LABELS` is empty and the resulting audit row has
  `result: "ok"`.
- AC-L2: Given the same labels now exist (mocked `gh label list` returns
  all of them), when `ensure_labels()` runs again, then no `gh label
  create` calls are issued — confirmed indirectly by the helper not
  populating `DROPPED_LABELS` even though the mock `gh label create`
  would fail with "label already exists".

## Scope

In: `ensure_labels()` function, colour/description registry, dropped-label
tracking, audit-row `labels_dropped` enrichment.
Out: custom label taxonomies (deferred to a future
`metadata.gh_issue.labels` override).

## Complexity

6/50 (Low) — straight-line bash loop over a static label list.

## Planned Stages

PL0 → DV0.
