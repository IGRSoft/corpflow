# view-detection.md — SwiftSyntax patterns for View detection

The SwiftSyntax tree walk `preview-ensurer` uses to identify SwiftUI View types and existing `#Preview` macros. Implementation lives in `references/reference-impl/Sources/PreviewEnsurer/PreviewEnsurer.swift`.

## SwiftSyntax visitor pattern

Detection uses a read-only `SyntaxVisitor`. There is no `SyntaxRewriter`: the `#Preview` block is a string appended to the source text (§ Position of injection), and only when `--auto-add true` and detection found no existing preview.

```swift
import SwiftSyntax
import SwiftParser

let tree = Parser.parse(source: try String(contentsOf: file, encoding: .utf8))
let detector = ViewDetector()
detector.walk(tree)
// detector.viewTypes → [Detected] (top-level only); .hasPreview / .hasPreviewProvider → Bool
```

## View-conformance patterns

| Source shape | SwiftSyntax node | Notes |
|---|---|---|
| `struct X: View` — also `SwiftUI.View`, and alongside other conformances (`View, Equatable`) | `StructDeclSyntax.inheritanceClause?.inheritedTypes` | the 95% case |
| `class X: View` | `ClassDeclSyntax` inheritance clause | rare but legal; `actor` is not detected |
| `extension X: View` | `ExtensionDeclSyntax.inheritanceClause?` | registered by `extendedType` name with no parameters, so the preview is `X()`; no check that `X` is declared in the file |

## Existing-preview patterns (never overwritten)

| Source shape | SwiftSyntax node |
|---|---|
| `struct X_Previews: PreviewProvider` (legacy, pre-Xcode-15) | a `struct` or `class` whose `.inheritanceClause` contains `PreviewProvider`, at any depth |
| `#Preview { }`, `#Preview("dark mode") { }`, `#Preview(traits: .sizeThatFitsLayout) { }` | `MacroExpansionExprSyntax` OR `MacroExpansionDeclSyntax` with `.macroName.text == "Preview"`, anywhere in the tree |

## Anti-pattern — `#Preview` inside comments or strings

Detection must not trigger on `// #Preview` or `let s = "#Preview"`. The tree walk ignores trivia and string-literal contents on its own, so don't run regex over the raw source.

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

- The visitor keeps a depth counter and registers only top-level View types (depth == 1). Nested View types are ignored: no comment, no result row of their own.
- `detector.viewTypes.count >= 3` with no matching `--view` → `action: "skipped"`, `reason: "ambiguous_view_target"`; the result carries no view count or names. With one or two types the first is the target.

## Position of injection

Append the block text to the end of the source string, after a newline if the file lacks a trailing one. The block starts with a blank line and ends with a newline.

## Post-edit smoke

`xcrun swift -frontend -parse <file>`. Non-zero → the original text is written back from memory, never `git checkout`, so the developer's uncommitted edits survive. The smoke checks syntax only: it catches a template that produced invalid Swift, not a mock or `concrete-init` guess that fails to type-check.

## Test fixtures

`tests/Fixtures/`, with expected output in `tests/ensurer-tests.md`.
