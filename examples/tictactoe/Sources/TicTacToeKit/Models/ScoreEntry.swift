/// A single player's cumulative record in the `Leaderboard`.
public struct ScoreEntry: Codable, Sendable, Equatable {
    public var name: String
    public var wins: Int
    public var losses: Int
    public var draws: Int
    /// Current consecutive-win streak (resets to 0 on a loss or draw).
    public var currentStreak: Int

    public init(name: String, wins: Int = 0, losses: Int = 0, draws: Int = 0, currentStreak: Int = 0) {
        self.name = name
        self.wins = wins
        self.losses = losses
        self.draws = draws
        self.currentStreak = currentStreak
    }

    /// Total games recorded for this entry.
    public var gamesPlayed: Int { wins + losses + draws }
}
