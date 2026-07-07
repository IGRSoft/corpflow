import Observation

/// Drives a single Tic-Tac-Toe match: owns the `Board`, applies human moves,
/// triggers the AI opponent's reply, fires sound effects, and records the
/// final result to the `Leaderboard` exactly once per game.
@MainActor
@Observable
public final class GameViewModel {
    public private(set) var board: Board
    public var difficulty: AIDifficulty {
        didSet { ai.difficulty = difficulty }
    }
    public var playerXName: String
    public var playerOName: String

    /// The human player's mark. The AI always plays the other mark.
    public let humanPlayer: Player

    private let sound: SoundPlaying
    private let leaderboard: Leaderboard
    private var ai: AIOpponent
    private var hasRecordedResult = false

    public init(
        difficulty: AIDifficulty = .easy,
        humanPlayer: Player = .x,
        playerXName: String = "Player X",
        playerOName: String = "Player O",
        sound: SoundPlaying,
        leaderboard: Leaderboard,
        aiRNG: (any RandomNumberGenerator)? = nil
    ) {
        self.board = Board()
        self.difficulty = difficulty
        self.humanPlayer = humanPlayer
        self.playerXName = playerXName
        self.playerOName = playerOName
        self.sound = sound
        self.leaderboard = leaderboard
        if let aiRNG {
            self.ai = AIOpponent(difficulty: difficulty, rng: aiRNG)
        } else {
            self.ai = AIOpponent(difficulty: difficulty)
        }
    }

    /// The current game state.
    public var state: GameState { board.state() }

    /// Whether the game has reached a terminal state.
    public var isGameOver: Bool { state != .inProgress }

    /// Name for `player`, from the configured player names.
    public func name(for player: Player) -> String {
        player == .x ? playerXName : playerOName
    }

    /// Applies a human move at `index`, then — if the game continues and it's
    /// the AI's turn — applies the AI's reply. Fires sounds for each move and
    /// for a terminal win/draw, and records the leaderboard result exactly
    /// once when the game ends.
    public func playHuman(at index: Int) {
        guard board.isValidMove(index) else { return }
        guard board.turn == humanPlayer else { return }

        applyMove(index)
        maybeLetAIMove()
    }

    /// Starts a brand-new game, resetting the board and result-recording guard.
    public func newGame() {
        board = Board()
        hasRecordedResult = false
    }

    private func maybeLetAIMove() {
        guard !isGameOver else { return }
        guard board.turn != humanPlayer else { return }
        guard let index = ai.move(on: board) else { return }
        applyMove(index)
    }

    private func applyMove(_ index: Int) {
        guard let _ = try? board.play(index) else { return }
        sound.play(.move)
        handleTerminalStateIfNeeded()
    }

    private func handleTerminalStateIfNeeded() {
        switch state {
        case .xWins, .oWins:
            sound.play(.win)
            recordResultIfNeeded()
        case .draw:
            sound.play(.draw)
            recordResultIfNeeded()
        case .inProgress:
            break
        }
    }

    private func recordResultIfNeeded() {
        guard !hasRecordedResult else { return }
        hasRecordedResult = true

        switch state {
        case .xWins:
            leaderboard.record(name: playerXName, outcome: .win)
            leaderboard.record(name: playerOName, outcome: .loss)
        case .oWins:
            leaderboard.record(name: playerOName, outcome: .win)
            leaderboard.record(name: playerXName, outcome: .loss)
        case .draw:
            leaderboard.record(name: playerXName, outcome: .draw)
            leaderboard.record(name: playerOName, outcome: .draw)
        case .inProgress:
            break
        }
    }
}
