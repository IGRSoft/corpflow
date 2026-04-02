# Coordinator

Navigation decoupling, reusable flows, and deep linking.

## Core Boundaries

- **Coordinator**: Owns one navigation flow. Creates screens, passes dependencies, decides transitions.
- **Screen (View/ViewModel)**: Emits navigation events via closures. Never pushes/presents directly.
- **NavigationRouter** (UIKit): Thin wrapper around `UINavigationController`.
- **Navigation State** (SwiftUI): Value-type path + sheet on `@Observable` coordinator.

Hierarchy: `AppCoordinator → AuthCoordinator → MainCoordinator → ProfileCoordinator`

Coordinator is a navigation layer, not a standalone architecture. Pair with MVVM, MVP, or TCA for presentation.

## Feature Structure

```text
App/
  AppCoordinator.swift
  Coordinators/
    AuthCoordinator.swift
    MainCoordinator.swift
    ProfileCoordinator.swift
  Features/
    Auth/
      LoginViewModel.swift
      LoginView.swift
    Profile/
      ProfileViewModel.swift
      ProfileView.swift
Navigation/
  Coordinator.swift          (protocol)
  NavigationRouter.swift     (UIKit helper)
```

## State Modeling

Coordinator protocol with child retention:

```swift
@MainActor
protocol Coordinator: AnyObject {
    var childCoordinators: [Coordinator] { get set }
    func start()
}

extension Coordinator {
    func addChild(_ coordinator: Coordinator) {
        childCoordinators.append(coordinator)
        coordinator.start()
    }
    func removeChild(_ coordinator: Coordinator) {
        childCoordinators.removeAll { $0 === coordinator }
    }
}
```

SwiftUI navigation state as value types:

```swift
enum AppDestination: Hashable { case profile(UUID), editProfile(UUID) }
enum AppSheet: Identifiable { case settings; var id: String { "\(self)" } }

@MainActor @Observable
final class AppCoordinator: Coordinator {
    var childCoordinators: [Coordinator] = []
    var path: [AppDestination] = []
    var sheet: AppSheet?

    func showProfile(userID: UUID) { path.append(.profile(userID)) }
    func showSettings() { sheet = .settings }
    func pop() { guard !path.isEmpty else { return }; path.removeLast() }
    func dismissSheet() { sheet = nil }
    func start() { }
}
```

## Dependency Injection

Coordinators receive repositories/services and pass them to child coordinators and ViewModels:

```swift
init(router: NavigationRouter, userRepository: UserRepository) {
    self.router = router
    self.userRepository = userRepository
}
```

ViewModels receive navigation closures, not coordinator references:
```swift
let viewModel = ProfileViewModel(
    repository: userRepository,
    onEditTapped: { [weak self] in self?.showEditProfile() }
)
```

## Concurrency & Cancellation

Coordinators do not own async work — they delegate to child ViewModels/Presenters. Navigation state mutations are synchronous on `@MainActor`.

## Navigation

**UIKit**: NavigationRouter wraps `UINavigationController` with push/present/pop methods. Coordinator calls router.

**SwiftUI**: `NavigationStack(path: $coordinator.path)` + `.navigationDestination(for:)` + `.sheet(item: $coordinator.sheet)`.

**Deep Linking**: Centralized `DeepLinkHandler` parses URL → destination enum, updates coordinator state:

```swift
@MainActor
final class DeepLinkHandler {
    private let coordinator: AppCoordinator
    func handle(url: URL) {
        guard url.scheme == "myapp" else { return }
        switch url.host {
        case "profile":
            guard let id = extractUUID(from: url) else { return }
            coordinator.path = [.profile(id)]
        case "settings":
            coordinator.sheet = .settings
        default: break
        }
    }
}
```

## Anti-Patterns

1. **ViewController Pushes Itself** — `navigationController?.pushViewController(...)` in VC. *Fix*: emit closure/delegate; Coordinator handles navigation.
2. **Child Retained by Local Variable** — child coordinator deallocated after `start()`. *Fix*: `addChild()` before `start()` to retain in `childCoordinators`.
3. **Navigation Logic Scattered** — push/present calls across multiple ViewControllers. *Fix*: centralize in Coordinator.
4. **Deep Linking Bypasses Coordinator** — AppDelegate pushes views directly. *Fix*: route all deep links through DeepLinkHandler → coordinator state.
5. **Coordinator Contains Business Logic** — API calls, validation in Coordinator. *Fix*: navigation only; business logic in ViewModel/UseCase.

## Testing Strategy

Test by verifying navigation state changes. Use SpyNavigationRouter for UIKit, direct property inspection for SwiftUI:

```swift
@MainActor
final class AppCoordinatorTests: XCTestCase {
    func test_showProfile_appendsDestination() {
        let coordinator = AppCoordinator(userRepository: StubUserRepository())
        let id = UUID()
        coordinator.showProfile(userID: id)
        XCTAssertEqual(coordinator.path, [.profile(id)])
    }

    func test_pop_removesLastDestination() {
        let coordinator = AppCoordinator(userRepository: StubUserRepository())
        coordinator.path = [.profile(UUID()), .editProfile(UUID())]
        coordinator.pop()
        XCTAssertEqual(coordinator.path.count, 1)
    }

    func test_deepLink_unknownScheme_noChange() {
        let coordinator = AppCoordinator(userRepository: StubUserRepository())
        let handler = DeepLinkHandler(coordinator: coordinator)
        handler.handle(url: URL(string: "https://example.com")!)
        XCTAssertTrue(coordinator.path.isEmpty)
    }
}
```

UIKit: `SpyNavigationRouter` tracks `pushedViewControllers` and `presentedViewControllers`.

## PR Review Checklist

- [ ] Each coordinator owns one clearly scoped flow
- [ ] Child coordinators retained in `childCoordinators` before `start()`
- [ ] Children removed when flow completes
- [ ] ViewModels receive navigation closures — not coordinator references
- [ ] Navigation state modeled as value types (Hashable path, Identifiable sheet)
- [ ] Deep links route through coordinator, not directly to views
- [ ] No push/present calls in ViewControllers or ViewModels
- [ ] Tests verify state changes without UI presentation timing
