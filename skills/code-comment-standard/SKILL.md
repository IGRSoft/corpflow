---
name: code-comment-standard
description: Compact source comment standard — comment the non-obvious WHY and contract, never the WHAT, history, or provenance. Use when writing or editing source comments or DocC (/// or //) in any context: worktask stages, direct edits, reviews, remediation.
effort: low
version: 0.1.0
---

# Code Comment Standard

> corpflow code-comment-standard: comment the non-obvious WHY and the contract only — never the WHAT, the history, or design provenance. Budgets: function doc 1–3 lines (one is the norm, only when the name isn't clear); var/const doc ≤1 sentence, only when needed; inline // = one short line per non-obvious literal; #Preview blocks are never commented; density well below 1:1 and ≤40% of a change's added lines (gated by dv-comment-density-gate.sh). Never write: multi-paragraph /// essays, before/after narration, Figma/hex provenance, caller enumeration, AC-/REQ- IDs, issue tags, prose restating the signature, QA runbooks, or a justification answering a DR finding. Rationale belongs in the PR / .context/development-N.md.

For the full budgets table, doc-block shapes, and BEFORE→AFTER examples, read `skills/shared/code-documentation.md` (plugin root: `${CLAUDE_PLUGIN_ROOT}` if available, else resolve per `skills/shared/plugin-root-resolution.md`).
