import SwiftUI

/// Sound toggle, AI difficulty picker, and player name fields.
public struct SettingsView: View {
    @Binding var settings: GameSettings

    public init(settings: Binding<GameSettings>) {
        self._settings = settings
    }

    public var body: some View {
        Form {
            Section("Audio") {
                Toggle("Sound Effects", isOn: $settings.soundEnabled)
            }

            Section("Difficulty") {
                Picker("AI Difficulty", selection: $settings.difficulty) {
                    Text("Easy").tag(AIDifficulty.easy)
                    Text("Hard").tag(AIDifficulty.hard)
                }
                .pickerStyle(.segmented)
            }

            Section("Players") {
                TextField("Player X Name", text: $settings.playerXName)
                TextField("Player O Name", text: $settings.playerOName)
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    @Previewable @State var settings = GameSettings()
    SettingsView(settings: $settings)
}
