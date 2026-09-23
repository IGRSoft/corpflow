---
name: preview-ensurer
description: Use when the `dv-screenshot-capture` apple-canvas adapter runs, before `swift run SnapshotHost`. Adds a minimal `#Preview` block via SwiftSyntax to modified SwiftUI View files that have no `#Preview` or `PreviewProvider`.
version: 1.1.0
argument-hint: "<modified_files-newline-list> [--auto-add=true|false]"
keep-coding-instructions: true
# G3: no standalone value — it edits Swift sources mid-capture from an adapter's modified-file list, which a user outside a DV screenshot run does not have.
disable-model-invocation: true
---

# preview-ensurer

Appends a minimal `#Preview { TypeName(<mocked-args>) }` block to SwiftUI View files that lack one, driven by SwiftSyntax (pinned `.upToNextMajor(from: "510.0.0")`). The `dv-screenshot-capture` apple-canvas adapter is its only caller.

## Contract (canonical signature)

```
ensure_previews(
  modified_files: [Path],              # absolute paths from git diff --diff-filter=AMR
  options: { auto_add: Bool,           # default true; false = dry-run (detect only)
             write_mode: "in-source" } # the only mode; "staged-patch" unsupported
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

## Heuristics

### H1 — View-file filter

Process a file only when it sits under a View path (`Sources/**/Views/*.swift`, `Sources/**/UI/*.swift`, `App/**/Views/*.swift`, …; configurable per project) and declares a `SwiftUI.View` conformance, detected with SwiftSyntax rather than regex so extensions count.

Skip test files (`*Tests.swift`, `*Test.swift`), anything under `tools/SnapshotHost/` (the capture scaffold itself), and any file that already contains `#Preview` or `PreviewProvider` anywhere — a pre-existing preview always wins.

### H2 — View-type detection

A `struct` / `class` / `actor` whose inheritance clause includes `View` (bare or `SwiftUI.View`), or an `extension X: View` where `X` is declared in the same file. A file with 3+ View types is skipped with `reason: "ambiguous_view_target"`; the caller's `args.view` disambiguates.

### H3 — Existing-preview detection

A file has a preview if it contains a `#Preview` macro (`MacroExpansionExprSyntax` named `Preview`, with or without arguments) or a type with `PreviewProvider` in its inheritance clause. Detection runs before any edit; a hit returns `action: "found"` and the file is left untouched.

### H4 — Initializer-signature parsing

Take the target View's `InitializerDeclSyntax`; with no explicit init, infer Swift's synthesized memberwise init from the stored-property `VariableDeclSyntax` members. Record each parameter's name and type in declaration order.

### H5 — Mock-arg derivation

Per parameter: `Binding<…>` → `.constant(<empty value>)` (`binding-constant`); optional → `nil` (`optional-nil`); protocol `P` with a `Mock<P>.swift` file → `Mock<P>()` (`mock-found`); concrete type with a no-arg init → `T()` (`concrete-init`). Anything else — a protocol with no mock, closures, generics — skips the view: `action: "skipped"`, a reason such as `no_mock_for_<P>` or `unsupported_init_signature`, `mock_strategy: "preview-tbd"`, and a `// preview-tbd:` comment at end of file as a user-visible TODO. Full table and reasons: `references/mock-data-strategy.md`.

### H6 — Generation, verification, rollback

1. Build the `#Preview` block as a SwiftSyntax `MacroExpansionExprSyntax` rather than by string concatenation, and append it at end of file through a `MemberDeclListSyntax` rewrite.
2. Write the file, then smoke it: `swift -frontend -parse <file>` (or `swiftc -parse <file>`).
3. Non-zero → revert with `git checkout -- <file>`, add `parse_failed_after_preview_add: <file>` to `errors[]`, and do not retry.
4. Zero → emit the `preview_added` audit row and the state.json fact.

## State.json registration

`facts.previews_added[]` gets one entry per added preview, bounded by `modified_files.length` and evicted at worktask archival:

```json
{ "file": "Sources/UI/ContentView.swift", "type": "ContentView",
  "action": "added", "mock_strategy": "binding-constant" }
```

## Audit row

One `preview_added` row per added preview: `{actor: "preview-ensurer", action: "preview_added", subject: "<view_type>", result: "ok", metadata: {file, view_type, mock_strategy, lines_added}}`. Field canon: `../dv-screenshot-capture/references/apple-canvas.md § Audit row schema`.

## Failure escalation

| Failure | Behavior |
|---|---|
| SwiftSyntax parse fails on input file | `errors[]` += `parse_failed: <file>`; skip file; continue with others |
| Post-edit `swift -frontend -parse` fails | Rollback (`git checkout -- <file>`); `errors[]` += `parse_failed_after_preview_add: <file>`; never leave broken syntax |
| swift-syntax API broke on toolchain bump | `errors[]` += `swift_syntax_api_break: <method>`; escalate to `apple-developer:ios-developer` |
| File has 3+ View structs and no `args.view` | `action: "skipped"`, `reason: "ambiguous_view_target"`; surface for `metadata.canvas_view` selection |
| `Mock<P>.swift` exists but doesn't compile against host | Out of scope — file existence is trusted; broken mocks surface at `swift run SnapshotHost` time as exit code 3 |

Non-empty `errors[]` bubbles to apple-canvas, which throws `missing_input` to DV; DV records it in `.context/errors/developer.md`.

## Toolchain compatibility

The swift-syntax pin `.upToNextMajor(from: "510.0.0")` builds with Swift 5.10 (Xcode 15.4) and Swift 6.0+ (Xcode 16.x). To move to a newer swift-syntax major, bump the floor in `references/reference-impl/Package.swift` on a feature branch and run the fixture suite (`tests/ensurer-tests.md`): green → PR with a one-line CHANGELOG entry; red → an `apple-developer:ios-developer` triage task.

## Limitations

- Single-file scope: extensions of types declared in another file are not resolved.
- One render per view; no dark/light/Dynamic Type matrix.
- In-source writes only; no `staged-patch` mode.
- SwiftUI `@Environment` / `@FocusState` parameters are not mocked — skipped with `preview-tbd:`.

## See also

- `references/view-detection.md` — SwiftSyntax patterns for View and preview detection
- `references/mock-data-strategy.md` — full mock derivation table
- `references/reference-impl/Sources/PreviewEnsurer/PreviewEnsurer.swift` — the executable apple-canvas runs
- `tests/ensurer-tests.md` — fixture test matrix
- `../dv-screenshot-capture/references/apple-canvas.md` — caller contract (canonical)
- `../dv-screenshot-capture/references/preview-ensurer.md` — caller-side summary
