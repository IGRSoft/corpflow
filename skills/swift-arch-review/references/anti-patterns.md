# Architecture Anti-Patterns Catalog

Consolidated anti-patterns across 7 Swift architecture patterns. Each entry: name, detection signal, fix direction.

## MVVM

1. **God ViewModel** — ViewModel handles multiple features, hundreds of lines, mixed concerns.
   *Fix*: Split into focused ViewModels per feature; extract services for shared logic.

2. **Duplicate State** — Same data stored in both Model and ViewModel, updated separately.
   *Fix*: Single source of truth in ViewModel; derive View state from domain models.

3. **Stale Async Overwrite** — New request starts without cancelling in-flight task; old response overwrites new.
   *Fix*: Cancel previous Task before starting new one; or use request ID versioning.

4. **Navigation in ViewModel** — ViewModel imports UIKit or creates views for navigation.
   *Fix*: Move navigation to Coordinator or Router; ViewModel exposes navigation intents only.

5. **Heavy Main-Actor Work** — Expensive computation runs on `@MainActor`, blocking UI.
   *Fix*: Offload to background task; only publish final result on `@MainActor`.

## MVI

1. **Side Effects in Reducer** — Reducer performs async calls, network requests, or state mutations beyond return.
   *Fix*: Reducer must be pure; return Effects that the Store executes.

2. **Merged Intent/Action** — Single enum used for both user input and effect results.
   *Fix*: Separate Intent (user input) from Action (effect results); distinct reducer paths.

3. **Duplicate State** — Same data stored in Store and child components.
   *Fix*: Single source of truth in Store State; child views observe Store.

4. **Stored Derived Fields** — Computed values stored in State (e.g., `isButtonEnabled` alongside raw data).
   *Fix*: Compute derived values in View from raw State; never store what can be derived.

5. **Monolithic Reducer** — Single massive reducer handles all app-wide actions.
   *Fix*: Compose feature-level reducers with action-mapping combinators.

## TCA

1. **Massive Feature** — Single feature reducer handles dozens of actions with deep nesting.
   *Fix*: Break into child features composed with `Scope` and `ifLet`.

2. **Reference Types in State** — Classes or actors stored in State, breaking value semantics.
   *Fix*: Use only structs, enums, and `IdentifiedArrayOf` in State.

3. **Business Work in Views** — Views contain logic, async calls, or direct dependency access.
   *Fix*: All logic in Reducer; Views only `store.send()` actions and observe state.

4. **Side Effects in Reducer** — Synchronous side effects or mutations outside `Effect.run`.
   *Fix*: All side effects go through `.run { send in }` or `.publisher`.

5. **Duplicate State** — Parent and child store same data; manual sync required.
   *Fix*: Use `Scope` to derive child state from parent; single source of truth.

6. **Over-Observing** — View observes entire feature state when it only needs a subset.
   *Fix*: Use `@ObservableState` with fine-grained observation or scope to substate.

7. **Missing Cancellation** — `.run` effects without `.cancellable(id:cancelInFlight:true)` on replaceable requests.
   *Fix*: Add `.cancellable(id: CancelID.x, cancelInFlight: true)` for search/load requests.

## Clean Architecture

1. **God Use Case** — Single use case orchestrates multiple unrelated features.
   *Fix*: One use case per business operation; compose at the application layer.

2. **Presentation Imports Data** — Presentation layer directly imports Data layer types.
   *Fix*: Presentation depends only on Domain; Data layer accessed through repository protocols.

3. **Domain Depends on Frameworks** — Domain entities import SwiftUI, UIKit, or Foundation networking.
   *Fix*: Domain contains only pure Swift types and protocols; no framework imports.

4. **Repository Leaks DTOs** — Data Transfer Objects exposed beyond the Data layer boundary.
   *Fix*: Map DTOs to domain entities at the repository boundary using mappers.

5. **Testing Through Real Infrastructure** — Tests hit real network or database instead of stubs.
   *Fix*: Inject stub repositories conforming to domain protocols; test use-case logic in isolation.

## Reactive

1. **Nested Subscriptions** — Subscribe-inside-subscribe creating callback-like nesting.
   *Fix*: Use `flatMap` / `switchToLatest()` for dependent operations; keep pipelines linear.

2. **Missing Cancellation** — Subscriptions not stored in cancellable set; resources leak.
   *Fix*: Store all subscriptions in `Set<AnyCancellable>` or `DisposeBag`.

3. **Business Logic in View** — View layer contains Combine/Rx pipelines and transformations.
   *Fix*: Move pipelines to ViewModel/Presenter; View only observes published state.

4. **UI Thread Violations** — State mutations dispatched without `receive(on: DispatchQueue.main)`.
   *Fix*: Add `.receive(on: DispatchQueue.main)` before state writes; or use `@MainActor`.

5. **Unbounded Fan-Out** — Publisher consumed by many subscribers without `share()`, causing duplicate side effects.
   *Fix*: Apply `share()` to publishers with side effects consumed by multiple subscribers.

## MVP

1. **View Contains Logic** — ViewController makes decisions, transforms data, or calls services directly.
   *Fix*: View is passive; forwards all actions to Presenter; only executes display commands.

2. **Presenter Observes State** — Presenter uses `@Published` or reactive bindings instead of direct commands.
   *Fix*: Presenter calls `view.showX()` commands explicitly; no observable state pattern.

3. **Bidirectional Strong References** — Both Presenter and View hold strong references to each other.
   *Fix*: Presenter uses `weak var view: ViewProtocol?`; View holds strong ref to Presenter.

4. **No Request-Identity Guard** — Stale network responses overwrite current UI state.
   *Fix*: Track `latestRequestID: UUID?`; guard against mismatched IDs after async return.

5. **Fat Presenter** — Presenter handles networking, caching, and business logic directly.
   *Fix*: Extract business logic to services/interactors; Presenter orchestrates and delegates.

## Coordinator

1. **ViewController Pushes Itself** — ViewController calls `navigationController?.pushViewController`.
   *Fix*: ViewController emits events/closures; Coordinator handles all navigation.

2. **Child Retained Only by Local Variable** — Child coordinator deallocated after `start()` returns.
   *Fix*: Call `addChild(coordinator)` before `start()` to retain in `childCoordinators`.

3. **Navigation Logic Scattered** — Push/present calls spread across multiple ViewControllers.
   *Fix*: Centralize all navigation in Coordinator; screens only emit navigation intents.

4. **Deep Linking Bypasses Coordinator** — Deep link handler directly presents views instead of updating coordinator state.
   *Fix*: `DeepLinkHandler` maps URL to destination enum; Coordinator applies state change.

5. **Coordinator Contains Business Logic** — Coordinator performs API calls, data processing, or validation.
   *Fix*: Coordinator handles navigation only; business logic belongs in ViewModel/Presenter/UseCase.
