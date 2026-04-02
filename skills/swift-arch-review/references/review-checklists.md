# Architecture Review Checklists

Per-pattern PR review checklists. Apply the checklist matching the detected architecture pattern.

## MVVM

- [ ] ViewModel owns all state; View has zero business logic
- [ ] State uses explicit modeling (e.g., `Loadable<T>` enum) — no boolean flags for loading/error
- [ ] ViewModel exposes `ViewData` structs for rendering — no domain models in View
- [ ] In-flight Task is cancelled before starting a new one (no stale overwrites)
- [ ] Navigation logic lives in Coordinator or Router — not in ViewModel
- [ ] Dependencies injected via initializer — no singletons or service locators
- [ ] View binds to ViewModel properties — no manual state synchronization
- [ ] Unit tests cover success, failure, cancellation, and mapping paths
- [ ] `@MainActor` applied to ViewModel or UI-mutating methods

## MVI

- [ ] Intent (user input) and Action (effect result) are separate enums
- [ ] Reducer is a pure function — no side effects, no async calls inside
- [ ] Effects return Actions through structured async — not direct state mutation
- [ ] Request ID versioning guards against stale responses in reducer
- [ ] Store manages Task cancellation by effect ID
- [ ] Expected service failures map to explicit Actions — not thrown errors
- [ ] State has no stored derived/computed fields (compute in View)
- [ ] Tests verify deterministic state transitions with controlled services
- [ ] Composed reducers use action-mapping — no shared mutable state

## TCA

- [ ] Feature uses `@Reducer` macro + `@ObservableState` struct
- [ ] Dependencies injected via `@Dependency` — never stored in State
- [ ] No reference types in State (only value types, `IdentifiedArrayOf`)
- [ ] Effects use `.cancellable(id:cancelInFlight:true)` for replaceable requests
- [ ] Navigation modeled with `@Presents` + destination `State` enum
- [ ] No business logic in View — all in Reducer body
- [ ] TestStore tests with `withDependencies` for controlled mocking
- [ ] Tests verify `send()` → state assertion → `receive()` for effects
- [ ] CancellationError handled gracefully in `.run` effects

## Clean Architecture

- [ ] Domain layer has zero framework imports (no SwiftUI, UIKit, Foundation networking)
- [ ] Dependency rule: inner layers never import outer layers
- [ ] Repository protocols defined in Domain — implementations in Data
- [ ] DTOs mapped to domain entities at data boundary — never leak to presentation
- [ ] Use cases orchestrate business logic via repository protocols
- [ ] Composition root / assembly layer wires all concrete dependencies
- [ ] `async let` used for parallel independent fetches
- [ ] Cancellation propagates through `try await` chains
- [ ] Tests mock at repository boundary — no real network/DB

## Reactive

- [ ] Input → pipeline → state → UI flow is clear and linear
- [ ] `switchToLatest()` used for request replacement (no nested subscriptions)
- [ ] `debounce` + `removeDuplicates` applied to user input streams
- [ ] `receive(on: DispatchQueue.main)` for UI-bound state writes
- [ ] `share()` prevents duplicate side effects on multiple subscribers
- [ ] Error recovery in stream boundaries (`catch` / `replaceError`) — stream stays alive
- [ ] Subscriptions stored in `Set<AnyCancellable>` / `DisposeBag` — no leaked subscriptions
- [ ] Tests use injected scheduler (`DispatchQueue.test`) for deterministic timing
- [ ] No business logic in View layer — pipelines live in ViewModel/Presenter

## MVP

- [ ] View protocol defines command methods (`showLoading()`, `show(data:)`, `showError()`)
- [ ] View is fully passive — forwards all user actions to Presenter
- [ ] Presenter uses `weak var view` to avoid retain cycles
- [ ] Request ID versioning prevents stale response overwrites
- [ ] ViewData mapped by Presenter — View receives display-ready values only
- [ ] Assembly function wires dependencies and sets weak references
- [ ] No observable state in View — driven entirely by protocol commands
- [ ] Tests use MockView implementing ViewProtocol to verify Presenter behavior
- [ ] SwiftUI adapter uses `@Observable` conforming to ViewProtocol

## Coordinator

- [ ] Screens emit events/closures — Coordinator decides what happens next
- [ ] `childCoordinators` array retains children — no premature deallocation
- [ ] `addChild()` called before `start()` on child coordinators
- [ ] Navigation state modeled as value types (Hashable path, Identifiable sheet)
- [ ] Deep linking handled by centralized `DeepLinkHandler` updating coordinator state
- [ ] No push/present calls in ViewControllers or ViewModels
- [ ] Child coordinator removed when flow completes (cleanup)
- [ ] ViewModels receive navigation closures — not coordinator references
- [ ] Tests verify state changes (path append, sheet set) without UI
