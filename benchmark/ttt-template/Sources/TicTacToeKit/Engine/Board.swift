/// A 3x3 Tic-Tac-Toe board. Cells are `nil` (empty) or a `Player`.
///
/// Ports `tictactoe/board.py` `Board` semantics exactly: move validation,
/// win/draw detection, and the fixed-width ASCII `render()` layout.
public struct Board: Sendable, Equatable {
    /// Number of cells on the board.
    public static let size = 9

    /// The 8 winning lines as index triples on the 0..8 flattened board.
    static let winLines: [(Int, Int, Int)] = [
        (0, 1, 2), (3, 4, 5), (6, 7, 8), // rows
        (0, 3, 6), (1, 4, 7), (2, 5, 8), // cols
        (0, 4, 8), (2, 4, 6), // diagonals
    ]

    private var cells: [Player?]
    private var currentTurn: Player

    public init() {
        cells = [Player?](repeating: nil, count: Board.size)
        currentTurn = .x
    }

    /// The player to move next.
    public var turn: Player { currentTurn }

    /// Validates `index` is an in-range cell index.
    private static func checkIndex(_ index: Int) throws(InvalidMove) {
        if index < 0 || index >= Board.size {
            throw InvalidMove.outOfRange(index)
        }
    }

    /// The contents of `index`, or `nil` if empty.
    /// - Throws: `InvalidMove.outOfRange` if `index` is not `0..<9`.
    public func cell(_ index: Int) throws(InvalidMove) -> Player? {
        try Board.checkIndex(index)
        return cells[index]
    }

    /// Indices of all empty cells, in ascending order.
    public func emptyCells() -> [Int] {
        cells.indices.filter { cells[$0] == nil }
    }

    /// Whether every cell is occupied.
    public func isFull() -> Bool {
        cells.allSatisfy { $0 != nil }
    }

    /// Whether playing at `index` right now would be legal (in-range, empty cell,
    /// game still in progress). Never throws — invalid indices simply return `false`.
    public func isValidMove(_ index: Int) -> Bool {
        guard index >= 0, index < Board.size else { return false }
        return cells[index] == nil && state() == .inProgress
    }

    /// Applies the current player's move at `index`, advances the turn if the
    /// game continues, and returns the resulting state.
    /// - Throws: `InvalidMove.outOfRange` for an out-of-range index,
    ///   `InvalidMove.gameOver` if the game already ended, or
    ///   `InvalidMove.occupied` if the cell is already taken.
    @discardableResult
    public mutating func play(_ index: Int) throws(InvalidMove) -> GameState {
        try Board.checkIndex(index)
        if state() != .inProgress {
            throw InvalidMove.gameOver
        }
        if cells[index] != nil {
            throw InvalidMove.occupied(index)
        }
        cells[index] = currentTurn
        let resulting = state()
        if resulting == .inProgress {
            currentTurn = currentTurn.other
        }
        return resulting
    }

    /// The winning player, or `nil` if there is no winner yet.
    public func winner() -> Player? {
        for (a, b, c) in Board.winLines {
            if let v = cells[a], cells[b] == v, cells[c] == v {
                return v
            }
        }
        return nil
    }

    /// The current terminal/non-terminal state of the board.
    public func state() -> GameState {
        switch winner() {
        case .x: return .xWins
        case .o: return .oWins
        case nil:
            return isFull() ? .draw : .inProgress
        }
    }

    /// Renders the board as fixed-width ASCII, matching the Python
    /// `Board.render()` output byte-for-byte.
    public func render() -> String {
        func sym(_ i: Int) -> String {
            cells[i]?.rawValue ?? String(i)
        }
        let rows = [
            " \(sym(0)) | \(sym(1)) | \(sym(2)) ",
            "---+---+---",
            " \(sym(3)) | \(sym(4)) | \(sym(5)) ",
            "---+---+---",
            " \(sym(6)) | \(sym(7)) | \(sym(8)) ",
        ]
        return rows.joined(separator: "\n")
    }
}
