import SwiftUI

extension AnyTransition {
    /// Combines a slight upward move with a fade, used for screen and row
    /// transitions throughout the app.
    public static var moveAndFade: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
        )
    }

    /// A scale + fade transition, used for newly-placed board marks.
    public static var scaleAndFade: AnyTransition {
        .scale(scale: 0.6).combined(with: .opacity)
    }
}
