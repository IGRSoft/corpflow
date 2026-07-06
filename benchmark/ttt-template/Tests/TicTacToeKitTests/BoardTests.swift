import Testing
@testable import TicTacToeKit

/// Ports every scenario in `Tests/test_board.py` to Swift Testing.
@Suite("Board — move validation")
struct BoardMoveValidationTests {
    @Test("initial turn is X")
    func initialTurnIsX() {
        #expect(Board().turn == .x)
    }

    @Test("play advances turn")
    func playAdvancesTurn() throws {
        var b = Board()
        try b.play(0)
        #expect(b.turn == .o)
    }

    @Test("occupied cell rejected")
    func occupiedCellRejected() throws {
        var b = Board()
        try b.play(0)
        #expect(throws: InvalidMove.occupied(0)) {
            try b.play(0)
        }
    }

    @Test("out-of-range indices rejected", arguments: [-1, 9, 100])
    func outOfRangeRejected(bad: Int) {
        var b = Board()
        #expect(throws: InvalidMove.outOfRange(bad)) {
            try b.play(bad)
        }
    }

    @Test("is_valid_move false for out-of-range index")
    func isValidMoveFalseOutOfRange() {
        let b = Board()
        #expect(b.isValidMove(9) == false)
    }

    @Test("cell(9) and cell(-1) throw")
    func cellOutOfRangeThrows() {
        let b = Board()
        #expect(throws: InvalidMove.outOfRange(9)) {
            _ = try b.cell(9)
        }
        #expect(throws: InvalidMove.outOfRange(-1)) {
            _ = try b.cell(-1)
        }
    }

    @Test("cell reflects played move")
    func cellReflectsPlayedMove() throws {
        var b = Board()
        #expect(try b.cell(0) == nil)
        try b.play(0)
        #expect(try b.cell(0) == .x)
    }

    @Test("is_valid_move false when occupied")
    func isValidMoveFalseWhenOccupied() throws {
        var b = Board()
        try b.play(0)
        #expect(b.isValidMove(0) == false)
    }

    @Test("is_valid_move false when game over")
    func isValidMoveFalseWhenGameOver() throws {
        var b = Board()
        for m in [0, 3, 1, 4, 2] {
            try b.play(m)
        }
        #expect(b.state() == .xWins)
        #expect(b.isValidMove(5) == false)
    }

    @Test("empty_cells shrinks as moves are played")
    func emptyCellsShrink() throws {
        var b = Board()
        #expect(b.emptyCells().count == 9)
        try b.play(4)
        #expect(b.emptyCells().count == 8)
        #expect(!b.emptyCells().contains(4))
    }

    @Test("Player.other is symmetric")
    func playerOther() {
        #expect(Player.x.other == .o)
        #expect(Player.o.other == .x)
    }
}

@Suite("Board — win detection")
struct BoardWinTests {
    @Test("row win for X")
    func rowWinForX() throws {
        var b = Board()
        var state: GameState = .inProgress
        for m in [0, 3, 1, 4, 2] {
            state = try b.play(m)
        }
        #expect(state == .xWins)
        #expect(b.winner() == .x)
    }

    @Test("column win for X")
    func columnWinForX() throws {
        var b = Board()
        var state: GameState = .inProgress
        for m in [0, 1, 3, 2, 6] {
            state = try b.play(m)
        }
        #expect(state == .xWins)
        #expect(b.winner() == .x)
    }

    @Test("diagonal win for O")
    func diagonalWinForO() throws {
        var b = Board()
        var state: GameState = .inProgress
        for m in [1, 0, 2, 4, 5, 8] {
            state = try b.play(m)
        }
        #expect(state == .oWins)
        #expect(b.winner() == .o)
    }

    @Test("anti-diagonal win for O")
    func antiDiagonalWinForO() throws {
        var b = Board()
        var state: GameState = .inProgress
        for m in [0, 2, 1, 4, 3, 6] {
            state = try b.play(m)
        }
        #expect(state == .oWins)
        #expect(b.winner() == .o)
    }

    static let allWinLines: [(Int, Int, Int)] = [
        (0, 1, 2), (3, 4, 5), (6, 7, 8),
        (0, 3, 6), (1, 4, 7), (2, 5, 8),
        (0, 4, 8), (2, 4, 6),
    ]

    @Test("all 8 win lines produce X_WINS", arguments: BoardWinTests.allWinLines)
    func allEightWinLines(line: (Int, Int, Int)) throws {
        var b = Board()
        let lineIndices = [line.0, line.1, line.2]
        let others = (0..<9).filter { !lineIndices.contains($0) }
        for (x, o) in zip(lineIndices, others) {
            try b.play(x)
            if x != lineIndices.last {
                try b.play(o)
            }
        }
        #expect(b.winner() == .x)
        #expect(b.state() == .xWins)
    }

    @Test("no moves after win")
    func noMovesAfterWin() throws {
        var b = Board()
        for m in [0, 3, 1, 4, 2] {
            try b.play(m)
        }
        #expect(throws: InvalidMove.gameOver) {
            try b.play(5)
        }
    }

    @Test("winner nil mid-game")
    func winnerNilMidGame() throws {
        var b = Board()
        try b.play(0)
        #expect(b.winner() == nil)
        #expect(b.state() == .inProgress)
    }
}

@Suite("Board — draw detection")
struct BoardDrawTests {
    @Test("full board draw")
    func fullBoardDraw() throws {
        var b = Board()
        let moves = [0, 1, 2, 4, 3, 5, 7, 6, 8]
        var state = b.state()
        for m in moves {
            state = try b.play(m)
        }
        #expect(state == .draw)
        #expect(b.winner() == nil)
        #expect(b.isFull())
    }

    @Test("is_full false until last move")
    func isFullFalseUntilLastMove() throws {
        var b = Board()
        let moves = [0, 1, 2, 4, 3, 5, 7, 6, 8]
        for m in moves.dropLast() {
            try b.play(m)
            #expect(!b.isFull())
        }
        try b.play(moves.last!)
        #expect(b.isFull())
    }
}

@Suite("Board — rendering")
struct BoardRenderTests {
    @Test("render() exact ASCII for a known position")
    func renderExactASCII() throws {
        var b = Board()
        // X:0 O:1 X:4
        try b.play(0)
        try b.play(1)
        try b.play(4)
        let expected = [
            " X | O | 2 ",
            "---+---+---",
            " 3 | X | 5 ",
            "---+---+---",
            " 6 | 7 | 8 ",
        ].joined(separator: "\n")
        #expect(b.render() == expected)
    }

    @Test("render() on an empty board shows indices")
    func renderEmptyBoard() {
        let b = Board()
        let expected = [
            " 0 | 1 | 2 ",
            "---+---+---",
            " 3 | 4 | 5 ",
            "---+---+---",
            " 6 | 7 | 8 ",
        ].joined(separator: "\n")
        #expect(b.render() == expected)
    }
}
