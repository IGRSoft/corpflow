# view-detection.md — SwiftSyntax patterns for View detection

This reference documents the SwiftSyntax tree walks that `preview-ensurer` uses to identify SwiftUI View types and existing `#Preview` macros. Implementation lives in `references/reference-impl/Sources/PreviewEnsurer/PreviewEnsurer.swift`.

## SwiftSyntax visitor pattern

`preview-ensurer` uses a `SyntaxVisitor` (read-only walk) for detection, and a `SyntaxRewriter` (immutable tree → new tree) for in-source insertion. Detection always runs first; rewrite is conditional on `auto_add: true` AND detection returning "no existing preview".

```swift
import SwiftSyntax
import SwiftParser

let source = try String(contentsOf: file, encoding: .utf8)
let tree   = Parser.parse(source: source)

let detector = ViewDetector()
detector.walk(tree)

// detector.viewTypes    → [ViewTypeInfo]
// detector.hasPreview   → Bool
// detector.parseErrors  → [String]
```

## Pattern 1 — `struct X: View { ... }`

The 95% case: a top-level struct that conforms to `View` directly.

```swift
// matches:
struct ContentView: View {
    var body: some View { Text("hi") }
}

// matches (qualified):
struct ContentView: SwiftUI.View { ... }

// matches (multiple conformances):
struct ContentView: View, Equatable { ... }
```

SwiftSyntax shape: `StructDeclSyntax.inheritanceClause?.inheritedTypes` contains an `InheritedTypeSyntax` whose `.type.trimmedDescription` equals one of:

- `"View"`
- `"SwiftUI.View"`

## Pattern 2 — `class X: View { ... }` / `actor X: View { ... }`

Rare but valid. Same inheritance-clause shape, different decl node:

```swift
// matches (class-based View — unusual but legal):
class ObservedView: View { ... }
```

SwiftSyntax shape: `ClassDeclSyntax.inheritanceClause?` / `ActorDeclSyntax.inheritanceClause?`.

## Pattern 3 — `extension X: View { ... }`

Extension-based View conformance. v1 limitation: only resolved when the base type `X` is also declared in the same file (in-file resolution only — cross-file resolution requires a build-graph walk and is out of scope).

```swift
struct ContentView { /* not yet a View */ }

extension ContentView: View {
    var body: some View { Text("hi") }
}
```

SwiftSyntax shape: `ExtensionDeclSyntax.inheritanceClause?` + cross-reference to a same-file `StructDeclSyntax`/`ClassDeclSyntax` with matching `.name.text`.

## Pattern 4 — `PreviewProvider` legacy conformance

Pre-Xcode-15 preview style. Treated as "has preview" for A4 invariant — never overwrite:

```swift
struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}
```

SwiftSyntax shape: any decl whose `.inheritanceClause` contains `PreviewProvider`.

## Pattern 5 — `#Preview` macro detection

The new (Xcode 15+) macro form. Two shapes:

```swift
// trailing-closure form:
#Preview {
    ContentView()
}

// named form:
#Preview("dark mode") {
    ContentView().preferredColorScheme(.dark)
}

// parameterized form:
#Preview(traits: .sizeThatFitsLayout) {
    ContentView()
}
```

SwiftSyntax shape: `MacroExpansionExprSyntax` (top-level) OR `MacroExpansionDeclSyntax` whose `.macroName.text == "Preview"`. The visitor scans ALL of `SourceFileSyntax.statements` looking for either node form.

## Anti-pattern — comments / strings containing `#Preview`

Detection MUST NOT trigger on:

```swift
// #Preview  ← comment; ignored
let s = "#Preview"   // string literal; ignored
```

SwiftSyntax tree walk inherently ignores trivia (comments) and string literal contents — this is automatic with the visitor pattern (do NOT use regex on the raw source).

## Ambiguous file detection

If `detector.viewTypes.count >= 3` AND no `args.view` provided by the caller, mark the file as `ambiguous_view_target`:

```
action: "skipped"
reason: "ambiguous_view_target"
view_count: <N>
view_names: [...]   # surface in DV summary for user to pick
```

This addresses the "3+ View structs in one file" fixture case.

## Conformance traversal

The visitor maintains a stack to handle nested types:

```swift
struct Outer: View {       // depth 1, top-level View
    struct Inner: View {   // depth 2, nested — only register if at type-name uniqueness boundary
        var body: ...
    }
}
```

v1 rule: register only top-level View types (depth == 1). Nested Views are `// preview-tbd:`'d with reason `nested_view_unsupported`.

## Inheritance-clause traversal

Helper that resolves `"View"` / `"SwiftUI.View"` consistently:

```swift
extension InheritanceClauseSyntax {
    func declaresView() -> Bool {
        self.inheritedTypes.contains { inh in
            let name = inh.type.trimmedDescription
            return name == "View"
                || name == "SwiftUI.View"
                || name.hasSuffix(".View")  // permissive — covers DesignSystem.View etc.
        }
    }
}
```

Note: the permissive `hasSuffix(".View")` is intentional. False positives here are safe because the next step (`#Preview` macro generation) targets a concrete `TypeName(<args>)` constructor — if the type isn't actually a SwiftUI.View, `swift build` of SnapshotHost will fail and the failure cascade kicks in. False negatives (silently skipping a real View) are worse than false positives.

## Position of injection

When inserting a `#Preview` block, append it to the **end of the file**, after the last existing top-level declaration. SwiftSyntax shape: rewrite `SourceFileSyntax.statements` by appending a new `MacroExpansionDeclSyntax`.

```swift
// before:
struct ContentView: View { ... }
// EOF

// after:
struct ContentView: View { ... }

#Preview {
    ContentView()
}
// EOF
```

Preserve trailing newline at EOF.

## Post-edit smoke

After writing the modified file:

```bash
xcrun swift -frontend -parse <file>
# OR (more permissive — for files referencing other modules):
xcrun swiftc -parse <file>
```

Non-zero → rollback. The smoke catches the rare case where SwiftSyntax serialization produced invalid Swift (toolchain version skew).

## Test fixtures

Located under `tests/Fixtures/`:

- `SimpleView.swift` — Pattern 1, no `#Preview` (should auto-add)
- `BindingView.swift` — Pattern 1 with `@Binding`, no `#Preview` (should auto-add via `binding-constant`)
- `AmbiguousMultiView.swift` — 3 Pattern-1 structs (should skip with `ambiguous_view_target`)

Each fixture documents expected output in `tests/ensurer-tests.md`.
