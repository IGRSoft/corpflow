import Testing
@testable import TicTacToeKit

@Suite("AppRouter")
@MainActor
struct AppRouterTests {
    @Test("starts on the main screen with no prior transition")
    func startsOnMain() {
        let router = AppRouter()
        #expect(router.screen == .main)
        #expect(router.lastTransition == nil)
    }

    @Test("navigate updates the current screen")
    func navigateUpdatesScreen() {
        let router = AppRouter()
        router.navigate(to: .game)
        #expect(router.screen == .game)
    }

    @Test("navigate records the from/to transition")
    func navigateRecordsTransition() {
        let router = AppRouter()
        router.navigate(to: .leaderboard)
        #expect(router.lastTransition?.from == .main)
        #expect(router.lastTransition?.to == .leaderboard)

        router.navigate(to: .settings)
        #expect(router.lastTransition?.from == .leaderboard)
        #expect(router.lastTransition?.to == .settings)
    }

    @Test("custom start screen is honored")
    func customStartScreen() {
        let router = AppRouter(start: .settings)
        #expect(router.screen == .settings)
    }
}
