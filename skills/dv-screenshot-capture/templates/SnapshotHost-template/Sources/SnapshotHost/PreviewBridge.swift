// PreviewBridge.swift
//
// Bridge between SnapshotHost's CLI and the project's View modules.
// This file is the ONLY place `@testable import <ProjectModule>` lines are
// permitted (ad3 — `@testable import` boundary rule).
//
// REWRITTEN IDEMPOTENTLY by the apple-canvas adapter before each render:
//   - Same project state → byte-identical file content (no spurious diff churn).
//   - The adapter walks `swift package show-dependencies --format json`,
//     filters to leaf View modules (no sim-only SDK transitives), and emits
//     this file with one `@testable import` line per module + one viewRegistry
//     entry per render target.
//
// HUMAN EDITS DISCOURAGED — they will be overwritten. To register a custom
// view manually, add it to the canonical project View module (so it appears
// in the next `show-dependencies` walk), or add a per-project override in
// `tools/SnapshotHost/Sources/SnapshotHost/PreviewBridge+Overrides.swift`
// (not auto-rewritten).
//
// AR contract:
//   References analyzing-0.md § Source layout / § @testable import boundary rules.
//   The viewRegistry shape is: [String: AnyView] where keys are "ModuleName.TypeName".
//
// This template version (committed under skills/dv-screenshot-capture/templates/)
// ships an empty registry. Real projects will see this file populated by the
// scaffolder on first run, e.g.:
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
/// The dictionary is rewritten per-project by the apple-canvas scaffolder.
/// This template stub renders empty — the host fails fast with exit code 2
/// (`view-key not found`) until the scaffolder populates it.
public enum PreviewBridge {

    /// Map of `"ModuleName.TypeName"` → type-erased View constructor invocation.
    ///
    /// The apple-canvas adapter populates this dictionary by:
    ///   1. Reading the `--view` argument (e.g., `FeatureLogin.LoginView`).
    ///   2. Cross-referencing it with `preview-ensurer`'s output for that file.
    ///   3. Emitting one entry per render target, with mocked-args derived per
    ///      `skills/preview-ensurer/references/mock-data-strategy.md`.
    ///
    /// Mock construction lives at scaffold time — at runtime, this dictionary
    /// is purely a string→AnyView lookup. ImageRenderer (in `main.swift`)
    /// consumes the AnyView and rasterizes it to PNG.
    // Template ships empty. Real projects: see file header docs — the
    // scaffolder replaces this literal with a populated `[String: AnyView]`
    // table keyed by `"ModuleName.TypeName"`.
    public static let viewRegistry: [String: AnyView] = [:]
}
