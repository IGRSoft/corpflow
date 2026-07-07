/// A Tic-Tac-Toe player marker. Raw value matches the Python `Player(str, Enum)`
/// values exactly ("X" / "O") so any serialized state is interoperable.
public enum Player: String, Codable, Sendable, CaseIterable {
    case x = "X"
    case o = "O"

    /// The opposing player.
    public var other: Player {
        self == .x ? .o : .x
    }
}
