// swift-tools-version: 5.10
//
// preview-ensurer — SPM package for the `PreviewEnsurer` executable.
//
// Build:  swift build --package-path skills/preview-ensurer/references/reference-impl
// Run:    swift run --package-path skills/preview-ensurer/references/reference-impl PreviewEnsurer \
//           --modified-files <newline-list> [--auto-add true|false]
//
// swift-syntax pinned `.upToNextMajor(from: "510.0.0")`.
// Covers Swift 5.10 (Xcode 15.4) and Swift 6.0+ (Xcode 16.x).

import PackageDescription

let package = Package(
    name: "PreviewEnsurer",

    platforms: [
        .macOS(.v13),
    ],

    products: [
        .executable(name: "PreviewEnsurer", targets: ["PreviewEnsurer"]),
    ],

    dependencies: [
        .package(
            url: "https://github.com/swiftlang/swift-syntax.git",
            .upToNextMajor(from: "510.0.0")
        ),
    ],

    targets: [
        .executableTarget(
            name: "PreviewEnsurer",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
            // Standard SPM layout: Sources/PreviewEnsurer/*.swift
        ),
    ]
)
