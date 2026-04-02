# Clean Architecture

Strict layer boundaries with use-case-driven business logic and replaceable infrastructure.

## Core Boundaries

- **Entities (Domain)**: Pure Swift domain models and business rules. No framework imports.
- **Use Cases**: Orchestrate business actions through repository protocols.
- **Data (Adapters)**: Repository implementations, API clients, persistence, DTO mapping.
- **Presentation**: Views, ViewModels/Presenters that call use cases.
- **App**: Composition root, DI wiring, bootstrap.

Dependency rule: inner layers never import outer layers. `UI → Adapters → UseCases → Entities`.

## Feature Structure

```text
Domain/
  Entities/
    User.swift
  UseCases/
    LoadUserUseCase.swift
  Repositories/
    UserRepository.swift        (protocol)
Data/
  Repositories/
    LiveUserRepository.swift
  API/
  Mappers/
    UserMapper.swift
Presentation/
  Features/
    Profile/
      ProfileViewModel.swift
      ProfileView.swift
App/
  Assembly/
    UserFeatureAssembly.swift
```

## State Modeling

Domain entities are plain value types:

```swift
struct User: Equatable {
    let id: UUID
    let name: String
}

protocol LoadUserUseCase {
    func execute(id: UUID) async throws -> User
}

final class LoadUser: LoadUserUseCase {
    private let repository: UserRepository
    init(repository: UserRepository) { self.repository = repository }
    func execute(id: UUID) async throws -> User {
        try await repository.fetch(id: id)
    }
}
```

One business responsibility per use case. No UI details in domain.

## Dependency Injection

Repository protocols defined in Domain. Implementations in Data. Assembly wires at composition root:

```swift
protocol UserRepository {
    func fetch(id: UUID) async throws -> User
}

enum UserFeatureAssembly {
    static func makeLoadUserUseCase() -> LoadUserUseCase {
        LoadUser(repository: LiveUserRepository(api: .live))
    }
}
```

## Concurrency & Cancellation

Use structured concurrency in use cases. `async let` for parallel independent fetches:

```swift
func execute(id: UUID) async throws -> UserProfile {
    async let user = userRepo.fetch(id: id)
    async let posts = postsRepo.fetchRecent(userID: id)
    return try await UserProfile(user: user, posts: posts)
}
```

Cancellation propagates automatically through `try await` chains. Use `Task.checkCancellation()` before expensive work. Presentation cancels tasks on view disappearance.

## Navigation

Clean Architecture is presentation-agnostic. Navigation lives in the Presentation layer:
- SwiftUI: `@Observable` ViewModel + NavigationStack
- UIKit: Coordinator/Router in Presentation layer
- Use cases and Domain never reference navigation

## Anti-Patterns

1. **God Use Case** — 500+ line use case handling many responsibilities. *Fix*: split by business capability; compose use cases.
2. **Presentation Imports Data** — ViewModel uses `LiveRepository` directly. *Fix*: depend on use-case protocol only.
3. **Domain Depends on Frameworks** — entities import SwiftUI/UIKit/networking. *Fix*: keep domain pure Swift; move adapters outward.
4. **Repository Leaks DTOs** — presentation receives network models. *Fix*: map DTOs to domain entities at data boundary.
5. **Testing Through Real Infrastructure** — tests require network/DB. *Fix*: stub repositories conforming to domain protocols.

## Testing Strategy

Test at three boundaries: use-case logic (stub repos), DTO mapping (mapper tests), presentation (mocked use cases).

```swift
struct StubUserRepository: UserRepository {
    var result: Result<User, Error>
    func fetch(id: UUID) async throws -> User { try result.get() }
}

@MainActor
final class LoadUserTests: XCTestCase {
    func test_execute_returnsUser() async throws {
        let expected = User(id: UUID(), name: "Alice")
        let sut = LoadUser(repository: StubUserRepository(result: .success(expected)))
        let user = try await sut.execute(id: expected.id)
        XCTAssertEqual(user, expected)
    }

    func test_cancellationPropagates() async {
        let sut = LoadUser(repository: BlockingUserRepository())
        let task = Task { try await sut.execute(id: UUID()) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError { /* expected */ }
        catch { XCTFail("Unexpected: \(error)") }
    }
}
```

## PR Review Checklist

- [ ] Dependency direction points inward only
- [ ] Domain layer has zero framework imports
- [ ] Use cases encapsulate business rules — one per operation
- [ ] Presentation does not import Data implementations
- [ ] Repository protocols in Domain, implementations in Data
- [ ] DTOs mapped at data boundary — never leak to presentation
- [ ] `async let` for parallel fetches; cancellation propagates
- [ ] Tests isolate use cases from infrastructure
- [ ] Composition root wires all dependencies
