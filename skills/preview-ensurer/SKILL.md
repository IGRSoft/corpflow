---
name: preview-ensurer
description: |
  Detect modified SwiftUI View files lacking `#Preview`/`PreviewProvider` and auto-add a minimal
  `#Preview` block via SwiftSyntax. Use ONLY from the `dv-screenshot-capture` `apple-canvas`
  adapter, BEFORE `swift run SnapshotHost`.
version: 1.1.0
model: sonnet
effort: medium
tools: Read, Edit, Write, Bash, Glob, Grep
argument-hint: "<modified_files-newline-list> [--auto-add=true|false]"
keep-coding-instructions: true
---

# preview-ensurer

Auto-add minimal `#Preview { TypeName(<mocked-args>) }` blocks to SwiftUI View files that lack them. Driven by SwiftSyntax (pinned `.upToNextMajor(from: "510.0.0")`). Invoked exclusively from `dv-screenshot-capture/apple-canvas` adapter in v1.

## Contract (canonical signature)

```
ensure_previews(
  modified_files: [Path],              # absolute paths from git diff --diff-filter=AMR
  options: { auto_add: Bool,           # default true; false = dry-run (detect only)
             write_mode: "in-source" } # OQ1 ratified; "staged-patch" not supported in v1
) → {
  views: [{ file: Path,
            type: String,              # e.g. "ContentView"
            has_preview: Bool,
            action: "found" | "added" | "skipped",
            reason: String?,           # populated when action == "skipped"
            mock_strategy: String? }], # populated when action == "added"
  errors: [String]                     # non-empty → caller throws missing_input
}
```

## Heuristics (planning-0.md alignment)

Detail: `references/view-detection.md` (SwiftSyntax tree walks), `references/mock-data-strategy.md` (full mock derivation tree).

### H1 — View-file filter

Process a file only when it is path-filtered to a View location (`Sources/**/Views/*.swift`, `Sources/**/UI/*.swift`, `App/**/Views/*.swift`, …; configurable per project) AND declares a `SwiftUI.View` conformance detected via SwiftSyntax, NOT regex — extensions matter.

Skip: test files (`*Tests.swift`, `*Test.swift`); anything under `tools/SnapshotHost/` (don't bootstrap on our own scaffold); any file already containing `#Preview` OR `PreviewProvider` ANYWHERE (A4 invariant — pre-existing wins always).

### H2 — View-type detection

A `struct` / `class` / `actor` whose inheritance clause includes `View` (bare or qualified `SwiftUI.View`), OR an `extension X: View {...}` where `X` is declared in the same file (cross-file extension resolution is out of scope in v1).

If a single file contains 3+ View-conforming types, mark `action: "skipped"`, `reason: "ambiguous_view_target"` — the caller's `args.view` must disambiguate.

### H3 — Existing-preview detection

A file "has preview" if it contains a `#Preview` macro invocation (`MacroExpansionExprSyntax` with identifier `Preview`, with or without arguments) or a type with `PreviewProvider` in its inheritance clause.

**Critical**: detection runs BEFORE any edit. If positive, action=`"found"`, no edit attempted, no rollback risk. A4 satisfied.

### H4 — Initializer-signature parsing

Walk `MemberDeclListSyntax` for the target View's `InitializerDeclSyntax`. With no explicit init, infer Swift's synthesized memberwise init from the stored-property `VariableDeclSyntax` members. Record each parameter's name and type in declaration order.

### H5 — Mock-arg derivation per parameter type

| Parameter type pattern | Generated arg | `mock_strategy` |
|---|---|---|
| `Binding<Bool>` | `.constant(false)` | `binding-constant` |
| `Binding<Int>` | `.constant(0)` | `binding-constant` |
| `Binding<String>` | `.constant("")` | `binding-constant` |
| `Binding<<Optional>>` | `.constant(nil)` | `binding-constant` |
| `Optional<T>` / `T?` | `nil` | `optional-nil` |
| Concrete protocol `P`; `Source/Mocks/MockP.swift` exists | `MockP()` | `mock-found` |
| Concrete protocol `P`; no mock | skip view; emit `// preview-tbd: provide MockP` | `preview-tbd` |
| Concrete struct/class with no-arg init | `TypeName()` | (treated as concrete-init) |
| Closures / generics / complex / unknown | skip view; emit `// preview-tbd:` | `preview-tbd` |

Skipped view: `action: "skipped"`, `reason: "no_mock_for_<P>"` or `"unsupported_init_signature"`, plus a `// preview-tbd:` comment at end of file as a user-visible TODO.

### H6 — Generation + verification + rollback

1. Build the `#Preview` block via SwiftSyntax `MacroExpansionExprSyntax` (NOT string concat), appended at end of file through a `MemberDeclListSyntax` rewrite.
2. Write the modified file, then smoke it: `swift -frontend -parse <file>` (or `swiftc -parse <file>`).
3. Non-zero → `git checkout -- <file>` to revert; `errors[]` += `parse_failed_after_preview_add: <file>`; do NOT re-attempt.
4. Zero → emit the `preview_added` audit row + state.json fact update.

## State.json registration

`facts.previews_added[]` collects one entry per added preview:

```json
{ "file": "Sources/UI/ContentView.swift", "type": "ContentView",
  "action": "added", "mock_strategy": "binding-constant" }
```

Array max bounded by `modified_files.length`. Eviction at worktask archival.

## Audit row

One `preview_added` row per added preview: `{actor: "preview-ensurer", action: "preview_added", subject: "<view_type>", result: "ok", metadata: {file, view_type, mock_strategy, lines_added}}`. Field canon: `../dv-screenshot-capture/references/apple-canvas.md § Audit row schema`.

## Failure escalation

| Failure | Behavior |
|---|---|
| SwiftSyntax parse fails on input file | `errors[]` += `parse_failed: <file>`; skip file; continue with others |
| Post-edit `swift -frontend -parse` fails | Rollback (`git checkout -- <file>`); `errors[]` += `parse_failed_after_preview_add: <file>`; never leave broken syntax |
| swift-syntax API broke on toolchain bump | `errors[]` += `swift_syntax_api_break: <method>`; escalate per coordination-0.md risk-watch row 1 |
| File has 3+ View structs and no `args.view` | `action: "skipped"`, `reason: "ambiguous_view_target"`; surface for `metadata.canvas_view` selection |
| `Source/Mocks/MockP.swift` exists but doesn't compile against host | Out of scope — preview-ensurer trusts file existence; broken mocks surface at `swift run SnapshotHost` time as exit code 3 |

`errors[]` non-empty bubbles to apple-canvas, which throws `missing_input` to DV. DV records it in `.context/errors/developer.md`.

## Toolchain compatibility

swift-syntax pin `.upToNextMajor(from: "510.0.0")` (ad2) covers Swift 5.10 (Xcode 15.4) and Swift 6.0+ (Xcode 16.x). Drift canary: the P6 fixture project pins known-good in `Package.resolved` and CI smokes it.

Upgrade when Swift 6.x ships `602.x.x`: bump the `Package.swift` floor on a feature branch → run the fixture suite (`skills/preview-ensurer/tests/Fixtures/`) → green means PR with a one-line CHANGELOG, red means an `apple-developer:ios-developer` triage task.

## v1 limitations / future work

- Single-file scope: cross-file extension resolution out of scope (rare in practice; documented for v2).
- No matrix renders (dark/light/Dynamic-Type) — single shot only. Future: `args.trait_collections`.
- No `staged-patch` write mode (OQ1 was ratified as in-source only).
- SwiftUI `@Environment` / `@FocusState` parameters are not mocked — skipped with `preview-tbd:`.

## See also

- `references/view-detection.md` — SwiftSyntax patterns for View detection
- `references/mock-data-strategy.md` — full mock derivation tree
- `references/reference-impl/Sources/PreviewEnsurer/PreviewEnsurer.swift` — reference Swift implementation (executable)
- `tests/ensurer-tests.md` — fixture test matrix
- `../dv-screenshot-capture/references/apple-canvas.md` — caller contract (canonical)
- `../dv-screenshot-capture/references/preview-ensurer.md` — caller-side summary
