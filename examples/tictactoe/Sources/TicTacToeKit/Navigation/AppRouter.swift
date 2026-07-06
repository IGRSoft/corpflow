import Observation

/// Drives top-level screen navigation. Tracks the most recent transition so
/// tests (and transition-driven UI, e.g. animations) can assert on it.
@MainActor
@Observable
public final class AppRouter {
    public private(set) var screen: AppScreen
    public private(set) var lastTransition: (from: AppScreen, to: AppScreen)?

    public init(start: AppScreen = .main) {
        self.screen = start
        self.lastTransition = nil
    }

    /// Navigates to `screen`, recording the transition from the current screen.
    public func navigate(to screen: AppScreen) {
        lastTransition = (from: self.screen, to: screen)
        self.screen = screen
    }
}
