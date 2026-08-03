No frontmatter, no H1, no summary or problem anchor — every prose rank of the
title chain is empty, so the chain must reach its last rank (the worktask slug)
and record that degradation instead of publishing it silently.

## Requirements

- REQ-1: The chain still resolves a non-empty title.
- REQ-2: The run exits 0 and publishes.

## Acceptance Criteria

- AC-1 (REQ-1): Given no prose source, When the helper runs, Then the title is
  the worktask id.
- AC-2 (REQ-2): Given the same run, Then one audit row records the degradation.

## Scope

Title resolution only. The body sections are unaffected by this fixture.

## Complexity

Low (Low) — a single fallback rank.
