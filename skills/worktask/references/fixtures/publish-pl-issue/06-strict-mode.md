# Strict-mode fixture — STRICT=1 + operational failure → exit 1

This fixture documents the contract exercised by the `06-strict-mode` block of
`publish-pl-issue.sh --self-test`. The self-test mocks `gh` such that every
`label create` and the subsequent `issue create` fail with a label-related
stderr blob ("could not add label: 'workflow' not found in repository").

## Summary

When `STRICT=1` (or `metadata.gh_issue.strict: true` in state.json), the
helper MUST exit `1` on operational failure instead of degrading to
`result: "deferred"` with `exit 0`. This makes the workflow block until the
underlying issue (missing repo scopes, missing labels with read-only token,
network failure, etc.) is resolved.

## Requirements

- REQ-S1: Strict mode is opt-in via either `--strict` CLI flag or
  `metadata.gh_issue.strict: true` on state.json. Default (`STRICT=0`)
  preserves the legacy non-blocking behaviour (fixtures 01–05).
- REQ-S2: On `gh issue create` failure under strict mode, helper exits `1`
  and writes one audit row with `result: "failed"` and the classified
  reason (one of `label_create_failed`, `gh_api_error`, `auth_missing`,
  `permission_denied`, `repo_not_found`, `gh_timeout`, `network_error`).
- REQ-S3: When labels were dropped during `ensure_labels()`, the failure
  audit row carries `metadata.labels_dropped: [<names>]`.

## Acceptance Criteria

- AC-S1: Given `STRICT=1` and a mocked `gh` that fails every `label create`
  plus `issue create`, when the helper runs, then exit code is `1`,
  `audit.jsonl` carries `result: "failed"`, and `metadata.reason` is
  `label_create_failed` (or `gh_api_error` when labels were not dropped
  but the API call failed for another reason).
- AC-S2: Given `STRICT=0` (default) and the same failure scenario, when
  the helper runs, then exit code is `0` and the audit row carries
  `result: "deferred"` — preserving fixtures 01–05 behaviour.

## Scope

In: strict-mode toggle (CLI + state.json), audit-row `result: "failed"`,
exit-code 1 on operational failure when strict.
Out: re-architecting the audit schema; changing the default behaviour.

## Complexity

3/50 (Low) — single env-var read + one new audit-row branch.

## Planned Stages

PL0 → DV0 (this is the very plan that adds the strict-mode contract).
