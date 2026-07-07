// swift-tools-version:6.2
import PackageDescription

// BenchmarkHarness — Swift port of the Python A/B token benchmark harness.
//
// Package boundary (AC-8, link-level): the deterministic world (BenchmarkKit +
// bench-deterministic + bench-report) NEVER links the live world (BenchmarkLive
// + bench-live). This is compile-enforced by the target dependency graph below
// and asserted at test time by BenchmarkKitTests/PackageGraphTests (which parses
// this manifest via `swift package dump-package`).
let package = Package(
    name: "BenchmarkHarness",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "BenchmarkKit", targets: ["BenchmarkKit"]),
        .library(name: "BenchmarkLive", targets: ["BenchmarkLive"]),
        .executable(name: "bench-deterministic", targets: ["bench-deterministic"]),
        .executable(name: "bench-live", targets: ["bench-live"]),
        .executable(name: "bench-report", targets: ["bench-report"]),
    ],
    targets: [
        // Deterministic world — AC-8 clean. Zero dependency on BenchmarkLive.
        .target(name: "BenchmarkKit"),
        // Live world — depends on BenchmarkKit for the shared metrics schema.
        .target(name: "BenchmarkLive", dependencies: ["BenchmarkKit"]),

        // Executables. bench-deterministic + bench-report link ONLY BenchmarkKit.
        .executableTarget(name: "bench-deterministic", dependencies: ["BenchmarkKit"]),
        .executableTarget(name: "bench-report", dependencies: ["BenchmarkKit"]),
        // bench-live is the only executable that links the live world.
        .executableTarget(name: "bench-live", dependencies: ["BenchmarkLive"]),

        // Tests.
        .testTarget(
            name: "BenchmarkKitTests",
            dependencies: ["BenchmarkKit"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "BenchmarkLiveTests",
            dependencies: ["BenchmarkLive"]
        ),
    ]
)
