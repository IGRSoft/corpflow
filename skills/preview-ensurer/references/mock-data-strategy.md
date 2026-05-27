# mock-data-strategy.md — Mock-arg derivation rules

Detailed derivation tree used by `preview-ensurer` to synthesize `TypeName(<args>)` for the generated `#Preview` block. Audit-strategy values match `dv-screenshot-capture § audit row schema` (`preview_added.metadata.mock_strategy`).

## Derivation tree

For each parameter of the target View's initializer (in declaration order), walk the tree top-down. First match wins.

```
parameter type T
│
├─ T matches Binding<U>
│   │
│   ├─ U == Bool           → .constant(false)              | binding-constant
│   ├─ U == Int            → .constant(0)                  | binding-constant
│   ├─ U == Double | Float → .constant(0)                  | binding-constant
│   ├─ U == String         → .constant("")                 | binding-constant
│   ├─ U is Optional<V>    → .constant(nil)                | binding-constant
│   ├─ U is Array<V>       → .constant([])                 | binding-constant
│   └─ U otherwise         → skip; preview-tbd            | preview-tbd
│       reason: "binding_complex_type:<U>"
│
├─ T matches Optional<U> / U?
│   └─ → nil                                               | optional-nil
│
├─ T is a concrete protocol existential (`some P` / `any P` / `P`)
│   │
│   ├─ Source/Mocks/Mock<P>.swift exists  → Mock<P>()      | mock-found
│   └─ otherwise                          → skip; preview-tbd | preview-tbd
│       reason: "no_mock_for_<P>"
│
├─ T is a concrete struct/class with synthesized no-arg init
│   └─ → T()                                                | concrete-init
│
├─ T is a closure type ((...) -> ... )
│   └─ → skip; preview-tbd                                  | preview-tbd
│       reason: "closure_unsupported"
│
├─ T is a generic / type-erased / opaque (e.g. AnyView, some Equatable)
│   └─ → skip; preview-tbd                                  | preview-tbd
│       reason: "generic_unsupported"
│
└─ T otherwise
    └─ → skip; preview-tbd                                  | preview-tbd
        reason: "unsupported_init_signature"
```

## Bindings — default value selection

Bindings carry a value of type `U` whose default the synthesizer must pick. The defaults are conservative — they should NEVER cause a runtime crash in a SwiftUI body that reads them.

| `U` | Default | Rationale |
|---|---|---|
| `Bool` | `false` | Off/false state is the safer preview default |
| `Int` | `0` | Identity element |
| `Double`, `Float`, `CGFloat` | `0` (or `0.0`) | Identity element |
| `String` | `""` | Empty string — most labels handle this without index-out-of-range crashes |
| `Optional<V>` | `nil` | `nil` works for any Optional |
| `Array<V>` | `[]` | Empty array — preview can render "no items" state |
| Anything else | — | skip with `preview-tbd` |

## Protocol mocks — convention

`preview-ensurer` looks for a file at:

```
Source/Mocks/Mock<ProtocolName>.swift
Sources/Mocks/Mock<ProtocolName>.swift     ← alternate root
<ProjectDir>/Mocks/Mock<ProtocolName>.swift ← also accepted
```

The file is detected by filename only — its contents are not parsed. It MUST declare a type `Mock<ProtocolName>` with a no-arg init, e.g.:

```swift
// Source/Mocks/MockUserRepository.swift
import Foundation

struct MockUserRepository: UserRepository {
    init() { }
    func currentUser() -> User { .preview }
}
```

If the file exists but doesn't declare the type or the type has args, `swift build` will fail at SnapshotHost link time — the failure cascade in apple-canvas catches it.

## When to skip vs when to emit `preview-tbd:`

Both `skip` and emitting a `// preview-tbd:` comment result in `action: "skipped"`. The differentiator is the comment trail:

- **Always emit `// preview-tbd:` comment**: when the View has at least one parameter we could not satisfy.
- **Skip silently (no comment)**: when the View is unambiguously not preview-able (e.g., requires `@Environment` injection only, or already has a `#Preview` we left alone — A4 path).

The comment serves as a user-visible TODO. Format:

```swift
// preview-tbd: <reason> — see preview-ensurer skill
// e.g.:
// preview-tbd: no_mock_for_UserRepository — create Source/Mocks/MockUserRepository.swift
// preview-tbd: closure_unsupported — onTap parameter is a closure
```

The comment is appended at the END of the file (same position generated `#Preview` would have gone), so a future scan can either notice + fix the TODO or convert it into a real `#Preview` once the user provides the mock.

## Closure parameters

Closures are the most common reason a real-world view is skipped. v1 does NOT try to synthesize `{ }` empty closures because they typically have side effects (`onTap: () -> Void` is fine, but `transform: (Item) -> Item` is not).

Future work (`args.closure_strategy: "empty" | "skip"`) is documented but out of v1 scope.

## Property wrappers — heuristics

| Wrapper | Treat parameter type as | Notes |
|---|---|---|
| `@Binding var x: T` | `Binding<T>` | Standard heuristic |
| `@State var x: T` | (not an init param; ignore — synthesized init excludes `@State`) | |
| `@StateObject var x: T` | (not an init param; ignore) | |
| `@ObservedObject var x: T` | `T` — typically a `ObservableObject` class; treat as concrete-init | |
| `@EnvironmentObject var x: T` | (not an init param; ignore — provided via env at preview-render time) | |
| `@Environment(\.X) var x` | (not an init param; ignore) | |

The synthesizer relies on Swift's memberwise init: `@State`, `@StateObject`, `@EnvironmentObject`, `@Environment` are NOT init parameters by language rule, so they don't appear in the parameter list.

## Optional parameters with default values

```swift
struct ContentView: View {
    var title: String = "Default"
    var body: some View { Text(title) }
}
```

If a parameter has a default value (Swift memberwise-init-with-defaults), the synthesizer omits it from the generated call:

```swift
#Preview {
    ContentView()   // title defaulted
}
```

This applies recursively — fully-defaulted views render as `TypeName()`.

## Generated block — full template

For a View with 2 parameters (one `Binding<String>`, one concrete class):

```swift

#Preview {
    ContentView(
        text: .constant(""),
        repository: MockUserRepository()
    )
}
```

Indentation: 4 spaces (SwiftFormat default). Multi-line if argument count ≥ 2; single-line otherwise:

```swift

#Preview {
    SimpleView()
}
```

## Lines-added metric

The `preview_added.metadata.lines_added` value counts the number of newline characters added between the previous EOF and the new EOF. For the SimpleView template above, that's typically 4 (`\n#Preview {\n    SimpleView()\n}\n`).

## Cross-reference with audit enum

The `mock_strategy` value emitted in the `preview_added` audit row must be one of:

- `"binding-constant"`
- `"optional-nil"`
- `"mock-found"`
- `"preview-tbd"`

(Plus the implicit `"concrete-init"` — accepted but not enumerated in the spec's primary set. The skill MAY emit `"concrete-init"`; consumers should treat unknown values as `"preview-tbd"` for forward-compat.)
