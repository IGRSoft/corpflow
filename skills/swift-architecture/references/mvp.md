# MVP

Passive View driven by Presenter commands, UIKit-native testability.

## Core Boundaries

- **Model**: Domain entities and business rules. No UI dependencies.
- **View**: Passive renderer executing Presenter commands. Owns zero logic.
- **Presenter**: Owns all presentation logic, maps domain to display output, drives View via protocol.
- **Services/Repositories**: Side-effect boundaries injected into Presenter.

Direction: View → Presenter (user actions). Presenter → View (protocol commands, one-way).

Key difference from MVVM: View holds no observable state — it passively executes commands.

## Feature Structure

```text
App/
  Features/
    Profile/
      ProfileViewController.swift   (View)
      ProfilePresenter.swift
      ProfileViewProtocol.swift
      ProfileViewData.swift
      ProfileAssembly.swift
  Navigation/
    AppCoordinator.swift
Domain/
  Entities/
  Repositories/
Data/
  Repositories/
```

## State Modeling

View protocol defines command methods. ViewData is display-ready:

```swift
@MainActor
protocol ProfileView: AnyObject {
    func showLoading(_ isLoading: Bool)
    func show(profile: ProfileViewData)
    func showError(message: String)
}

struct ProfileViewData: Equatable {
    let displayName: String
    let badgeText: String?
    let formattedJoinDate: String
}
```

`AnyObject` allows `weak` references. One command per distinct UI concern.

## Dependency Injection

Assembly wires dependencies and sets weak references:

```swift
enum ProfileAssembly {
    static func build(repository: ProfileRepository) -> UIViewController {
        let presenter = ProfilePresenter(repository: repository)
        let vc = ProfileViewController(presenter: presenter)
        presenter.view = vc
        return vc
    }
}
```

Set `presenter.view` after construction, not inside Presenter init. Inject concrete repos from composition root.

## Concurrency & Cancellation

Presenter tracks `loadTask: Task<Void, Never>?` and `latestRequestID: UUID?` for stale-response gating:

```swift
@MainActor
final class ProfilePresenter {
    weak var view: ProfileView?
    private let repository: ProfileRepository
    private var loadTask: Task<Void, Never>?
    private var latestRequestID: UUID?

    func load() {
        let requestID = UUID()
        latestRequestID = requestID
        loadTask?.cancel()
        view?.showLoading(true)
        loadTask = Task {
            do {
                let user = try await repository.fetchCurrentUser()
                try Task.checkCancellation()
                guard latestRequestID == requestID else { return }
                view?.show(profile: ProfileViewData(user: user))
            } catch is CancellationError { }
            catch {
                guard latestRequestID == requestID else { return }
                view?.showError(message: "Failed to load profile.")
            }
            guard latestRequestID == requestID else { return }
            view?.showLoading(false)
        }
    }
    deinit { loadTask?.cancel() }
}
```

## Navigation

MVP does not prescribe navigation. Pair with Coordinator: Presenter calls Router protocol, Coordinator implements navigation. ViewModels/Presenters receive navigation closures.

SwiftUI adapter: `@Observable` class conforming to ViewProtocol bridges Presenter to SwiftUI.

## Anti-Patterns

1. **View Contains Logic** — ViewController computes display strings or calls services. *Fix*: View is passive; forwards all actions to Presenter.
2. **Presenter Observes State** — uses `@Published` instead of direct commands. *Fix*: Presenter calls `view.showX()` explicitly.
3. **Bidirectional Strong References** — Presenter and View both hold strong refs. *Fix*: `weak var view: ProfileView?` in Presenter.
4. **No Request-Identity Guard** — stale responses overwrite current UI. *Fix*: track `latestRequestID` and guard after async return.
5. **Fat Presenter** — networking, caching, business logic in Presenter. *Fix*: delegate to services/interactors; Presenter orchestrates.

## Testing Strategy

Test Presenter with MockView and StubRepository. Verify command dispatch for success, failure, cancellation:

```swift
@MainActor
final class MockProfileView: ProfileView {
    var isLoading = false
    var shownViewData: ProfileViewData?
    var shownError: String?
    func showLoading(_ isLoading: Bool) { self.isLoading = isLoading }
    func show(profile: ProfileViewData) { shownViewData = profile }
    func showError(message: String) { shownError = message }
}

struct StubProfileRepository: ProfileRepository {
    var result: Result<User, Error>
    func fetchCurrentUser() async throws -> User { try result.get() }
}

@MainActor
final class ProfilePresenterTests: XCTestCase {
    func test_load_success_showsUserName() async {
        let user = User(id: UUID(), name: "Alice", isPremium: false, joinDate: .now)
        let view = MockProfileView()
        let presenter = ProfilePresenter(repository: StubProfileRepository(result: .success(user)))
        presenter.view = view
        presenter.load()
        await Task.yield()
        XCTAssertEqual(view.shownViewData?.displayName, "Alice")
    }

    func test_load_failure_showsError() async {
        let view = MockProfileView()
        let presenter = ProfilePresenter(repository: StubProfileRepository(result: .failure(TestError.notFound)))
        presenter.view = view
        presenter.load()
        await Task.yield()
        XCTAssertNotNil(view.shownError)
    }
}
```

## PR Review Checklist

- [ ] View contains no business logic, formatting, or service calls
- [ ] Presenter `view` property is `weak` and typed as protocol
- [ ] Presenter cancels previous task before new load
- [ ] All async Presenter-to-View calls guarded by request identity
- [ ] Dependencies injected via protocols — no singletons
- [ ] ViewData mapped by Presenter — View receives display-ready values
- [ ] Assembly wires module from outside
- [ ] Tests cover success, failure, and stale-cancellation paths
- [ ] SwiftUI adapter uses `@Observable` conforming to ViewProtocol
