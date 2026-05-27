---
name: preview-ensurer
description: |
  Detect SwiftUI View files modified in the current diff that lack a `#Preview` macro or `PreviewProvider`,
  and auto-add a minimal `#Preview { TypeName(<mocked-args>) }` block in-source using SwiftSyntax. Use this
  skill from inside the `dv-screenshot-capture` `apple-canvas` adapter ONLY (v1 single-chokepoint rule):
  it runs BEFORE `swift run SnapshotHost` so the host has a `#Preview` to render. Mock-arg derivation
  follows Binding→.constant / Optional→nil / Protocol→Mock<P> conventions; A4 invariant: existing previews
  are never overwritten. Returns `{views: [...], errors: [...]}`; non-empty errors bubble as missing_input
  to the calling DV stage.
version: 1.0.0
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
  modified_files: [Path],         # absolute paths from git diff --diff-filter=AMR
  options: {
    auto_add: Bool,               # default true; false = dry-run (detect only)
    write_mode: "in-source"       # OQ1 ratified; "staged-patch" not supported in v1
  }
) → {
  views: [
    {
      file: Path,
      type: String,               # e.g. "ContentView"
      has_preview: Bool,
      action: "found" | "added" | "skipped",
      reason: String?,            # populated when action == "skipped"
      mock_strategy: String?      # populated when action == "added"
    }
  ],
  errors: [String]                # non-empty → caller throws missing_input
}
```

## Heuristics (planning-0.md alignment)

### H1 — View-file filter

Only process files that are:

- Path-filtered to common View locations (`Sources/**/Views/*.swift`, `Sources/**/UI/*.swift`, `App/**/Views/*.swift`, etc.). Configurable per project.
- Contain at least one `struct X: View` / `class X: View` / extension declaration that conforms to `SwiftUI.View` (detected via SwiftSyntax, NOT regex — extensions matter).

Skip files that:

- Contain only test code (`*Tests.swift`, `*Test.swift`).
- Are under `tools/SnapshotHost/` (don't bootstrap on our own scaffold).
- Already contain `#Preview` OR `PreviewProvider` ANYWHERE (A4 invariant — pre-existing wins always).

### H2 — View-type detection

Use SwiftSyntax to locate every declaration that:

1. Is `struct` / `class` / `actor` declaration.
2. Has an inheritance clause that includes `View` (qualified `SwiftUI.View` or bare `View`).
3. OR an `extension X: View {...}` declaration where `X` is a type declared in the same file (resolve cross-file extension as out-of-scope v1).

If a single file contains 3+ View-conforming types, mark `action: "skipped"`, `reason: "ambiguous_view_target"` — the caller's `args.view` must disambiguate.

### H3 — Existing-preview detection

A file is treated as "has preview" if ANY of:

- Contains `#Preview` macro invocation (`MacroExpansionExprSyntax` with identifier `Preview`).
- Contains a type with `PreviewProvider` in its inheritance clause.
- Contains `#Preview(...) {...}` with arguments (named previews).

**Critical**: detection runs BEFORE any edit. If positive, action=`"found"`, no edit attempted, no rollback risk. A4 satisfied.

### H4 — Initializer-signature parsing

For each target View type, locate the synthesized or explicit `init` SwiftSyntax declaration:

- Walk `MemberDeclListSyntax` for `InitializerDeclSyntax`.
- If no explicit init present, infer from `VariableDeclSyntax` members marked stored properties (Swift's synthesized memberwise init).
- Each parameter has a name and type — record them in order.

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

When a view is skipped: `action: "skipped"`, `reason: "no_mock_for_<P>"` or `"unsupported_init_signature"`. Emit a `// preview-tbd:` comment at the bottom of the file as a user-visible TODO.

### H6 — Generation + verification + rollback

1. Build `#Preview` block via SwiftSyntax `MacroExpansionExprSyntax` (NOT string concat) using `MemberDeclListSyntax` rewrite to append at end of file.
2. Write the modified file.
3. Run `swift -frontend -parse <file>` (or `swiftc -parse <file>` smoke).
4. On non-zero: `git checkout -- <file>` to revert; append `errors[]` entry `parse_failed_after_preview_add: <file>`; do NOT re-attempt.
5. On success: emit `preview_added` audit row + state.json fact update.

## State.json registration

```json
{
  "facts": {
    "previews_added": [
      { "file": "Sources/UI/ContentView.swift", "type": "ContentView",
        "action": "added", "mock_strategy": "binding-constant" }
    ]
  }
}
```

Array max bounded by `modified_files.length`. Eviction at workflow archival.

## Audit row

```jsonc
{
  "actor": "preview-ensurer",
  "action": "preview_added",
  "subject": "<view_type>",
  "result": "ok",
  "metadata": {
    "file": "Sources/UI/ContentView.swift",
    "view_type": "ContentView",
    "mock_strategy": "binding-constant",
    "lines_added": 6
  }
}
```

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

- swift-syntax pin: `.upToNextMajor(from: "510.0.0")` (ad2).
- Covers Swift 5.10 (Xcode 15.4) and Swift 6.0+ (Xcode 16.x).
- Upgrade procedure when Swift 6.x ships `602.x.x`:
  1. Bump preview-ensurer `Package.swift` floor in a feature branch.
  2. Run the fixture suite (`skills/preview-ensurer/tests/Fixtures/`).
  3. If green: open PR with one-line CHANGELOG; otherwise file `apple-developer:ios-developer` triage task.
- Drift detection: P6 fixture project pins to known-good in `Package.resolved`. CI smoke is the canary.

## v1 limitations / future work

- Single-file scope: cross-file extension resolution out of scope (rare in practice; documented for v2).
- No matrix renders (dark/light/Dynamic-Type) — single shot only. Future: `args.trait_collections`.
- No `staged-patch` write mode (OQ1 was ratified as in-source only).
- No support for SwiftUI `@Environment` or `@FocusState` parameters in mocked init (skipped with `preview-tbd:` if encountered).

## See also

- `references/view-detection.md` — SwiftSyntax patterns for View detection
- `references/mock-data-strategy.md` — full mock derivation tree
- `examples/PreviewEnsurer.swift` — reference Swift implementation (executable)
- `tests/ensurer-tests.md` — fixture test matrix
- `../dv-screenshot-capture/references/apple-canvas.md` — caller contract (canonical)
- `../dv-screenshot-capture/references/preview-ensurer.md` — caller-side summary
