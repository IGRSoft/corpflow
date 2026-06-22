---
name: legacy-fallback-f1
description: Canonical explanation of the F1 legacy context_files fallback path. Use when documenting or debugging worktask handoff when state.json is absent.
---

# Legacy `context_files` / F1 Fallback

The preferred handoff mode is anchor-based: a stage reads `.context/state.json`
plus the anchors named in `metadata.context_refs` (≥30% input-token reduction,
cache-friendly preamble).

**F1 fallback**: when `.context/state.json` is absent (or `context_refs` is
missing), stages fall back to reading `metadata.context_files` in full — the
*legacy mode*. There is no cache-friendly preamble in this mode, so the
prompt-cache benefit collapses (silent cache degradation, surfaced via the
`#f1-telemetry` log consumed by `/cost-report`).

This path remains **supported for backward compatibility** (AC-16/AC-17): a
worktask MUST complete even when state.json is absent. `context_refs` wins when
state.json is present; `context_files` is the safety net.

Canonical operational specs (not duplicated here):
the F1..F4 matrix lives in `skills/worktask/references/handoff-protocol.md#fallback-paths`;
the F1 telemetry snippet lives in `skills/shared/stage-contracts.md#f1-telemetry`.
