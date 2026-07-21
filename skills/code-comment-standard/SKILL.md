---
name: code-comment-standard
description: Compact source-code comment standard — comment the non-obvious WHY and the contract, never the WHAT, history, or design provenance. Use whenever writing or editing source-code comments or DocC (/// or //) in ANY context — worktask stages AND direct edits outside a worktask, reviews, and remediation passes.
effort: low
version: 0.1.0
---

# Code Comment Standard

> igrsoft code-comment-standard: comment the non-obvious WHY and the contract only — never the WHAT, the history, or design provenance. Budgets: function doc 1–3 lines (one is the norm, only when the name isn't clear); var/const doc ≤1 sentence, only when needed; inline // = one short line per non-obvious literal; #Preview blocks are never commented; comment-to-code density well below 1:1. Never write: multi-paragraph /// essays, before/after or "the previous X" narration, Figma/hex provenance, caller enumeration, AC-/REQ- IDs, issue tags as provenance, prose restating the signature. Rationale belongs in the PR / .context/development-N.md, not in source.

For the full budgets table, doc-block shapes, and BEFORE→AFTER examples, read `${CLAUDE_PLUGIN_ROOT}/skills/shared/code-documentation.md`.
