# External-ticket-prefix fixture — OV-113 propagation

This fixture documents the contract exercised by the `07-ticket-extract`,
`07-ticket-no-match`, and `07-no-double-prefix` blocks of
`publish-pl-issue.sh --self-test`. The companion `07-state.json` carries
`facts.goal = "OV-113 Change navigation in settings"`.

## Summary

When `facts.goal` (or `workflow_id` as fallback) starts with the canonical
external-ticket pattern `^[A-Z][A-Z0-9]+-[0-9]+`, the helper extracts the
prefix and threads it through the published issue: title, label, and
state.json metadata.

## Requirements

- REQ-T1: Extraction regex is `^[A-Z][A-Z0-9]+-[0-9]+\b` anchored at start
  of the first non-empty line.
- REQ-T2: The published issue title starts with the prefix — already
  prefixed titles are left untouched (no `OV-113 OV-113 …` double-prefix).
- REQ-T3: A `ticket:<PREFIX>` label is added to the `--label` argument and
  auto-provisioned by `ensure_labels()` (purple `5319e7` colour).
- REQ-T4: `state.json:metadata.external_ticket = "<PREFIX>"` after a
  successful run; the success audit row includes `external_ticket: "<PREFIX>"`.

## Acceptance Criteria

- AC-T1: Given `facts.goal = "OV-113 Change navigation in settings"`,
  when helper runs, then `extract_external_ticket()` returns `"OV-113"`.
- AC-T2: Given the same goal, when the issue is created, then the title
  starts with `OV-113 ` and the `--label` argument includes
  `ticket:OV-113`.
- AC-T3: Given `facts.goal = "fix-publish-pl-issue-helper"` (no
  capital-leading prefix), when helper runs, then
  `extract_external_ticket()` returns empty and no `ticket:*` label is
  added.
- AC-T4: Given a title that *already* starts with `OV-113`, when the
  prefix-normaliser runs, then the title is left unchanged (no
  duplication).

## Scope

In: extraction regex, title-prefix normaliser, label injection, state
mutator (`write_state_external_ticket`), audit-row enrichment.
Out: cross-tracker prefixes (Jira `PROJ-123` is supported by the regex;
GitLab issue IIDs and other tracker shapes are out of scope this round).

## Complexity

4/50 (Low) — one regex + three threading points.

## Planned Stages

PL0 → DV0.
