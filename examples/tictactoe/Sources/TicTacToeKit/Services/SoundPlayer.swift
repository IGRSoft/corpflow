/// Sound effects fired by gameplay events.
public enum SoundEffect: Sendable {
    case move
    case win
    case draw
    case tap
}

/// Abstraction over platform sound playback so view models can be tested
/// with a silent/spy implementation instead of touching real audio APIs.
public protocol SoundPlaying: Sendable {
    func play(_ effect: SoundEffect)
}

/// No-op `SoundPlaying` implementation for tests and headless execution.
public struct SilentSoundPlayer: SoundPlaying {
    public init() {}
    public func play(_ effect: SoundEffect) {
        // Intentionally does nothing.
    }
}

#if canImport(AppKit)
import AppKit

/// NSSound-backed sound player for macOS. Falls back to a silent no-op if the
/// named system sound is unavailable (e.g. headless CI) — never crashes.
public struct AppKitSoundPlayer: SoundPlaying {
    public init() {}

    public func play(_ effect: SoundEffect) {
        guard let sound = NSSound(named: soundName(for: effect)) else {
            return
        }
        sound.play()
    }

    private func soundName(for effect: SoundEffect) -> NSSound.Name {
        switch effect {
        case .move: return NSSound.Name("Tink")
        case .win: return NSSound.Name("Glass")
        case .draw: return NSSound.Name("Pop")
        case .tap: return NSSound.Name("Tock")
        }
    }
}
#endif

#if canImport(UIKit)
import AudioToolbox

/// AudioToolbox-backed sound player for iOS/tvOS/watchOS, using system sound
/// IDs. Never crashes if playback is unavailable (e.g. headless simulators).
public struct UIKitSoundPlayer: SoundPlaying {
    public init() {}

    public func play(_ effect: SoundEffect) {
        AudioServicesPlaySystemSound(systemSoundID(for: effect))
    }

    private func systemSoundID(for effect: SoundEffect) -> SystemSoundID {
        switch effect {
        case .move: return 1104
        case .win: return 1025
        case .draw: return 1053
        case .tap: return 1103
        }
    }
}
#endif

/// Returns the best-available platform sound player, falling back to
/// `SilentSoundPlayer` on platforms without AppKit or UIKit.
public func makePlatformSoundPlayer() -> SoundPlaying {
    #if canImport(AppKit)
    return AppKitSoundPlayer()
    #elseif canImport(UIKit)
    return UIKitSoundPlayer()
    #else
    return SilentSoundPlayer()
    #endif
}
