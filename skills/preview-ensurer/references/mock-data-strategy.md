# mock-data-strategy.md — Mock-arg derivation rules

Full derivation rules `preview-ensurer` uses to synthesize `TypeName(<args>)` for the generated `#Preview` block. Walk the target View initializer's parameters in declaration order; first match wins. Emitted `mock_strategy` values match `../../dv-screenshot-capture/references/apple-canvas.md § Audit row schema` (`preview_added.metadata.mock_strategy`).

## Derivation — `Binding<U>` parameters

Defaults are conservative — identity or empty values that can never crash a SwiftUI body that reads them.

| `U` | Generated arg | `mock_strategy` |
|---|---|---|
| `Bool` | `.constant(false)` | `binding-constant` |
| `Int` | `.constant(0)` | `binding-constant` |
| `Double` / `Float` / `CGFloat` | `.constant(0)` | `binding-constant` |
| `String` | `.constant("")` | `binding-constant` |
| `Optional<V>` | `.constant(nil)` | `binding-constant` |
| `Array<V>` | `.constant([])` | `binding-constant` |
| anything else | skip view | `preview-tbd`, reason `binding_complex_type:<U>` |

## Derivation — non-`Binding` parameters

Checked in this order:

| Parameter type `T` | Generated arg | `mock_strategy` |
|---|---|---|
| `Optional<U>` / `U?` | `nil` | `optional-nil` |
| closure (`(...) -> ...`) | skip view | `preview-tbd`, reason `closure_unsupported` |
| `some P` / `any P` / `AnyView` | skip view | `preview-tbd`, reason `generic_unsupported` |
| `T` with `Mock<T>.swift` present | `Mock<T>()` | `mock-found` |
| any other capitalized simple name — struct, class, or a protocol with no mock | `T()` | `concrete-init` |
| anything else (generic arguments, qualified names, tuples) | skip view | `preview-tbd`, reason `unsupported_init_signature:<T>` |

A protocol with no mock file therefore becomes `P()`; the parse smoke passes it and the SnapshotHost build fails on it. A stored property with a default value is left out of the inferred memberwise call, so a fully-defaulted view renders as `TypeName()`; an explicit `init`'s defaulted parameters still get an argument.

## Protocol mocks — convention

Detected by filename only — contents are never parsed — at `Source/Mocks/Mock<ProtocolName>.swift`, `Sources/Mocks/Mock<ProtocolName>.swift`, or `<ProjectDir>/Mocks/Mock<ProtocolName>.swift`. The file must declare a type named exactly `Mock<ProtocolName>` with a no-arg init:

```swift
// Source/Mocks/MockUserRepository.swift
struct MockUserRepository: UserRepository {
    init() { }
    func currentUser() -> User { .preview }
}
```

If the type is absent or its init takes args, `swift build` fails at SnapshotHost link time and the apple-canvas failure cascade catches it.

## Skipped views leave no trail in the file

A view with a parameter no rule satisfies is reported as `action: "skipped"`, `mock_strategy: "preview-tbd"` and the first failing parameter's reason; nothing is written to the source, so the JSON result (`.context/logs/preview-ensurer-<ts>.json` under apple-canvas) is the only record. A view whose only properties are wrapper-injected (§ Property wrappers) is not skipped: it gets `TypeName()`.

## Closure parameters

Closures are the most common reason a real-world view is skipped. Empty `{ }` closures are not synthesized because many must return a value rather than absorb an event (`onTap: () -> Void` would be fine, `transform: (Item) -> Item` is not).

## Property wrappers

| Wrapper | Treated as |
|---|---|
| `@Binding var x: T` | `Binding<T>` |
| `@ObservedObject var x: T` | `T` (usually an `ObservableObject` class) → concrete-init |
| `@State` / `@StateObject` / `@EnvironmentObject` / `@Environment` / `@FocusState` | left out of the call — by language rule these are not memberwise-init parameters |

## Generated block — template

4-space indentation (SwiftFormat default), preceded by a blank line; multi-line when the call carries ≥2 arguments, single-line otherwise.

```swift
#Preview {
    ContentView(
        text: .constant(""),
        repository: MockUserRepository()
    )
}

#Preview {
    SimpleView()
}
```

`preview_added.metadata.lines_added` counts the newlines added between the previous EOF and the new EOF — typically 4 for the `SimpleView` form (`\n#Preview {\n    SimpleView()\n}\n`).

## Cross-reference with audit enum

The emitted `mock_strategy` must be one of `"binding-constant"`, `"optional-nil"`, `"mock-found"`, `"preview-tbd"` — plus the implicit `"concrete-init"`, which the skill may emit though it is not in the spec's primary set. Consumers treat unknown values as `"preview-tbd"` for forward-compat.
