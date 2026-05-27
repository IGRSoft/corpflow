# preview-ensurer — heuristics summary (from dv-screenshot-capture POV)

This file is the **summary** of how `dv-screenshot-capture/apple-canvas` consumes `preview-ensurer`. The full skill lives at `../../preview-ensurer/SKILL.md`; the canonical cross-skill contract lives in `apple-canvas.md`.

> **One chokepoint** (v1): apple-canvas adapter is the sole caller of preview-ensurer. Do not invoke it directly from DV outside of `dv-screenshot-capture`.

## What preview-ensurer does

For each modified SwiftUI View file:

1. Parse with SwiftSyntax (pinned `.upToNextMajor(from: "510.0.0")`).
2. Detect View-conforming types (`struct X: View` / `class X: View` / extension conformance).
3. Check for any existing `#Preview` macro OR `PreviewProvider` conformance.
4. If absent and `auto_add: true`: synthesize a minimal `#Preview { TypeName(<mocked-args>) }`, append to the file, run `swift -frontend -parse <file>` smoke; rollback on parse failure.
5. Return structured `{views, errors}` result; write to `state.json → facts.previews_added[]`.

**A4 invariant**: NEVER overwrite an existing `#Preview` or `PreviewProvider`. Pre-existing previews always win.

## Mock-arg derivation rules (priority order)

| Parameter type | Generated arg | `mock_strategy` (audit) | Notes |
|---|---|---|---|
| `Binding<T>` (Bool / Int / String / Optional) | `.constant(<default>)` | `binding-constant` | Defaults: `false`, `0`, `""`, `nil` |
| `Optional<T>` | `nil` | `optional-nil` | Trivial |
| Concrete protocol `P` with `Source/Mocks/Mock<P>.swift` | `Mock<P>()` | `mock-found` | Convention: file + type exactly `Mock<ProtocolName>` |
| Concrete protocol `P`, no mock found | skip; emit `// preview-tbd: provide Mock<P>` | `preview-tbd` | action=`skipped`, reason=`no_mock_for_<P>` |
| Concrete class/struct with no-arg init | `<Type>()` | (treated as concrete-init) | Detected via SwiftSyntax `init()` member |
| Closures / generics / complex types | skip; emit `// preview-tbd:` | `preview-tbd` | action=`skipped`, reason=`unsupported_init_signature` |

## Inputs from apple-canvas

```
ensure_previews(
  modified_files = [...absolute paths from git diff...],
  options = {
    auto_add: true,
    write_mode: "in-source"   # ad4 — only mode in v1
  }
)
```

## Outputs consumed by apple-canvas

```
{
  views: [{file, type, has_preview, action, reason?, mock_strategy?}],
  errors: [String]
}
```

- `errors` empty → apple-canvas continues to `swift run SnapshotHost`.
- `errors` non-empty → apple-canvas throws `missing_input`; DV completion gate records it in `.context/errors/developer.md`.

## Failure / escalation

| Failure | Behavior |
|---|---|
| SwiftSyntax parse fails on input file | Append to `errors[]` with `parse_failed: <file>`; skip that file but continue with others |
| Post-edit `swift -frontend -parse` fails on generated `#Preview` | Rollback edit (`git checkout -- <file>`); record skipped with reason `generated_preview_invalid`; never leave broken syntax |
| swift-syntax API breakage on toolchain bump | Surface as `errors[]` with `swift_syntax_api_break: <hint>`; escalates per coordination-0.md risk-watch row 1 (apple-developer:ios-developer) |
| File contains 3+ View structs and `args.view` not specified | Skip with reason `ambiguous_view_target`; surface for user to disambiguate via `metadata.canvas_view` |

## Audit row emitted

```
action: "preview_added"
metadata:
  file: <path>
  view_type: <TypeName>
  mock_strategy: binding-constant | optional-nil | mock-found | preview-tbd
  lines_added: <integer>
```

## Back-reference

For the full SwiftSyntax driver, View detection patterns, and the fixture test matrix, see:

- `../../preview-ensurer/SKILL.md` — the skill itself
- `../../preview-ensurer/references/view-detection.md` — SwiftSyntax patterns for `struct ...: View`
- `../../preview-ensurer/references/mock-data-strategy.md` — full mock derivation rules
