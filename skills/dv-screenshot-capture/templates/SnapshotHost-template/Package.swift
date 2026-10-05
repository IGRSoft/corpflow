// swift-tools-version: 5.10
//
// SnapshotHost — SPM executable template for the `dv-screenshot-capture` apple-canvas adapter.
//
// Scaffolded into `tools/SnapshotHost/` per-project on first canvas render. The adapter:
//   1. Copies this file (and the surrounding sources) verbatim.
//   2. Optionally uncomments the `.iOS(.v16)` platform line when `metadata.canvas_destination=ios-sim`.
//   3. Appends `.target` dependencies for app modules whose Views are render targets.
//
// Constraints:
//   - platforms: .macOS(.v13) always; .iOS(.v16) conditional (uncommented by scaffolder)
//   - the swift-syntax dep lives in preview-ensurer's Package.swift, not here
//   - @testable import boundary: leaf View modules only (this file declares the target shape only)
//
// Once `tools/SnapshotHost/` is committed, it becomes a normal project artifact —
// CI-reproducible (`swift build` / `swift run`) without re-scaffolding.

import PackageDescription

let package = Package(
    name: "SnapshotHost",

    platforms: [
        .macOS(.v13),
        // .iOS(.v16),   // uncommented by scaffolder on `metadata.canvas_destination=ios-sim`
    ],

    products: [
        .executable(name: "SnapshotHost", targets: ["SnapshotHost"]),
    ],

    dependencies: [
        // Intentionally empty. SwiftSyntax is preview-ensurer's concern, not the host's.
        // Per-project Views are pulled in via `targets[].dependencies` appended by the
        // apple-canvas scaffolder (it uses `swift package show-dependencies --format json`
        // to derive the minimal `@testable import` set).
    ],

    targets: [
        .executableTarget(
            name: "SnapshotHost",
            dependencies: [
                // Appended by scaffolder per-project. Example shape:
                //   .product(name: "DesignSystem", package: "DesignSystem"),
                //   .product(name: "FeatureA",     package: "FeatureA"),
                // Modules that transitively import sim-only SDKs (e.g. ARKit on
                // host with no macOS variant) are REJECTED by the scaffolder with
                // exit code `module_graph_sim_required`; the adapter then falls
                // through to the simulator-based `apple` adapter.
            ],
            path: "Sources/SnapshotHost"
        ),
    ]
)
