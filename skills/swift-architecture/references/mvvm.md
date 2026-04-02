# MVVM

Screen-level state management with async effects for SwiftUI/UIKit.

## Core Boundaries

- **Model**: Domain entities and business rules. UI-framework independent.
- **View**: Renders state, forwards user intents. No service calls.
- **ViewModel**: Owns presentation state, maps domain to view data, coordinates effects.
- **Services/Repositories**: Side-effect boundaries injected via protocols.

Direction: View → ViewModel → Services (via protocols). Model has no dependency on View/ViewModel.

## Feature Structure

```text
App/
  Features/
    Feed/
      FeedView.swift
      FeedViewModel.swift
      FeedState.swift
      FeedViewData.swift
      FeedAssembly.swift
  Navigation/
    AppRouter.swift
Domain/
  Entities/
  UseCases/
Data/
  Repositories/
  API/
```

## State Modeling

Use explicit state types over boolean combinations:

```swift
enum Loadable<Value: Equatable>: Equatable {
    case idle
    case loading
    case loaded(Value)
    case failed(String)
}

struct FeedState: Equatable {
    var load: Loadable<Void> = .idle
    var items: [FeedItemViewData] = []
    var toast: ToastState?
}
```

Map domain models to `ViewData` structs for rendering — keep View free of formatting logic.

## Dependency Injection

Simple assembly per feature; evolve to app-level container as needed:

```swift
protocol FeedRepository {
    func fetchPage(cursor: String?) async throws -> FeedPage
}

enum FeedAssembly {
    static func makeViewModel() -> FeedViewModel {
        FeedViewModel(repository: LiveFeedRepository(api: .live))
    }
}
```

For larger apps, use a composition-root `AppContainer` protocol that owns shared dependency graphs.

## Concurrency & Cancellation

ViewModel stores `loadTask: Task<Void, Never>?` and cancels before each new request:

```swift
@MainActor @Observable
final class FeedViewModel {
    private(set) var state = FeedState()
    private let repository: FeedRepository
    private var loadTask: Task<Void, Never>?

    func load() {
        loadTask?.cancel()
        state.load = .loading
        loadTask = Task {
            do {
                let page = try await repository.fetchPage(cursor: nil)
                try Task.checkCancellation()
                state.items = page.items.map(FeedItemViewData.init)
                state.load = .loaded(())
            } catch is CancellationError { }
            catch { state.load = .failed(error.localizedDescription) }
        }
    }
    deinit { loadTask?.cancel() }
}
```

For expensive mapping, offload to `Task.detached` and commit final state on `@MainActor`.

## Navigation

**Path ownership tradeoffs**:
- **ViewModel-owned path**: Simplest SwiftUI wiring, mixes data+nav state
- **Router-owned path**: Keeps ViewModel focused on data/loading, extra types
- **Coordinator (UIKit/mixed)**: Best for multi-step flows and deep links

Model destinations as `Hashable` enum. Sheets as `Identifiable` enum with optional state on ViewModel.

Deep links: centralize in `DeepLinkHandler` / `AppRouter` that maps URLs to navigation state.

## Anti-Patterns

1. **God ViewModel** — networking, parsing, persistence all in one class. *Fix*: extract UseCases/Repositories; keep ViewModel focused on state and intent handling.
2. **Duplicate State** — `@State var items` and `viewModel.state.items` coexist. *Fix*: single source of truth in ViewModel.
3. **Stale Async Overwrite** — older response replaces newer state. *Fix*: cancel in-flight task before new request and check cancellation.
4. **Navigation with UIKit Types** — direct `UINavigationController` usage in ViewModel. *Fix*: inject Router/Coordinator protocol.
5. **Heavy Main-Actor Work** — expensive mapping on `@MainActor` blocks UI. *Fix*: offload CPU work off-main; assign final state on main actor.

## Testing Strategy

Test deterministic state transitions: success (`loading→loaded`), failure (`loading→failed`), cancellation (no stale overwrite), mapping correctness.

Use protocol stubs. Avoid sleep-based tests. Run `@MainActor` assertions via `await MainActor.run`.

```swift
actor ControlledFeedRepository: FeedRepository {
    private var continuations: [CheckedContinuation<FeedPage, Error>] = []
    func fetchPage(cursor: String?) async throws -> FeedPage {
        try await withCheckedThrowingContinuation { continuations.append($0) }
    }
    func resolveNext(with result: Result<FeedPage, Error>) {
        guard !continuations.isEmpty else { return }
        let c = continuations.removeFirst()
        switch result {
        case .success(let page): c.resume(returning: page)
        case .failure(let error): c.resume(throwing: error)
        }
    }
}

@MainActor
final class FeedViewModelTests: XCTestCase {
    func test_load_success_setsLoadedAndMapsItems() async {
        let repo = ControlledFeedRepository()
        let sut = FeedViewModel(repository: repo)
        sut.load()
        await repo.resolveNext(with: .success(FeedPage(items: [FeedItem(id: UUID(), title: "A")])))
        await Task.yield()
        XCTAssertEqual(sut.state.items.map(\.title), ["A"])
    }
}
```

## PR Review Checklist

- [ ] View does not call services directly
- [ ] ViewModel exposes explicit state model (not boolean flags)
- [ ] Dependencies injected via initializer — no singletons
- [ ] Async tasks have cancellation strategy
- [ ] Domain models mapped to ViewData — not directly in View
- [ ] Navigation destinations modeled as value types
- [ ] ViewModel does not import UIKit
- [ ] Deep links route through centralized router
- [ ] Tests cover success, failure, and cancellation
