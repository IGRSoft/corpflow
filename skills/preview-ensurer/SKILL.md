---
name: preview-ensurer
description: Use when the `dv-screenshot-capture` apple-canvas adapter runs, before `swift run SnapshotHost`. Detects SwiftUI View types with SwiftSyntax and appends a minimal `#Preview` block to modified View files that have no `#Preview` or `PreviewProvider`.
version: 1.1.0
argument-hint: "<modified_files-newline-list> [--auto-add=true|false]"
# G3: no standalone value — it edits Swift sources mid-capture from an adapter's modified-file list, which a user outside a DV screenshot run does not have.
disable-model-invocation: true
---

# preview-ensurer

Appends a minimal `#Preview { TypeName(<mocked-args>) }` block to SwiftUI View files that lack one. SwiftSyntax (pinned `.upToNextMajor(from: "510.0.0")`) detects the View types and existing previews; the block itself is a string template. The executable is `references/reference-impl` (`PreviewEnsurer`), and `dv-screenshot-capture/scripts/apple-canvas.sh` is its only caller, through `swift run`. `disable-model-invocation` keeps the Skill tool from loading this file, so no agent reaches it through `Skill`.

## Contract (canonical signature)

```
swift run --package-path skills/preview-ensurer/references/reference-impl PreviewEnsurer \
  --modified-files <newline list | path of a file with one path per line> \   # stdin when omitted
  [--auto-add true|false] \   # default true; false = dry run, nothing written
  [--view <TypeName>] \       # picks the target in a file with 3+ View types
  [--project-root <dir>]      # where Mock<T>.swift is looked up; default: cwd
→ stdout JSON, sorted keys, nil fields dropped:
{ views: [{ file, type, has_preview: Bool,
            action: "found" | "added" | "skipped",
            reason: String?,          # set on skipped
            mock_strategy: String?,   # set on added, dry_run, and a preview-tbd skip
            lines_added: Int? }],     # set on added
  errors: [String] }                  # "<reason>: <file>", read/write/parse failures
exit 0 when errors is empty, 1 otherwise
```

### How apple-canvas calls it

apple-canvas passes `--modified-files <list-file> --auto-add true --project-root <root>` and no `--view`.

## Heuristics

### H1 — File filter

Every `.swift` path in the list is processed except anything under `tools/SnapshotHost/` (the capture scaffold). There is no View-path filter and no test-file skip: a file with no top-level View type returns `skipped`, `reason: "no_view_type_detected"`. A file that already holds a preview returns `found` and is left untouched (H3).

### H2 — View-type detection

A top-level `struct` or `class` whose inheritance clause names `View`, `SwiftUI.View` or any `*.View`, or a top-level `extension X: View` (registered by name with no parameters; `X` need not be declared in the file). Actors and nested types are not detected. With 3+ View types and no matching `--view`, the file is skipped with `reason: "ambiguous_view_target"`; with one or two, the first wins. apple-canvas passes no `--view`, so under it a 3+-View file is always skipped.

### H3 — Existing-preview detection

A `#Preview` macro anywhere in the tree (expression or declaration form, with or without arguments), or a `struct`/`class` with `PreviewProvider` in its inheritance clause. Detection runs before any edit; a hit returns `action: "found"`.

### H4 — Initializer-signature parsing

The target's first explicit `init` wins. Without one, the memberwise init is inferred from stored properties, leaving out `static`/`class`, computed and defaulted properties and anything wrapped in `@State`, `@StateObject`, `@EnvironmentObject`, `@Environment` or `@FocusState`; `@Binding var x: T` becomes `Binding<T>`.

### H5 — Mock-arg derivation

Per parameter: `Binding` of `Bool`, a number, `String`, an optional or an array → `.constant(<empty value>)` (`binding-constant`); optional → `nil` (`optional-nil`); `T` with a `Mock<T>.swift` file → `Mock<T>()` (`mock-found`); any other capitalized simple name → `T()` (`concrete-init`), a protocol without a mock included. Closures, `some`/`any`/`AnyView`, other `Binding` types and other spellings skip the view: `action: "skipped"`, `mock_strategy: "preview-tbd"`, a reason such as `closure_unsupported` or `unsupported_init_signature:<T>`. A skip writes nothing to the file. Full table: `references/mock-data-strategy.md`.

### H6 — Generation, verification, rollback

1. Build the block from the string template and append it at end of file.
2. Write the file, then smoke it: `xcrun swift -frontend -parse <file>`.
3. Non-zero → write the original text back from memory, so the developer's other uncommitted edits in the file survive; return `skipped` with `reason: "parse_failed_after_preview_add"`, add `parse_failed_after_preview_add: <file>` to `errors[]`, and do not retry.
4. Zero → `action: "added"` with `lines_added`.

## Where results land

The executable writes only the source files and its stdout JSON; nothing goes to `state.json`. apple-canvas saves the JSON to `.context/logs/preview-ensurer-<ts>.json` and writes one `preview_added` audit row per `added` view: `{actor: "apple-canvas-adapter", action: "preview_added", subject: "<worktask_id>/<slug>", result: "ok", metadata: {file, view_type, mock_strategy, lines_added}}`. Field canon: `../dv-screenshot-capture/references/apple-canvas.md § Audit row schema`.

## Failure escalation

| Failure | Behavior |
|---|---|
| File unreadable, or the write fails | `skipped` with `read_failed: …` / `write_failed: …`; the same text goes to `errors[]` |
| Post-edit `swift -frontend -parse` fails | Original text written back from memory; `skipped`, `parse_failed_after_preview_add`; `errors[]` += `parse_failed_after_preview_add: <file>` |
| File has 3+ View types and no `--view` | `skipped`, `reason: "ambiguous_view_target"` |
| `Mock<T>.swift` or a `concrete-init` guess doesn't compile against the host | Not caught here — the parse smoke checks syntax only; it surfaces at `swift run SnapshotHost` |

### Non-zero exit

`Parser.parse` recovers from syntax errors instead of throwing, so an unparseable input is not an error: it yields whatever types the recovered tree holds. A swift-syntax API break on a toolchain bump fails the `swift run` build itself. Either way a non-zero exit makes apple-canvas append `missing_input: preview-ensurer errors` to `.context/errors/developer.md`, write a `canvas_render` error row (`reason: "preview_ensurer_errors"`) and exit 2.

## Toolchain compatibility

The swift-syntax pin `.upToNextMajor(from: "510.0.0")` builds with Swift 5.10 (Xcode 15.4) and Swift 6.0+ (Xcode 16.x). To move to a newer swift-syntax major, bump the floor in `references/reference-impl/Package.swift` on a feature branch and run the fixture suite (`tests/ensurer-tests.md`): green → PR with a one-line CHANGELOG entry; red → an `apple-developer:ios-developer` triage task.

## Limitations

- Single-file scope: extensions of types declared in another file are not resolved.
- One render per view; no dark/light/Dynamic Type matrix.
- In-source writes only; no `staged-patch` mode.
- `@State`, `@StateObject`, `@EnvironmentObject`, `@Environment` and `@FocusState` properties are left out of the call, not mocked; the view still gets a preview and renders with whatever the host environment supplies.
- Nested View types and actors are not detected.

## See also

- `references/view-detection.md` — SwiftSyntax patterns for View and preview detection
- `references/mock-data-strategy.md` — full mock derivation table
- `references/reference-impl/Sources/PreviewEnsurer/PreviewEnsurer.swift` — the executable apple-canvas runs
- `tests/ensurer-tests.md` — fixture test matrix
- `../dv-screenshot-capture/references/apple-canvas.md` — caller contract (canonical)
- `../dv-screenshot-capture/references/preview-ensurer.md` — caller-side summary
