---
name: gh-issue-dedup
description: Use when the PL stage publishes a plan, when a repeat `/worktask` runs in an existing `.context/`, or before any `gh issue create` / `publish-pl-issue.sh` call. Enforce one GitHub issue per `.context/` per worktask — never open a duplicate.
effort: low
version: 0.3.0
related:
  - ../worktask/scripts/publish-pl-issue.sh
  - ../worktask/scripts/preflight-issue-scan.sh
  - ../worktask/SKILL.md
  - ../shared/state-ledger.md
  - ../task-folder-organization/SKILL.md
---

# GitHub issue dedup (one `.context/` ↔ one issue)

## The invariant

Each `.context/` is tracked by exactly **one** GitHub issue for its whole life. The first
worktask run opens that issue; every later run in the same `.context/` **comments on it** with a
plan summary rather than opening a duplicate. This keeps a feature's planning history on a single
reviewable thread instead of scattering a new issue per re-plan.

## Why state.json alone can't enforce this

`state.json:metadata.github_issue_url` is not a sufficient dedupe key: `commands/worktask.md`
**re-seeds `state.json` from scratch on every fresh `/worktask`** and the seed writes no `metadata`,
so that URL is wiped on each new `run_index` — it guards a *resume of the same run* only. Hence a
persistent, run-independent anchor plus a comment path.

## The anchor: `.context/gh-issue.json`

Written next to `state.json`, in the "shared across runs" artifact set (never re-seeded). Minimal
schema:

```json
{
  "version": 1,
  "url": "https://github.com/<owner>/<repo>/issues/<n>",
  "number": 42,
  "created_run_index": 0,
  "created_worktask_id": "<worktask_id>",
  "created_at": "<ISO-8601>",
  "last_commented_run_index": 0
}
```

`created_run_index` is the run that opened the issue; `last_commented_run_index` advances each time
a later run posts its follow-up comment.

## Two tiers: advisory pre-flight, then authoritative anchor

The anchor only exists once a `.context/` does, so it protects **re-runs** — never the FIRST run of
work someone already filed under different wording. That gap is covered one level up at `/worktask`
entry by `skills/worktask/scripts/preflight-issue-scan.sh` (`commands/worktask.md § Step 2a`):
before `.context/` is created it scores keyword overlap against open-issue titles and offers the
candidates to the **user**, who may bind the new context to an existing issue.

The tiers never blur. The pre-flight is advisory, human-confirmed, and writes nothing itself; a
user who reuses an issue gets an anchor with `created_run_index: -1` — the same "predates this
context" value a recovered search hit uses — so the publish step comments rather than creating.
No fuzzy match ever auto-binds.

## Resolution order (what counts as "already exists")

`publish-pl-issue.sh` resolves the canonical issue in this order, stopping at the first hit:

1. **`.context/gh-issue.json` anchor** — authoritative, local, run-independent.
2. **`state.json:metadata.github_issue_url`** — only present within the *same* run (resume).
3. **GitHub-side search** — `gh issue list --state open --search "<title> in:title"`, accepted
   **only on an exact normalized-title match with a single result**; ambiguous / multi-hit results
   are refused, so a fresh context is never captured by an unrelated same-worded issue. A hit
   backfills the anchor so later runs resolve locally. Disable with `GH_ISSUE_SEARCH=0`.

## The decision

- **No issue resolves** → create it, then write the anchor (and `state.json` URL).
- **Resolves, created in THIS run** (`created_run_index >= run_index`, or same-run state URL) →
  defer `already_published`. No create, no comment.
- **Resolves, created in an EARLIER run** (`created_run_index < run_index`, or a search hit) →
  post one marker-deduped follow-up comment (`<!-- worktask-plan:<worktask_id>:<run_index> -->`)
  carrying the sanitized plan summary, then advance `last_commented_run_index`. No new issue.

Comment idempotency is a network-checked marker (mirrors
`attach-visual-evidence.sh:issue_has_marker`): if this run already commented, it defers
`comment_already_present` rather than double-posting.

## Precedence with existing guards (unchanged)

Order in `publish-pl-issue.sh`: `--no-gh-issue` opt-out → **this dedup (create vs comment)** →
milestone-mode skip → `gh` present / auth / remote. Opt-out and **milestone-mode still win** —
under `/megatask` the parent milestone issue is canonical, so per-issue runs neither create nor
comment.

## Enforcement lives in the helper

Implemented in `skills/worktask/scripts/publish-pl-issue.sh` (`resolve_context_issue_local`,
`resolve_context_issue_search`, `write_context_issue`, `bump_anchor_commented`, and the
create-vs-comment branch at the publish step) — the single choke point the orchestrator invokes;
this skill is its canonical description. Covered by `tests/shell/worktask/gh-issue-dedup.bats`, the
advisory tier by `tests/shell/worktask/preflight-issue-scan.bats`. Do not add a second
`gh issue create` path elsewhere in the worktask flow — route through the helper so the invariant
holds.
