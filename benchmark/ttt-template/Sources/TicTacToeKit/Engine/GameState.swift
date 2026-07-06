/// Terminal/non-terminal state of a `Board`. Raw values match the Python
/// `GameState(str, Enum)` values exactly so CLI output (`result: <value>`)
/// is byte-for-byte identical to the reference implementation.
public enum GameState: String, Codable, Sendable {
    case inProgress = "in_progress"
    case xWins = "X_wins"
    case oWins = "O_wins"
    case draw = "draw"
}
