// swift-tools-version:6.2
import PackageDescription

// PluginScriptsTests — Swift Testing suites that shell out to the UNCHANGED
// plugin skill scripts (skills/estimation-methodology/scripts/estimate-calc.py,
// skills/appstore-screenshots/scripts/layout-calc.py) via python3 and assert
// the same 38 behaviors the retired tests/python suites asserted. The scripts
// stay Python (skill runtime contract); only the test harness is Swift.
let package = Package(
    name: "PluginScriptsTests",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "PluginScripts"),
        .testTarget(name: "PluginScriptsTests", dependencies: ["PluginScripts"]),
    ]
)
