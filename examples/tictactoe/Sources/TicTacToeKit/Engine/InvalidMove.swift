/// Thrown by `Board` when a move is illegal. Mirrors the Python `InvalidMove(ValueError)`
/// cases (out-of-range index, occupied cell, finished game) as distinct, testable cases.
public enum InvalidMove: Error, Equatable, Sendable {
    /// The index was not in the range `0..<Board.size`.
    case outOfRange(Int)
    /// The target cell was already occupied.
    case occupied(Int)
    /// The game already reached a terminal state.
    case gameOver

    /// A human-readable message closely mirroring the Python `ValueError` text.
    public var message: String {
        switch self {
        case .outOfRange(let index):
            return "cell index out of range: \(index) (expected 0..8)"
        case .occupied(let index):
            return "cell \(index) is already occupied"
        case .gameOver:
            return "game is already over"
        }
    }
}

extension InvalidMove: CustomStringConvertible {
    public var description: String { message }
}
