# MVI

Strict unidirectional flow with deterministic state transitions.

## Core Boundaries

- **State**: Value-type single source of truth. Equatable, serializable.
- **Intent**: User-driven input only (taps, gestures, lifecycle).
- **Action**: Internal events and effect results fed back to reducer.
- **Effect**: Encapsulated async side effects executed by Store.
- **Reducer**: Pure function — mutates state, returns optional Effect.

Flow: `Intent → Reducer → State + Effect → Action → Reducer`

## Feature Structure

```text
App/
  Features/
    Counter/
      CounterState.swift
      CounterIntent.swift
      CounterAction.swift
      CounterReducer.swift
      CounterStore.swift
      CounterView.swift
Domain/
  Services/
```

## State Modeling

```swift
enum Loadable<Value: Equatable>: Equatable {
    case idle, loading, loaded(Value), failed(String)
}

struct CounterState: Equatable {
    var load: Loadable<Int> = .idle
    var count: Int { guard case .loaded(let v) = load else { return 0 }; return v }
}

enum CounterIntent { case incrementTapped, decrementTapped, resetTapped }
enum CounterAction {
    case incrementResponse(Result<Int, Error>)
    case decrementResponse(Result<Int, Error>)
}
```

Store only canonical state. Derive computed values in View — never store `isEven` alongside `count`.

## Dependency Injection

Service protocols injected into Store or passed to reducer. Two approaches:

- **Pragmatic**: Pass service into `reduce(state:intent:service:)` — simple but environment-coupled.
- **Pure**: `reduce` returns effect descriptors; separate `run(effect:service:)` executes them.

```swift
protocol CounterServicing {
    func increment() async throws -> Int
    func decrement() async throws -> Int
}
```

## Concurrency & Cancellation

Store manages tasks by effect ID. Request ID versioning guards stale responses:

```swift
enum Effect<Action> {
    case none
    case run(() async throws -> Action)
    case cancellable(id: AnyHashable, () async throws -> Action)
}
```

Store cancels previous task for same ID before starting new one. Map expected service failures to explicit failure Actions — reserve `onUnexpectedError` for true bugs.

For out-of-order responses, track `latestRequestID: UUID?` in State and guard in Action reducer:
```swift
case .response(let requestID, .success(let results)):
    guard requestID == state.latestRequestID else { return }
    state.results = results
```

## Navigation

MVI itself does not prescribe navigation. Pair with Coordinator pattern or emit navigation Actions that the parent/router handles.

SwiftUI: Store-bound views observe state. UIKit: subscribe once, render from state, map events to Intents.

## Anti-Patterns

1. **Side Effects in Reducer** — network/analytics calls in reducer branch. *Fix*: emit Effect and handle through action loop.
2. **Merged Intent/Action** — single enum for both user input and effect output. *Fix*: separate Intent and Action enums.
3. **Multiple Sources of Truth** — local `@State` mirrors store state. *Fix*: canonical state in Store only.
4. **Stored Derived Fields** — persisted `isEven` with `count`. *Fix*: compute derived properties in View.
5. **Monolithic Reducer** — large switch spanning unrelated domains. *Fix*: split reducers by feature and compose with action-mapping.

## Testing Strategy

Test intent reducer transitions (state + effect returned) and action reducer (state mutation). Verify cancellation and stale-response handling with request ID.

```swift
struct StubCounterService: CounterServicing {
    func increment() async throws -> Int { 1 }
    func decrement() async throws -> Int { 0 }
}

final class CounterReducerTests: XCTestCase {
    func test_intentIncrement_setsLoading_andReturnsEffect() {
        var state = CounterState()
        let effect = reduce(state: &state, intent: .incrementTapped, service: StubCounterService())
        XCTAssertEqual(state.load, .loading)
        XCTAssertNotNil(effect)
    }

    func test_staleResponse_isIgnored() {
        let latestID = UUID()
        var state = SearchState(latestRequestID: latestID, results: ["current"])
        reduce(state: &state, action: .response(requestID: UUID(), .success(["old"])))
        XCTAssertEqual(state.results, ["current"])
    }
}
```

## PR Review Checklist

- [ ] State is value-based and canonical (no stored derived fields)
- [ ] Reducers are deterministic and side-effect free
- [ ] Intent and Action are separate enums
- [ ] Effects isolated and mapped back into Actions
- [ ] Request ID versioning for concurrent requests
- [ ] Expected failures map to explicit Actions
- [ ] View sends Intents only — no direct state mutation
- [ ] Reducer tests cover success, failure, and cancellation
- [ ] Composed reducers use action-mapping, no shared mutable state
