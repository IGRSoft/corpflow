import Foundation

/// User-configurable game settings, persisted as JSON at an injectable URL
/// so tests can round-trip through a temp directory instead of a shared
/// on-disk default location.
public struct GameSettings: Codable, Sendable, Equatable {
    public var soundEnabled: Bool
    public var difficulty: AIDifficulty
    public var playerXName: String
    public var playerOName: String

    public init(
        soundEnabled: Bool = true,
        difficulty: AIDifficulty = .easy,
        playerXName: String = "Player X",
        playerOName: String = "Player O"
    ) {
        self.soundEnabled = soundEnabled
        self.difficulty = difficulty
        self.playerXName = playerXName
        self.playerOName = playerOName
    }
}

/// Loads/saves `GameSettings` as JSON at an injectable store URL.
public struct GameSettingsStore: Sendable {
    public let storeURL: URL

    public init(storeURL: URL) {
        self.storeURL = storeURL
    }

    /// Loads settings from disk, or returns `GameSettings()` defaults if the
    /// file is absent or unreadable. Never throws.
    public func load() -> GameSettings {
        guard let data = try? Data(contentsOf: storeURL) else {
            return GameSettings()
        }
        guard let settings = try? JSONDecoder().decode(GameSettings.self, from: data) else {
            return GameSettings()
        }
        return settings
    }

    /// Persists `settings` as JSON at `storeURL`, creating intermediate
    /// directories as needed.
    public func save(_ settings: GameSettings) throws {
        let data = try JSONEncoder().encode(settings)
        try FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: storeURL, options: .atomic)
    }
}
