import SwiftUI

/// The 3x3 game board screen: tap a cell to play, watch the AI respond, and
/// see the winning line highlighted when the game ends.
public struct GameView: View {
    @Bindable var viewModel: GameViewModel
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    public init(viewModel: GameViewModel) {
        self.viewModel = viewModel
    }

    private var winningLine: Set<Int> {
        Set(viewModel.board.winningLine() ?? [])
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text(statusText)
                .font(.title2.bold())
                .transition(.moveAndFade)
                .animation(AnimationTokens.screenTransition, value: viewModel.state)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(0..<Board.size, id: \.self) { index in
                    BoardCellView(
                        mark: try? viewModel.board.cell(index),
                        isWinningCell: winningLine.contains(index)
                    ) {
                        viewModel.playHuman(at: index)
                    }
                }
            }
            .padding()

            Button("New Game") {
                withAnimation(AnimationTokens.screenTransition) {
                    viewModel.newGame()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var statusText: String {
        switch viewModel.state {
        case .inProgress:
            return "\(viewModel.name(for: viewModel.board.turn))'s turn"
        case .xWins:
            return "\(viewModel.name(for: .x)) wins!"
        case .oWins:
            return "\(viewModel.name(for: .o)) wins!"
        case .draw:
            return "It's a draw!"
        }
    }
}

#Preview {
    GameView(
        viewModel: GameViewModel(
            sound: SilentSoundPlayer(),
            leaderboard: Leaderboard(storeURL: URL(fileURLWithPath: "/tmp/ttt-preview-leaderboard.json"))
        )
    )
}
