# Reactive Architecture

Stream-driven features using Combine or RxSwift pipelines.

## Core Boundaries

- **Input**: User events and external signals (text changes, taps, WebSocket messages).
- **Pipeline**: Publisher/Observable chain with operators (debounce, switchToLatest, share).
- **State**: Published output consumed by UI.
- **View**: Binds to state. No pipeline logic.

Flow: `Input → Publisher chain → State → UI`

## Feature Structure

```text
App/
  Features/
    Search/
      SearchViewModel.swift      (Combine pipelines)
      SearchView.swift
      SearchService.swift        (protocol)
Domain/
  Services/
Data/
  LiveSearchService.swift
```

## State Modeling

```swift
enum SearchResultState: Equatable {
    case loaded([String])
    case failed(String)
}

final class SearchViewModel<S: Scheduler>: ObservableObject
where S.SchedulerTimeType == DispatchQueue.SchedulerTimeType {
    @Published var query = ""
    @Published private(set) var results: [String] = []
    private var cancellables = Set<AnyCancellable>()

    init(service: SearchService, scheduler: S) {
        $query
            .debounce(for: .milliseconds(300), scheduler: scheduler)
            .removeDuplicates()
            .map { service.search($0).replaceError(with: []) }
            .switchToLatest()
            .receive(on: scheduler)
            .sink { [weak self] in self?.results = $0 }
            .store(in: &cancellables)
    }
}
```

Inject scheduler for testability. In production, pass `DispatchQueue.main`.

## Dependency Injection

Service protocols injected into ViewModel/Presenter. Scheduler injected for testability:

```swift
protocol SearchService {
    func search(_ query: String) -> AnyPublisher<[String], Error>
}
```

## Concurrency & Cancellation

- `switchToLatest()` auto-cancels previous subscription on new input — the primary cancellation strategy
- `debounce` + `removeDuplicates` stabilizes noisy user input
- `share()` prevents duplicate side effects for multiple subscribers
- `receive(on: DispatchQueue.main)` for UI-bound state writes
- Store subscriptions in `Set<AnyCancellable>` / `DisposeBag` — no leaked subscriptions

**RxSwift mapping**: `AnyPublisher` ↔ `Observable`, `AnyCancellable` ↔ `DisposeBag`, `receive(on:)` ↔ `observe(on:)`.

## Navigation

Reactive architecture does not prescribe navigation. Keep pipelines in ViewModel/Presenter layer. Navigation via Coordinator or NavigationStack binding, same as MVVM.

## Anti-Patterns

1. **Nested Subscriptions** — subscribe inside subscribe. *Fix*: compose with `flatMap`/`switchToLatest`.
2. **Missing Cancellation** — subscriptions not stored, resources leak. *Fix*: `Set<AnyCancellable>` or `DisposeBag`.
3. **Business Logic in View** — View constructs pipelines and calls services. *Fix*: pipelines live in ViewModel/Presenter.
4. **UI Thread Violations** — state mutations off main thread. *Fix*: `receive(on: DispatchQueue.main)`.
5. **Unbounded Fan-Out** — many subscribers trigger duplicate side effects. *Fix*: `share()` on publishers with side effects.

## Testing Strategy

Test stream behavior with injected scheduler. Assert emitted state sequences, not operator internals:

```swift
final class SearchViewModelTests: XCTestCase {
    func test_queryEmitsResults() {
        let subject = PassthroughSubject<[String], Error>()
        let stub = StubSearchService { _ in subject.eraseToAnyPublisher() }
        let scheduler = DispatchQueue.test
        let vm = SearchViewModel(service: stub, scheduler: scheduler.eraseToAnyScheduler())

        var collected: [[String]] = []
        let c = vm.$results.dropFirst().sink { collected.append($0) }

        vm.query = "swift"
        scheduler.advance(by: .milliseconds(300))
        subject.send(["SwiftUI", "Swift"])
        subject.send(completion: .finished)
        scheduler.advance()

        XCTAssertEqual(collected, [["SwiftUI", "Swift"]])
        c.cancel()
    }

    func test_switchToLatest_ignoresStaleResponse() {
        let first = PassthroughSubject<[String], Error>()
        let second = PassthroughSubject<[String], Error>()
        let stub = StubSearchService { $0 == "sw" ? first.eraseToAnyPublisher() : second.eraseToAnyPublisher() }
        let scheduler = DispatchQueue.test
        let vm = SearchViewModel(service: stub, scheduler: scheduler.eraseToAnyScheduler())

        var collected: [[String]] = []
        let c = vm.$results.dropFirst().sink { collected.append($0) }

        vm.query = "sw"; scheduler.advance(by: .milliseconds(300))
        vm.query = "swift"; scheduler.advance(by: .milliseconds(300))
        first.send(["stale"]); second.send(["fresh"]); scheduler.advance()

        XCTAssertEqual(collected, [["fresh"]])
        c.cancel()
    }
}
```

## PR Review Checklist

- [ ] Streams composed without nested subscriptions
- [ ] Cancellation/disposal is lifecycle-safe
- [ ] UI-bound updates marshaled to main thread
- [ ] Operators match intent (debounce, throttle, switchToLatest, share)
- [ ] Views do not hold business pipeline logic
- [ ] Error handling keeps stream alive (catch/replaceError)
- [ ] Scheduler injected for deterministic testing
- [ ] Tests assert emitted state sequences
