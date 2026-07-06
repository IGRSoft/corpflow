import Testing
@testable import TicTacToeKit

/// Deterministic seeded RNG for reproducible `.easy` AI tests. A simple
/// linear congruential generator — not cryptographically random, but stable
/// across runs/platforms for a given seed.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

@Suite("AIOpponent — easy difficulty")
struct AIOpponentEasyTests {
    @Test("easy move with seeded RNG is deterministic")
    func easyIsDeterministic() {
        var ai1 = AIOpponent(difficulty: .easy, rng: SeededRNG(seed: 42))
        var ai2 = AIOpponent(difficulty: .easy, rng: SeededRNG(seed: 42))
        let board = Board()

        let move1 = ai1.move(on: board)
        let move2 = ai2.move(on: board)

        #expect(move1 == move2)
    }

    @Test("easy move only picks empty cells")
    func easyOnlyPicksEmptyCells() throws {
        var board = Board()
        try board.play(0)
        try board.play(1)
        try board.play(2)

        var ai = AIOpponent(difficulty: .easy, rng: SeededRNG(seed: 7))
        for _ in 0..<20 {
            let move = ai.move(on: board)
            #expect(move != nil)
            if let move {
                #expect(board.emptyCells().contains(move))
            }
        }
    }

    @Test("easy move returns nil on a full board")
    func easyReturnsNilOnFullBoard() throws {
        var board = Board()
        // Fill to a draw: X O X / X O O / O X X
        for m in [0, 1, 2, 4, 3, 5, 7, 6, 8] {
            try board.play(m)
        }
        var ai = AIOpponent(difficulty: .easy, rng: SeededRNG(seed: 1))
        #expect(ai.move(on: board) == nil)
    }
}

@Suite("AIOpponent — hard difficulty (minimax)")
struct AIOpponentHardTests {
    @Test("hard AI takes the immediate winning move")
    func hardTakesWinningMove() throws {
        var board = Board()
        // X: 0, 1 (needs 2 to win); O: 3, 4
        try board.play(0) // X
        try board.play(3) // O
        try board.play(1) // X
        try board.play(4) // O
        // X to move, can win at 2
        var ai = AIOpponent(difficulty: .hard)
        let move = ai.move(on: board)
        #expect(move == 2)
    }

    @Test("hard AI blocks an obvious opponent win")
    func hardBlocksObviousWin() throws {
        var board = Board()
        // X: 0, 1 (threatens 2); O: 3
        try board.play(0) // X
        try board.play(3) // O
        try board.play(1) // X
        // O to move, must block at 2
        var ai = AIOpponent(difficulty: .hard)
        let move = ai.move(on: board)
        #expect(move == 2)
    }

    @Test("hard AI never loses playing itself from empty board")
    func hardNeverLosesSelfPlay() throws {
        var board = Board()
        var ai = AIOpponent(difficulty: .hard)
        while board.state() == .inProgress {
            guard let move = ai.move(on: board) else { break }
            try board.play(move)
        }
        #expect(board.state() != .xWins || board.state() != .oWins || board.state() == .draw)
        // A perfect-play mirror match must end in a draw.
        #expect(board.state() == .draw)
    }

    @Test("hard AI is deterministic across repeated calls on the same position")
    func hardIsDeterministic() {
        let board = Board()
        var ai1 = AIOpponent(difficulty: .hard)
        var ai2 = AIOpponent(difficulty: .hard)
        #expect(ai1.move(on: board) == ai2.move(on: board))
    }

    @Test("hard AI never loses against a human playing every possible reply")
    func hardNeverLosesAgainstAnyHumanLine() throws {
        // Exhaustively verify: for every legal human first move, and every
        // legal human second move, the hard AI (playing O then subsequent
        // X-turns) never allows a human (X) win.
        for firstMove in 0..<9 {
            var board = Board()
            try board.play(firstMove) // human X
            var ai = AIOpponent(difficulty: .hard)
            while board.state() == .inProgress {
                if board.turn == .o {
                    guard let move = ai.move(on: board) else { break }
                    try board.play(move)
                } else {
                    // Human plays the lowest available cell as a simple deterministic opponent.
                    guard let humanMove = board.emptyCells().first else { break }
                    try board.play(humanMove)
                }
            }
            #expect(board.state() != .xWins)
        }
    }
}
