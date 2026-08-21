# view-detection.md — SwiftSyntax patterns for View detection

The SwiftSyntax tree walks `preview-ensurer` uses to identify SwiftUI View types and existing `#Preview` macros. Implementation lives in `references/reference-impl/Sources/PreviewEnsurer/PreviewEnsurer.swift`.

## SwiftSyntax visitor pattern

Detection uses a read-only `SyntaxVisitor`; in-source insertion uses a `SyntaxRewriter` (immutable tree → new tree). Detection always runs first; the rewrite is conditional on `auto_add: true` AND detection returning "no existing preview".

```swift
import SwiftSyntax
import SwiftParser

let tree = Parser.parse(source: try String(contentsOf: file, encoding: .utf8))
let detector = ViewDetector()
detector.walk(tree)
// detector.viewTypes → [ViewTypeInfo]; .hasPreview → Bool; .parseErrors → [String]
```

## View-conformance patterns

| Source shape | SwiftSyntax node | Notes |
|---|---|---|
| `struct X: View` — also `SwiftUI.View`, and alongside other conformances (`View, Equatable`) | `StructDeclSyntax.inheritanceClause?.inheritedTypes` | the 95% case |
| `class X: View` / `actor X: View` | `ClassDeclSyntax` / `ActorDeclSyntax` inheritance clause | rare but legal |
| `extension X: View` | `ExtensionDeclSyntax.inheritanceClause?` plus a same-file `Struct`/`ClassDeclSyntax` with matching `.name.text` | v1 resolves in-file only — cross-file needs a build-graph walk (out of scope) |

## Existing-preview patterns (A4 — never overwrite)

| Source shape | SwiftSyntax node |
|---|---|
| `struct X_Previews: PreviewProvider` (legacy, pre-Xcode-15) | any decl whose `.inheritanceClause` contains `PreviewProvider` |
| `#Preview { }`, `#Preview("dark mode") { }`, `#Preview(traits: .sizeThatFitsLayout) { }` | top-level `MacroExpansionExprSyntax` OR `MacroExpansionDeclSyntax` with `.macroName.text == "Preview"` — the visitor scans ALL of `SourceFileSyntax.statements` |

## Anti-pattern — `#Preview` inside comments or strings

Detection MUST NOT trigger on `// #Preview` or `let s = "#Preview"`. The tree walk ignores trivia and string-literal contents inherently — do NOT run regex over the raw source.

## Inheritance-clause traversal

```swift
extension InheritanceClauseSyntax {
    // Permissive on purpose: a false positive costs one failed SnapshotHost build
    // (the failure cascade catches it), a false negative silently drops a real View.
    func declaresView() -> Bool {
        self.inheritedTypes.contains { inh in
            let name = inh.type.trimmedDescription
            return name == "View" || name == "SwiftUI.View" || name.hasSuffix(".View")
        }
    }
}
```

## Nested and ambiguous files

- The visitor keeps a depth stack: register only top-level View types (depth == 1). Nested Views get a `// preview-tbd:` with reason `nested_view_unsupported`.
- `detector.viewTypes.count >= 3` with no caller-supplied `args.view` → `action: "skipped"`, `reason: "ambiguous_view_target"`, plus `view_count` and `view_names` surfaced in the DV summary so the user can pick.

## Position of injection

Append the `#Preview` block to the END of the file, after the last top-level declaration — rewrite `SourceFileSyntax.statements` with a new `MacroExpansionDeclSyntax`. Preserve the trailing newline at EOF.

## Post-edit smoke

`xcrun swift -frontend -parse <file>`, or the more permissive `xcrun swiftc -parse <file>` for files referencing other modules. Non-zero → rollback. The smoke catches the rare case where SwiftSyntax serialization produced invalid Swift under toolchain version skew.

## Test fixtures

Under `tests/Fixtures/`, with expected output documented in `tests/ensurer-tests.md`:

- `SimpleView.swift` — plain `struct: View`, no `#Preview` (should auto-add)
- `BindingView.swift` — same with `@Binding` (should auto-add via `binding-constant`)
- `AmbiguousMultiView.swift` — 3 View structs (should skip with `ambiguous_view_target`)
