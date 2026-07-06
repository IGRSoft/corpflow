import Foundation
import Testing
@testable import TicTacToeKit

@Suite("GameSettings")
struct GameSettingsTests {
    @Test("defaults are sound-on, easy difficulty, and default player names")
    func defaults() {
        let settings = GameSettings()
        #expect(settings.soundEnabled == true)
        #expect(settings.difficulty == .easy)
        #expect(settings.playerXName == "Player X")
        #expect(settings.playerOName == "Player O")
    }

    @Test("round-trips through disk at an injected store URL")
    func roundTripsPersistence() throws {
        let url = makeTempStoreURL(name: "settings.json")
        let store = GameSettingsStore(storeURL: url)

        var settings = GameSettings()
        settings.soundEnabled = false
        settings.difficulty = .hard
        settings.playerXName = "Nova"
        settings.playerOName = "Comet"
        try store.save(settings)

        let reloadedStore = GameSettingsStore(storeURL: url)
        let reloaded = reloadedStore.load()

        #expect(reloaded == settings)
    }

    @Test("load() returns defaults when the store file is absent")
    func loadReturnsDefaultsWhenAbsent() {
        let url = makeTempStoreURL(name: "missing-settings-\(UUID().uuidString).json")
        let store = GameSettingsStore(storeURL: url)
        let loaded = store.load()
        #expect(loaded == GameSettings())
    }
}
