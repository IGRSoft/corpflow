import SwiftUI

/// Landing screen: navigate to a new game, the leaderboard, or settings.
public struct MainMenuView: View {
    var router: AppRouter

    public init(router: AppRouter) {
        self.router = router
    }

    public var body: some View {
        VStack(spacing: 24) {
            Text("Tic-Tac-Toe")
                .font(.largeTitle.bold())

            VStack(spacing: 12) {
                Button("Play") { router.navigate(to: .game) }
                    .buttonStyle(.borderedProminent)

                Button("Leaderboard") { router.navigate(to: .leaderboard) }
                    .buttonStyle(.bordered)

                Button("Settings") { router.navigate(to: .settings) }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .transition(.moveAndFade)
    }
}

#Preview {
    MainMenuView(router: AppRouter())
}
