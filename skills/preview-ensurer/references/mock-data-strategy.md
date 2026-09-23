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

| Parameter type `T` | Generated arg | `mock_strategy` |
|---|---|---|
| `Optional<U>` / `U?` | `nil` | `optional-nil` |
| protocol existential (`some P` / `any P` / `P`) with `Mock<P>.swift` present | `Mock<P>()` | `mock-found` |
| protocol existential, no mock file | skip view | `preview-tbd`, reason `no_mock_for_<P>` |
| concrete struct/class with a synthesized no-arg init | `T()` | `concrete-init` |
| closure (`(...) -> ...`) | skip view | `preview-tbd`, reason `closure_unsupported` |
| generic / type-erased / opaque (`AnyView`, `some Equatable`) | skip view | `preview-tbd`, reason `generic_unsupported` |
| anything else | skip view | `preview-tbd`, reason `unsupported_init_signature` |

A parameter that carries a default value (memberwise-init-with-defaults) is omitted from the generated call; a fully-defaulted view therefore renders as `TypeName()`.

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

## Skip silently vs emit `// preview-tbd:`

Both paths report `action: "skipped"`; the differentiator is the comment trail.

- **Emit the comment** when the View has at least one parameter we could not satisfy.
- **Skip silently** when the View is unambiguously not preview-able (e.g. `@Environment`-injection only) or already has a preview we left alone.

The comment is a user-visible TODO, appended at the end of the file — the position the generated `#Preview` would have taken — so a later scan can fix it or convert it into a real preview:

```swift
// preview-tbd: no_mock_for_UserRepository — create Source/Mocks/MockUserRepository.swift
// preview-tbd: closure_unsupported — onTap parameter is a closure
```

## Closure parameters

Closures are the most common reason a real-world view is skipped. Empty `{ }` closures are not synthesized because many must return a value rather than absorb an event (`onTap: () -> Void` would be fine, `transform: (Item) -> Item` is not).

## Property wrappers

| Wrapper | Treated as |
|---|---|
| `@Binding var x: T` | `Binding<T>` |
| `@ObservedObject var x: T` | `T` (usually an `ObservableObject` class) → concrete-init |
| `@State` / `@StateObject` / `@EnvironmentObject` / `@Environment` | ignored — by language rule these are not memberwise-init parameters |

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
