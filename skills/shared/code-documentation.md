---
name: code-comment-standard
description: Compact source-code comment standard for DV/DR/DC. Comment the non-obvious WHY and the contract, never the WHAT, the history, or external design provenance. Read on demand when writing, reviewing, or finalizing source comments.
effort: low
---

# Code Documentation Standard

Single source of truth for **source-code** comments (inline `//` and doc `///`/docstrings).
DV writes to it, DR flags violations against it, DC aligns its completion gate to it.

> Scope: this governs comments **inside source files**. Documentation *artifacts*
> (README, ADRs, API reference, DocC) follow `agents/technical-writer.md` — see Reconciliation.

## Principle

Comment the **WHY** when it is non-obvious; never the **WHAT**. Document the **contract**
(how to call it safely, units, invariants, gotchas), never the **history** of how the code
got here. Self-documenting code is the artifact; if a comment merely echoes the code, delete it.

The single source of truth for a fact lives where the fact lives: a color in the asset
catalog, a call-site list in the compiler/"find usages", a design in the design spec, a
rationale in the PR / `.context/development-N.md`. Do not transcribe any of them into a comment —
a copy drifts and lies the moment the source changes.

## Write vs. Do NOT write

| Write (in source) | Do NOT write (lives elsewhere) |
|---|---|
| One-line `///` summary stating the symbol's role/contract | Multi-paragraph `///` essays narrating the type |
| A non-obvious unit, invariant, or caller constraint (≤1 extra line) | Restating the signature/name/body in prose ("Config for the given selected state" over `config(isSelected:)`) |
| One short inline `//` on a genuinely non-obvious literal (the WHY) | Multi-line tutorials re-narrating each literal/stop the code already lists |
| `- Parameters/Returns/Throws` only when the effect is non-obvious | Design history, before/after, "the previous X", "the fix is…" |
| "shared material; do not duplicate" (centralization as one phrase) | Exhaustive call-site / caller enumeration (use "find usages") |
| | External-design narration: Figma board names, design-tool URLs, raw rgba/hex from mockups |
| | Verification / audit logs: "verified:", "resolves to", asset paths, per-channel byte dumps |

## Length budget

| Element | Budget |
|---|---|
| Function doc block | 1–3-line info block; one line is the norm; only when the name/signature isn't already clear |
| `- Parameters:` entries / Returns / Throws | One short-to-average sentence each; only when non-obvious — omit when the signature already says it |
| Var / constant doc | One average sentence, only when the name alone isn't clear; otherwise nothing |
| SwiftUI `#Preview` | Never commented — no doc line, no inline note, ever |
| Inline `//` rationale | One short trailing line per non-obvious literal |
| Longer discussion (multi-line) | Reserved strictly for a genuinely non-obvious **algorithm** — not for restating design, color, history, or callers |

Target comment-to-code density well below 1:1. A file that is ~half prose is over-documented.

## Doc block shape

No parameters — summary lines only (1–3):

```swift
/// The announcement is only posted if VoiceOver is currently running.
/// Second line only if needed.
```

With parameters — summary, one blank `///` line, then a grouped `- Parameters:` block with
one short sentence per entry (wrap to a continuation line only when unavoidable). A single
parameter may use `- Parameter x:` on one line instead:

```swift
/// The announcement is only posted if VoiceOver is currently running.
///
/// - Parameters:
///   - message: The message to announce.
///   - delay: Optional delay before announcing, so the announcement lands
///     after view transitions complete.
```

## Where rationale belongs instead

| Content | Home |
|---|---|
| Change summary, migration scope, design provenance link | **PR description** |
| Material/color/approach decision, rejected alternatives, DV verification evidence | **`.context/development-N.md` § Decisions** |
| Durable architectural decision | **ADR** (`igrsoft:arch-decision`) |
| Design source (Figma board, rgba/hex) | **design spec / `.context/designs`** (`igrsoft:design-specs`) |
| `AC-n` / `REQ-n` requirement traceability | **PR description / `.context/` stage artifacts** — never source comments |
| Resolved token value | **the asset catalog** (the single source of truth) — trust the semantic token |

## DO NOT

- DO NOT write multi-paragraph `///` essays where a one-line summary suffices.
- DO NOT narrate design history, before/after comparisons, or "the previous X"/"the fix is" in source.
- DO NOT reference external design sources (Figma board names, design-tool URLs, raw rgba/hex from mockups) in comments.
- DO NOT add verification logs, audit trails, "verified:"/"resolves to", or per-channel byte dumps.
- DO NOT enumerate call sites or callers — rely on the compiler and "find usages".
- DO NOT sprinkle issue/ticket IDs as provenance — tag a function only where that issue materially changed its business logic; the issue link belongs in the PR.
- DO NOT write acceptance-criteria or requirement IDs (`AC-2`, `REQ-5`) into source comments — traceability lives in the PR and `.context/` artifacts.
- DO NOT comment SwiftUI `#Preview` blocks — ever.
- DO NOT restate the symbol name, signature, or body in prose; if the comment echoes the code, delete it.

## Examples (BEFORE → AFTER)

### Property example

BEFORE — a 7-line doc block on the gradient property:

```swift
/// Top-lit lavender gradient stroked on every over-camera control (OV-140).
/// Stop 0 → Color.Border.stroke (#E6E2F3, Halo Stroke) at the top; stop 1 →
/// fully transparent at y=1.42 (below the bottom edge), so the upper rim reads as a
/// bright lavender specular and the lower edge fades out — matching the Figma's
/// light-source-from-above glass look.
/// The endPoint y: 1.42 deliberately extends past the unit rectangle so the fade is
/// gradual rather than sharp at the midpoint.
```

AFTER — one doc line + one inline note; hex, Figma ref, and per-stop walkthrough dropped
(the token and the code already carry them):

```swift
/// Top-lit halo gradient: Border.stroke at the rim, fading to clear past the bottom edge.
…
    .init(color: .clear, location: 1.0),
] // endPoint y: 1.42 — >1.0: extend fade past bottom edge
```

### Function example

BEFORE — a ~35-line `///` essay on a navigation helper (condensed here):

```swift
/// Opens `SkinAnalysisResultView` (the skin map) for the persisted analysis,
/// without running a camera session, reconstruction step, or YouCam network
/// call. Backs the Settings Skin Insights panel's VIEW SKIN MAP CTA (OV-153).
///
/// **Why this exists rather than the panel handing over its own data.** …
/// [… ~28 more lines: restart-hydration narrative, resolution order, guards]
```

AFTER — a 2-line info block + one `- Parameter` field; the why-narrative moves to the
PR / `development-N.md § Decisions`, and the issue tag goes (provenance, not a material
logic change):

```swift
/// Opens the skin map for a persisted analysis without running a camera
/// session, reconstruction, or network call.
/// - Parameter analysisID: The persisted analysis to display.
func openPersistedSkinMap(analysisID: AnalysisID) { … }
```

## Reconciliation

The `technical-writer` rules "always include examples / explain why, not just what" apply to
**documentation artifacts** (README, ADR, API reference, DocC) — those must teach and show
working examples. **This standard** governs **source-code inline + doc comments**, which stay
compact and contract-only. No conflict: different surfaces, different rules.
