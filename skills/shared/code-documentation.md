---
name: code-comment-standard
description: Compact source-code comment standard for DV/DR/DC. Comment the non-obvious WHY and the contract, never the WHAT, the history, or external design provenance. Read on demand when writing, reviewing, or finalizing source comments.
effort: low
---

# Code Documentation Standard

Single source of truth for **source-code** comments (inline `//` and doc `///`/docstrings).
DV writes to it, DR flags violations against it, DC aligns its completion gate to it.

> Scope: comments **inside source files**. Documentation *artifacts* (README, ADRs, API
> reference, DocC pages) follow `agents/technical-writer.md` — see Reconciliation.

## Principle

Comment the **WHY** when it is non-obvious; never the **WHAT**. Document the **contract**
(how to call it safely, units, invariants, gotchas), never the **history** of how the code
got here. If a comment echoes the code, delete it.

A fact's single source of truth lives where the fact lives: a color in the asset catalog, a
call-site list in "find usages", a design in the design spec, a rationale in the PR /
`.context/development-N.md`. A comment that transcribes one is a copy that drifts and lies
the moment the source changes.

## Write in source

- One-line `///` summary stating the symbol's role/contract.
- A non-obvious unit, invariant, or caller constraint — ≤1 extra line.
- One short inline `//` carrying the WHY of a genuinely non-obvious literal.
- `- Parameters/Returns/Throws` only when the effect is non-obvious.
- Centralization as one phrase: "shared material; do not duplicate".

## DO NOT write

Every entry is a review finding, not a preference.

- Multi-paragraph `///` essays where a one-line summary suffices.
- Restating the signature, name, or body in prose ("Config for the given selected state"
  over `config(isSelected:)`).
- Multi-line tutorials re-narrating each literal or stop the code already lists.
- Design history, before/after, "the previous X", "the fix is…".
- Call-site or caller enumeration — rely on the compiler and "find usages".
- External design sources: Figma board names, design-tool URLs, raw rgba/hex from mockups.
- Verification/audit logs: "verified:", "resolves to", asset paths, per-channel byte dumps.
- Issue/ticket IDs as provenance — tag a function only where that issue materially changed
  its business logic; the link belongs in the PR.
- Acceptance-criteria or requirement IDs (`AC-2`, `REQ-5`).
- Any comment on a preview/story block, in any framework, ever (see Length budget).

## Length budget

| Element | Budget |
|---|---|
| Function doc block | 1–3-line info block; one line is the norm; only when the name/signature isn't already clear |
| `- Parameters:` / Returns / Throws entries | One short sentence each; omit when the signature already says it |
| Var / constant doc | One sentence, only when the name alone isn't clear; otherwise nothing |
| Preview / story block — SwiftUI `#Preview`, Compose `@Preview`, Storybook story, snapshot fixture | Never commented — no doc line, no inline note, ever |
| Inline `//` rationale | One short trailing line per non-obvious literal |
| Longer multi-line discussion | Strictly for a genuinely non-obvious **algorithm** — never for design, color, history, or callers |

### Density gate

Target comment-to-code density well below 1:1. `dv-comment-density-gate.sh` gates a
change's *added* lines on two signals: ≤40% may sit in comment blocks longer than the
3-line budget above, and ≤60% may be comment overall. One compliant one-line `///` per
declaration never trips it — a list of short declarations is structurally near 1:1 while
still on budget. A file that is ~half prose is over-documented.

## Doc block shape

The budget is grammar-independent — DocC `///`, TSDoc/JSDoc `@param`, KDoc `@param`,
Python docstring `Args:`, Doxygen `\param`: one short sentence per entry, omitted entirely
when the signature already says it. DocC spells the canonical shape:

```swift
/// The announcement is only posted if VoiceOver is currently running.
///
/// - Parameters:
///   - message: The message to announce.
///   - delay: Optional delay before announcing, so the announcement lands
///     after view transitions complete.
```

Without parameters the summary lines alone (1–3) are the whole block; a single parameter
may use one-line `- Parameter x:` instead of the grouped block.

### Shell

Shell has no doc-comment syntax, so the budget lands on two blocks: a script header of one
purpose line plus the invocation contract (prerequisites, exit behaviour, re-run safety),
and a one-line WHY above a non-obvious literal. The header counts toward density like any
other comment — keep it to the contract, not a changelog:

```bash
#!/usr/bin/env bash
# prune-artifacts — drop build artifacts past the retention window.
#
# Requires: find, date. Exits non-zero when the artifact root is absent.
# Safe to re-run; deletion is idempotent.

# Two retries: the artifact store 502s on a cold cache.
fetch_manifest() { curl --retry 2 -fsSL "$1"; }
```

## Where rationale belongs instead

| Content | Home |
|---|---|
| Change summary, migration scope, design provenance link | **PR description** |
| Material/color/approach decision, rejected alternatives, DV verification evidence | **`.context/development-N.md` § Decisions** |
| Durable architectural decision | **ADR** (`corpflow:arch-decision`) |
| Design source (Figma board, rgba/hex) | **design spec / `.context/designs`** (`corpflow:design-specs`) |
| `AC-n` / `REQ-n` traceability | **PR / `.context/` stage artifacts** — never source comments |
| Resolved token value | **the asset catalog** — trust the semantic token |
| Answer to a DR/SR finding; threshold derivation; calibration data | **`.context/development-N.md`** — source keeps a one-line WHY at most |
| QA runbook ("if QA measures X, raise to Y") | **`docs/` runbook / QA checklist** |

## Canonical example (BEFORE → AFTER)

BEFORE — a ~35-line `///` essay on a navigation helper (condensed):

```swift
/// Opens `SkinAnalysisResultView` (the skin map) for the persisted analysis,
/// without running a camera session, reconstruction step, or YouCam network
/// call. Backs the Settings Skin Insights panel's VIEW SKIN MAP CTA (OV-153).
///
/// **Why this exists rather than the panel handing over its own data.** …
/// [… ~28 more lines: restart-hydration narrative, resolution order, guards]
```

AFTER — 2-line info block plus one `- Parameter`; the why-narrative moves to the PR /
`development-N.md § Decisions`, and the issue tag goes (provenance, not a logic change):

```swift
/// Opens the skin map for a persisted analysis without running a camera
/// session, reconstruction, or network call.
/// - Parameter analysisID: The persisted analysis to display.
func openPersistedSkinMap(analysisID: AnalysisID) { … }
```

### The same failure in other grammars

Identical shape, identical fix — the bulk always moves to the PR or the run artifact:

- **Swift property**: a 7-line block narrating every gradient stop, its hex, and the Figma
  look → one `///` line ("Top-lit halo gradient: Border.stroke at the rim, fading to clear
  past the bottom edge") plus `// endPoint y: 1.42 — >1.0: extend fade past bottom edge`.
- **TSDoc**: `useCartTotal (added in PR #812, refactored from the old getTotal helper)` +
  `@param items The cart items.` → `/** Total in minor units; excludes shipping, quoted
  per-address at checkout. */`.
- **Shell**: 4 lines citing `DR-3 / AC-6`, the reviewer exchange, and the staging
  measurement above `MAX_RETRIES=3` → `# Past 3 the retries never recovered — they only
  widened the partial-upload window.`

## Reconciliation

`technical-writer`'s "always include examples / explain why, not just what" governs
**documentation artifacts** (README, ADR, API reference, DocC pages), which must teach and
show working examples. This standard governs **source-code comments**, which stay compact
and contract-only. Different surfaces, different rules — no conflict.
