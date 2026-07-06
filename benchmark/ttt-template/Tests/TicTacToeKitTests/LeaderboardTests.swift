import Foundation
import Testing
@testable import TicTacToeKit

/// Creates a fresh temp-directory URL for a JSON store, so tests never touch
/// a shared on-disk location.
func makeTempStoreURL(name: String = "leaderboard.json") -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("TicTacToeKitTests-\(UUID().uuidString)", isDirectory: true)
    return dir.appendingPathComponent(name)
}

@Suite("Leaderboard")
struct LeaderboardTests {
    @Test("round-trips through disk at an injected store URL")
    func roundTripsPersistence() throws {
        let url = makeTempStoreURL()
        let board = Leaderboard(storeURL: url)
        board.record(name: "Alice", outcome: .win)
        board.record(name: "Bob", outcome: .loss)

        let reloaded = Leaderboard(storeURL: url)
        #expect(reloaded.entry(for: "Alice")?.wins == 1)
        #expect(reloaded.entry(for: "Bob")?.losses == 1)
    }

    @Test("never crashes when the store file is absent")
    func neverCrashesWhenFileAbsent() {
        let url = makeTempStoreURL(name: "does-not-exist-\(UUID().uuidString).json")
        let board = Leaderboard(storeURL: url)
        #expect(board.standings.isEmpty)
    }

    @Test("standings sorted by wins desc then name asc")
    func standingsSortedCorrectly() {
        let url = makeTempStoreURL()
        let board = Leaderboard(storeURL: url)
        board.record(name: "Zed", outcome: .win)
        board.record(name: "Amy", outcome: .win)
        board.record(name: "Bo", outcome: .win)
        board.record(name: "Bo", outcome: .win) // Bo now has 2 wins

        let names = board.standings.map(\.name)
        #expect(names == ["Bo", "Amy", "Zed"])
    }

    @Test("tracks per-player current streak, resetting on loss or draw")
    func tracksCurrentStreak() {
        let url = makeTempStoreURL()
        let board = Leaderboard(storeURL: url)
        board.record(name: "Casey", outcome: .win)
        board.record(name: "Casey", outcome: .win)
        #expect(board.entry(for: "Casey")?.currentStreak == 2)

        board.record(name: "Casey", outcome: .loss)
        #expect(board.entry(for: "Casey")?.currentStreak == 0)

        board.record(name: "Casey", outcome: .win)
        board.record(name: "Casey", outcome: .draw)
        #expect(board.entry(for: "Casey")?.currentStreak == 0)
    }

    @Test("gamesPlayed sums wins, losses, and draws")
    func gamesPlayedSums() {
        let url = makeTempStoreURL()
        let board = Leaderboard(storeURL: url)
        board.record(name: "Dana", outcome: .win)
        board.record(name: "Dana", outcome: .loss)
        board.record(name: "Dana", outcome: .draw)
        #expect(board.entry(for: "Dana")?.gamesPlayed == 3)
    }
}
