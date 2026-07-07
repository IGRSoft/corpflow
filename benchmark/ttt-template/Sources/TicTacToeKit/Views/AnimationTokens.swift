import SwiftUI

/// Shared animation constants used across the app's views, so tuning feel
/// stays consistent (and centralized) between the board, menu, and lists.
public enum AnimationTokens {
    /// Bouncy placement animation for a newly-played board cell mark.
    public static let cellPlacement: Animation = .spring(response: 0.35, dampingFraction: 0.65)

    /// Highlight pulse for the winning line.
    public static let winHighlight: Animation = .easeInOut(duration: 0.4).repeatCount(3, autoreverses: true)

    /// Screen-to-screen navigation transition.
    public static let screenTransition: Animation = .easeInOut(duration: 0.25)

    /// Leaderboard row insertion/removal.
    public static let rowInsertion: Animation = .spring(response: 0.4, dampingFraction: 0.8)
}
