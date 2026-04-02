# TCA (The Composable Architecture)

Strict unidirectional flow with strong composition and TestStore-driven testing.

## Core Boundaries

- **State**: `@ObservableState` value-type struct. Equatable.
- **Action**: Enum of all events (user actions + effect results).
- **Reducer**: `@Reducer` macro — mutates state, returns Effects.
- **Effect**: Async side effects returning Actions. Built-in cancellation.
- **Dependencies**: Injected via `@Dependency`, never in State.

Flow: `View → store.send(Action) → Reducer → State + Effect → Action`

## Feature Structure

```text
App/
  Features/
    Counter/
      CounterFeature.swift   (@Reducer + State + Action)
      CounterView.swift
  Dependencies/
    NumberFactClient.swift
```

## State Modeling

```swift
@Reducer
struct CounterFeature {
    enum CancelID { case fact }

    @ObservableState
    struct State: Equatable {
        var count = 0
        var isLoading = false
        @Presents var alert: AlertState<Action.Alert>?
    }

    enum Action: Equatable {
        case incrementTapped, decrementTapped, factButtonTapped
        case factResponse(Result<String, FactError>)
        case alert(PresentationAction<Alert>)
        enum Alert: Equatable {}
    }
}
```

Only value types in State. Use `IdentifiedArrayOf` for collections with stable identity.

## Dependency Injection

Use `DependencyKey` protocol. Provide `liveValue` and `testValue`:

```swift
struct NumberFactClient {
    var fetch: @Sendable (Int) async throws -> String
}

extension NumberFactClient: DependencyKey {
    static let liveValue = Self(fetch: { "\($0) is great." })
    static let testValue = Self(fetch: { _ in "Test fact" })
}
```

Access in reducer via `@Dependency(\.numberFact)`. Never place dependencies in State or call singletons.

## Concurrency & Cancellation

Use `.run { send in }` for async work. Add `.cancellable(id:cancelInFlight:true)` for replaceable requests:

```swift
case .factButtonTapped:
    state.isLoading = true
    let n = state.count
    return .run { send in
        do {
            let fact = try await numberFact.fetch(n)
            await send(.factResponse(.success(fact)))
        } catch is CancellationError { }
        catch { await send(.factResponse(.failure(.unavailable))) }
    }
    .cancellable(id: CancelID.fact, cancelInFlight: true)
```

## Navigation

Model navigation in State, drive through Actions:
- `@Presents var alert: AlertState<Action.Alert>?`
- `destination: Destination.State?` with `.ifLet` reducer
- Keep navigation decisions in reducers; views stay declarative.

## Anti-Patterns

1. **Massive Feature** — giant reducer handling unrelated domains. *Fix*: split into child reducers via `Scope`.
2. **Reference Types in State** — classes or actors in State break value semantics. *Fix*: structs, enums, `IdentifiedArrayOf` only.
3. **Business Work in Views** — views call services or transform data. *Fix*: all logic in Reducer; Views only `store.send()`.
4. **Side Effects in Reducer** — inline analytics/network without Effect boundary. *Fix*: route through `.run` and dependencies.
5. **Duplicate State** — local `@State` mirrors store state. *Fix*: single source of truth in Store.
6. **Over-Observing** — broad observation triggers unnecessary re-renders. *Fix*: scope to substate.
7. **Missing Cancellation** — overlapping effects overwrite current intent. *Fix*: `.cancellable(id:cancelInFlight:true)`.

## Testing Strategy

Use `TestStore` for deterministic action/state assertions. Cover success, failure, and cancellation:

```swift
@MainActor
final class CounterFeatureTests: XCTestCase {
    func testFactSuccess() async {
        let store = TestStore(initialState: CounterFeature.State()) {
            CounterFeature()
        } withDependencies: {
            $0.numberFact.fetch = { _ in "42 is great" }
        }
        await store.send(.factButtonTapped) { $0.isLoading = true }
        await store.receive(.factResponse(.success("42 is great"))) {
            $0.isLoading = false
            $0.alert = AlertState { TextState("42 is great") }
        }
    }

    func testCancellation_replacesInFlightRequest() async {
        let clock = TestClock()
        let store = TestStore(initialState: CounterFeature.State()) {
            CounterFeature()
        } withDependencies: {
            $0.numberFact.fetch = { _ in try await clock.sleep(for: .seconds(1)); return "fact" }
        }
        await store.send(.factButtonTapped) { $0.isLoading = true }
        await store.send(.factButtonTapped) // cancels first
        await clock.advance(by: .seconds(1))
        await store.receive(.factResponse(.success("fact"))) { $0.isLoading = false; $0.alert = AlertState { TextState("fact") } }
    }
}
```

## PR Review Checklist

- [ ] State is value-based and equatable
- [ ] Reducer avoids direct side effects
- [ ] Dependencies injected via `@Dependency` and overrideable in tests
- [ ] Effects have `.cancellable(id:cancelInFlight:)` where needed
- [ ] Features compose with `Scope`/`forEach`
- [ ] Navigation modeled in State (`@Presents`, destination enum)
- [ ] Tests cover success, failure, and cancellation flows
- [ ] Views render and send actions only — no business logic
