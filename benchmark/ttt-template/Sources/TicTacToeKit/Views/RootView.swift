import SwiftUI

/// Top-level view that switches between screens based on `AppRouter.screen`,
/// animating transitions between them.
public struct RootView: View {
    @State private var router = AppRouter()
    @State private var leaderboard: Leaderboard
    @State private var settings = GameSettings()
    private let sound: SoundPlaying

    public init(
        storeDirectory: URL = FileManager.default.temporaryDirectory,
        sound: SoundPlaying = SilentSoundPlayer()
    ) {
        _leaderboard = State(
            initialValue: Leaderboard(storeURL: storeDirectory.appendingPathComponent("leaderboard.json"))
        )
        self.sound = sound
    }

    public var body: some View {
        Group {
            switch router.screen {
            case .main:
                MainMenuView(router: router)
            case .game:
                GameView(
                    viewModel: GameViewModel(
                        difficulty: settings.difficulty,
                        playerXName: settings.playerXName,
                        playerOName: settings.playerOName,
                        sound: sound,
                        leaderboard: leaderboard
                    )
                )
            case .leaderboard:
                LeaderboardView(leaderboard: leaderboard)
            case .settings:
                SettingsView(settings: $settings)
            }
        }
        .animation(AnimationTokens.screenTransition, value: router.screen)
        .transition(.moveAndFade)
    }
}

#Preview {
    RootView()
}
