# preview-ensurer — heuristics summary (from dv-screenshot-capture POV)

How `dv-screenshot-capture/apple-canvas` consumes `preview-ensurer`. The full skill lives at `../../preview-ensurer/SKILL.md`; the canonical cross-skill contract (call signature, result shape, invocation sequence) lives in `apple-canvas.md`.

> **One chokepoint** (v1): the apple-canvas adapter is the sole caller. Do not invoke preview-ensurer directly from DV outside `dv-screenshot-capture`.

## What preview-ensurer does

For each modified SwiftUI View file:

1. Parse with SwiftSyntax (pinned `.upToNextMajor(from: "510.0.0")`).
2. Detect View-conforming types (`struct X: View` / `class X: View` / extension conformance).
3. Check for an existing `#Preview` macro OR `PreviewProvider` conformance.
4. If absent and `auto_add: true`: synthesize a minimal `#Preview { TypeName(<mocked-args>) }`, append it, run a `swift -frontend -parse <file>` smoke check, and roll back on parse failure.
5. Return `{views, errors}` and write `state.json → facts.previews_added[]`.

**A4 invariant**: NEVER overwrite an existing `#Preview` or `PreviewProvider` — pre-existing previews always win.

## Mock-arg derivation rules (priority order)

| Parameter type | Generated arg | `mock_strategy` (audit) |
|---|---|---|
| `Binding<T>` (Bool / Int / String / Optional) | `.constant(<default>)` — `false`, `0`, `""`, `nil` | `binding-constant` |
| `Optional<T>` | `nil` | `optional-nil` |
| Concrete protocol `P` with `Source/Mocks/Mock<P>.swift` (file + type named exactly `Mock<ProtocolName>`) | `Mock<P>()` | `mock-found` |
| Concrete protocol `P`, no mock found | skip; emit `// preview-tbd: provide Mock<P>` (action=`skipped`, reason=`no_mock_for_<P>`) | `preview-tbd` |
| Concrete class/struct with a no-arg init (SwiftSyntax `init()` member) | `<Type>()` | (concrete-init) |
| Closures / generics / complex types | skip; emit `// preview-tbd:` (action=`skipped`, reason=`unsupported_init_signature`) | `preview-tbd` |

## Call and result (summary)

apple-canvas calls `ensure_previews(modified_files, options={auto_add: true, write_mode: "in-source"})` — `in-source` is the only v1 mode (ad4) — and receives `{views: [{file, type, has_preview, action, reason?, mock_strategy?}], errors: [String]}`. Empty `errors` → continue to `swift run SnapshotHost`; non-empty → apple-canvas throws `missing_input` and the DV completion gate records it in `.context/errors/developer.md`. Field-level contract: `apple-canvas.md § Function signature (canonical)`.

## Failure / escalation

| Failure | Behavior |
|---|---|
| SwiftSyntax parse fails on an input file | Append `parse_failed: <file>` to `errors[]`; skip that file, continue with the others |
| Post-edit `swift -frontend -parse` fails on the generated `#Preview` | Roll back (`git checkout -- <file>`); record skipped with reason `generated_preview_invalid`; never leave broken syntax |
| swift-syntax API breakage on a toolchain bump | Surface as `errors[]` with `swift_syntax_api_break: <hint>`; escalates per coordination-0.md risk-watch row 1 (apple-developer:ios-developer) |
| File contains 3+ View structs and `args.view` unspecified | Skip with reason `ambiguous_view_target`; user disambiguates via `metadata.canvas_view` |

Each added preview emits one `preview_added` audit row (`file`, `view_type`, `mock_strategy`, `lines_added`).

## Back-reference

- `../../preview-ensurer/SKILL.md` — the skill itself
- `../../preview-ensurer/references/view-detection.md` — SwiftSyntax patterns for `struct ...: View`
- `../../preview-ensurer/references/mock-data-strategy.md` — full mock derivation rules
