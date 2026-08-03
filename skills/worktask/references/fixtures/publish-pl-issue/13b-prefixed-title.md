---
title: OV-164 Product list images are blinking before rendering
issue: OV-164
stage: PL
---

# Product list images are blinking before rendering

This fixture exercises the title/summary fallback chain of
`publish-pl-issue.sh --self-test` (`13-*` blocks). Its companion state.json
deliberately carries NO `facts.goal`, which is the condition that produced the
garbage title on issue #375.

## Summary

Product images flash a placeholder frame before the decoded bitmap is handed to
the view, so the catalog visibly blinks on every scroll into a new row.

## Requirements

- REQ-1: The catalog shows no placeholder flash once an image is cached.
- REQ-2: A cache miss shows a stable placeholder, never an alternating one.

## Acceptance Criteria

- AC-1 (REQ-1): Given a warm cache, When the catalog scrolls, Then no frame
  shows a placeholder for an image that has already decoded.
- AC-2 (REQ-2): Given a cold cache, When a row appears, Then the placeholder
  renders once and is replaced exactly once.

## Scope

Catalog list rendering and the image cache handoff. Out of scope: the network
fetch layer and the detail screen.

## Complexity

Moderate (Medium) — one rendering path, two call sites, existing test coverage.
