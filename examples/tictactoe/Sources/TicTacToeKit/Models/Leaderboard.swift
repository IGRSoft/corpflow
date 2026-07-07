import Foundation

/// The outcome of a completed game, from a single named player's perspective.
public enum GameOutcome: Sendable {
    case win
    case loss
    case draw
}

/// Persists player standings (`ScoreEntry`) as JSON at an injectable store
/// URL. Never crashes if the backing file is absent — `load()` starts from
/// an empty leaderboard in that case.
@Observable
public final class Leaderboard: @unchecked Sendable {
    private let storeURL: URL
    private var entriesByName: [String: ScoreEntry]

    public init(storeURL: URL) {
        self.storeURL = storeURL
        self.entriesByName = [:]
        load()
    }

    /// Standings sorted by wins descending, then name ascending.
    public var standings: [ScoreEntry] {
        entriesByName.values.sorted { lhs, rhs in
            if lhs.wins != rhs.wins { return lhs.wins > rhs.wins }
            return lhs.name < rhs.name
        }
    }

    /// Records a single game result for `name`, updating wins/losses/draws
    /// and the current win streak, then persists to disk.
    public func record(name: String, outcome: GameOutcome) {
        var entry = entriesByName[name] ?? ScoreEntry(name: name)
        switch outcome {
        case .win:
            entry.wins += 1
            entry.currentStreak += 1
        case .loss:
            entry.losses += 1
            entry.currentStreak = 0
        case .draw:
            entry.draws += 1
            entry.currentStreak = 0
        }
        entriesByName[name] = entry
        try? save()
    }

    /// The persisted entry for `name`, if any.
    public func entry(for name: String) -> ScoreEntry? {
        entriesByName[name]
    }

    /// Loads entries from `storeURL`. Leaves the leaderboard empty if the
    /// file is absent, empty, or unreadable — never throws or crashes.
    public func load() {
        guard let data = try? Data(contentsOf: storeURL), !data.isEmpty else {
            entriesByName = [:]
            return
        }
        guard let entries = try? JSONDecoder().decode([ScoreEntry].self, from: data) else {
            entriesByName = [:]
            return
        }
        entriesByName = Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0) })
    }

    /// Persists all entries as JSON at `storeURL`, creating intermediate
    /// directories as needed.
    public func save() throws {
        let entries = Array(entriesByName.values)
        let data = try JSONEncoder().encode(entries)
        try FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: storeURL, options: .atomic)
    }
}
