// PreviewBridge.swift
//
// Bridge between SnapshotHost's CLI and the project's View modules.
// This file is the ONLY place `@testable import <ProjectModule>` lines are
// permitted (leaf View modules only).
//
// Not rewritten by the apple-canvas adapter: apple-canvas.sh copies this
// template once, when tools/SnapshotHost/Package.swift is absent, and leaves it
// alone afterwards. Until a project fills viewRegistry by hand (and makes
// main.swift's lookupRegistry() return it), every --view key misses and
// SnapshotHost exits 2.
//
// AR contract:
//   References analyzing-0.md § Source layout / § @testable import boundary rules.
//   The viewRegistry shape is: [String: AnyView] where keys are "ModuleName.TypeName".
//
// This template version (committed under skills/dv-screenshot-capture/templates/)
// ships an empty registry. A hand-filled project copy looks like:
//
//   import SwiftUI
//   @testable import DesignSystem
//   @testable import FeatureLogin
//
//   enum PreviewBridge {
//       static let viewRegistry: [String: AnyView] = [
//           "DesignSystem.PrimaryButton": AnyView(PrimaryButton(title: "")),
//           "FeatureLogin.LoginView":     AnyView(LoginView(viewModel: MockLoginViewModel())),
//       ]
//   }

import SwiftUI

/// Bridge between SnapshotHost's CLI and the project's View modules.
///
/// The template stub is empty and nothing populates it automatically — the
/// host fails fast with exit code 2 (`view-key not found`) until the
/// project's copy is filled by hand.
public enum PreviewBridge {

    /// Map of `"ModuleName.TypeName"` → type-erased View constructor invocation.
    ///
    /// One entry per render target, with mocked args derived per
    /// `skills/preview-ensurer/references/mock-data-strategy.md`.
    ///
    /// Mock construction lives in this table — at runtime, this dictionary
    /// is purely a string→AnyView lookup. ImageRenderer (in `main.swift`)
    /// consumes the AnyView and rasterizes it to PNG.
    // Template ships empty; fill the project copy by hand, keyed by
    // `"ModuleName.TypeName"`.
    public static let viewRegistry: [String: AnyView] = [:]
}
