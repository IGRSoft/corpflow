/// Difficulty level for the built-in AI opponent.
public enum AIDifficulty: String, Codable, Sendable, CaseIterable {
    case easy
    case hard
}

/// A simple Tic-Tac-Toe AI opponent supporting an `.easy` (random) and
/// `.hard` (perfect minimax) difficulty.
///
/// Not `Sendable`: it holds an existential `RandomNumberGenerator`, which is
/// itself not `Sendable`. Callers needing to cross concurrency domains
/// should construct a fresh `AIOpponent` on the destination actor/task.
public struct AIOpponent {
    public var difficulty: AIDifficulty
    private var rng: any RandomNumberGenerator

    /// - Parameters:
    ///   - difficulty: `.easy` picks a uniformly random empty cell; `.hard` never loses.
    ///   - rng: Injectable random source so `.easy` behavior is deterministic in tests.
    public init(difficulty: AIDifficulty, rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.difficulty = difficulty
        self.rng = rng
    }

    /// Returns the index the AI would play on `board`, or `nil` if the board
    /// has no empty cells (game already over / full).
    public mutating func move(on board: Board) -> Int? {
        let empties = board.emptyCells()
        guard !empties.isEmpty else { return nil }
        switch difficulty {
        case .easy:
            let offset = Int.random(in: 0..<empties.count, using: &rng)
            return empties[offset]
        case .hard:
            return Self.bestMove(on: board)
        }
    }

    // MARK: - Minimax (hard difficulty — deterministic, plays optimally, never loses)

    /// Computes the optimal move for the player currently `board.turn`.
    /// Deterministic: ties are always broken by lowest index.
    static func bestMove(on board: Board) -> Int? {
        let empties = board.emptyCells()
        guard !empties.isEmpty else { return nil }
        let mover = board.turn

        var bestScore = Int.min
        var bestIndex: Int?
        for index in empties {
            var trial = board
            // Safe: index comes from emptyCells() on the same board, so it is
            // always a valid, unoccupied cell — this call cannot throw.
            guard let _ = try? trial.play(index) else { continue }
            let score = minimax(board: trial, mover: mover, depth: 1, isMaximizing: false)
            if score > bestScore {
                bestScore = score
                bestIndex = index
            }
        }
        return bestIndex
    }

    /// Standard minimax scoring: +1 win for `mover`, -1 loss, 0 draw, discounted
    /// by depth so faster wins / slower losses are preferred (keeps play deterministic
    /// and "human-reasonable" without affecting perfection).
    private static func minimax(board: Board, mover: Player, depth: Int, isMaximizing: Bool) -> Int {
        let state = board.state()
        switch state {
        case .xWins:
            return mover == .x ? (10 - depth) : (depth - 10)
        case .oWins:
            return mover == .o ? (10 - depth) : (depth - 10)
        case .draw:
            return 0
        case .inProgress:
            break
        }

        let empties = board.emptyCells()
        if isMaximizing {
            var best = Int.min
            for index in empties {
                var trial = board
                guard let _ = try? trial.play(index) else { continue }
                let score = minimax(board: trial, mover: mover, depth: depth + 1, isMaximizing: false)
                best = max(best, score)
            }
            return best
        } else {
            var best = Int.max
            for index in empties {
                var trial = board
                guard let _ = try? trial.play(index) else { continue }
                let score = minimax(board: trial, mover: mover, depth: depth + 1, isMaximizing: true)
                best = min(best, score)
            }
            return best
        }
    }
}
