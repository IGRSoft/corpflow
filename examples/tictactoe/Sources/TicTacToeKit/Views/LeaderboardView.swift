import SwiftUI

/// Displays player standings sorted by wins (desc) then name (asc), with
/// animated row insertion as the leaderboard changes.
public struct LeaderboardView: View {
    var leaderboard: Leaderboard

    public init(leaderboard: Leaderboard) {
        self.leaderboard = leaderboard
    }

    public var body: some View {
        List {
            ForEach(leaderboard.standings, id: \.name) { entry in
                HStack {
                    VStack(alignment: .leading) {
                        Text(entry.name).font(.headline)
                        Text("Streak: \(entry.currentStreak)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(entry.wins)W \(entry.losses)L \(entry.draws)D")
                        .font(.subheadline.monospacedDigit())
                }
                .transition(.moveAndFade)
            }
        }
        .animation(AnimationTokens.rowInsertion, value: leaderboard.standings)
        .navigationTitle("Leaderboard")
    }
}

extension ScoreEntry: Hashable {
    public static func == (lhs: ScoreEntry, rhs: ScoreEntry) -> Bool {
        lhs.name == rhs.name && lhs.wins == rhs.wins && lhs.losses == rhs.losses
            && lhs.draws == rhs.draws && lhs.currentStreak == rhs.currentStreak
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(wins)
        hasher.combine(losses)
        hasher.combine(draws)
        hasher.combine(currentStreak)
    }
}

#Preview {
    LeaderboardView(leaderboard: Leaderboard(storeURL: URL(fileURLWithPath: "/tmp/ttt-preview-leaderboard.json")))
}
