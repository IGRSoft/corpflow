# preview-ensurer — heuristics summary (from dv-screenshot-capture POV)

How `dv-screenshot-capture/apple-canvas` consumes `preview-ensurer`. The full skill lives at `../../preview-ensurer/SKILL.md`, which holds the canonical CLI and result shape; the invocation sequence lives in `apple-canvas.md`.

> One chokepoint: `scripts/apple-canvas.sh` is the sole caller, through `swift run … PreviewEnsurer`. The skill sets `disable-model-invocation`, so it is never reached through the `Skill` tool; do not run the executable from DV outside `dv-screenshot-capture`.

## What preview-ensurer does

For each modified `.swift` file outside `tools/SnapshotHost/`:

1. Parse with SwiftSyntax (pinned `.upToNextMajor(from: "510.0.0")`).
2. Detect top-level View-conforming types (`struct X: View` / `class X: View` / `extension X: View`).
3. Check for an existing `#Preview` macro OR `PreviewProvider` conformance.
4. If absent and `--auto-add true`: append a minimal `#Preview { TypeName(<mocked-args>) }` from a string template, run a `swift -frontend -parse <file>` smoke check, and on failure write the original text back from memory.
5. Print `{views, errors}` as JSON; apple-canvas saves it to `.context/logs/preview-ensurer-<ts>.json`. Nothing goes to `state.json`.

Never overwrite an existing `#Preview` or `PreviewProvider` — pre-existing previews always win.

## Mock-arg derivation rules (priority order)

| Parameter type | Generated arg | `mock_strategy` (audit) |
|---|---|---|
| `Binding<T>` (Bool / number / String / Optional / Array) | `.constant(<default>)` — `false`, `0`, `""`, `nil`, `[]` | `binding-constant` |
| `Optional<T>` | `nil` | `optional-nil` |
| `T` with `Source/Mocks/Mock<T>.swift` (file + type named exactly `Mock<T>`) | `Mock<T>()` | `mock-found` |
| Any other capitalized simple name, a protocol with no mock included | `<Type>()` | `concrete-init` |
| Closures / `some` / `any` / other spellings | skip, nothing written to the file (action=`skipped`, reason `closure_unsupported`, `generic_unsupported` or `unsupported_init_signature:<T>`) | `preview-tbd` |

## Call and result (summary)

apple-canvas runs `swift run --package-path <plugin>/skills/preview-ensurer/references/reference-impl PreviewEnsurer --modified-files <list-file> --auto-add true --project-root <root>` and reads `{views: [{file, type, has_preview, action, reason?, mock_strategy?, lines_added?}], errors: [String]}`. Exit 0 (empty `errors`) → continue to `swift run SnapshotHost`; non-zero → apple-canvas appends `missing_input: preview-ensurer errors` to `.context/errors/developer.md` and exits 2. Field-level contract: `../../preview-ensurer/SKILL.md § Contract (canonical signature)`.

## Failure / escalation

| Failure | Behavior |
|---|---|
| Input file unreadable, or the write fails | `skipped` with `read_failed` / `write_failed`; the same text goes to `errors[]` |
| Post-edit `swift -frontend -parse` fails on the generated `#Preview` | Roll back by rewriting the pre-edit text, so the developer's uncommitted edits survive; record skipped with reason `parse_failed_after_preview_add` and add `parse_failed_after_preview_add: <file>` to `errors[]`; never leave broken syntax |
| swift-syntax API breakage on a toolchain bump | The `swift run` build fails, a non-zero exit; triage with `apple-developer:ios-developer` |
| File contains 3+ View types | Skip with reason `ambiguous_view_target` — apple-canvas passes no `--view`, so `metadata.canvas_view` picks the render key, not the preview target |

apple-canvas writes one `preview_added` audit row per added preview (`file`, `view_type`, `mock_strategy`, `lines_added`).

## Back-reference

- `../../preview-ensurer/SKILL.md` — the skill itself
- `../../preview-ensurer/references/view-detection.md` — SwiftSyntax patterns for `struct ...: View`
- `../../preview-ensurer/references/mock-data-strategy.md` — full mock derivation rules
