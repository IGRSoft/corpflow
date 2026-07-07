// LayoutCalcTests.swift — port of tests/python/test_layout_calc.py
// (17 behaviors) against the UNCHANGED skills/appstore-screenshots/scripts/
// layout-calc.py, driven via `python3` subprocess. Geometry constants mirror
// the script: _PHONE_ASPECT = 19.5/9, _MAC_ASPECT = 16/10.

import Foundation
import PluginScripts
import Testing

private let repoRoot: String = {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // PluginScriptsTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // swift
        .deletingLastPathComponent()   // tests
        .deletingLastPathComponent()   // repo root
        .path
}()

private let script = repoRoot + "/skills/appstore-screenshots/scripts/layout-calc.py"

private let phoneAspect = 19.5 / 9.0
private let macAspect = 16.0 / 10.0

/// Python round() is banker's rounding; all values these tests touch are
/// non-.5 cases except where the Python self-test itself pins them, so
/// .toNearestOrEven matches Python exactly.
private func pyRound(_ v: Double) -> Int { Int(v.rounded(.toNearestOrEven)) }

private func run(_ args: String...) -> ScriptResult {
    ScriptRunner.run(script: script, args)
}

@Suite("compute_layout geometry (iPhone 6.9 Layout A)")
struct ComputeLayoutGeometry {
    @Test func layoutAHeadlineAndSubtitle() throws {
        let r = run("iphone-6.9-1320x2868", "--layout", "A")
        #expect(r.exitCode == 0, "stderr: \(r.stderr)")
        let data = try #require(r.json)
        let headline = try #require(data.dict("headline"))
        #expect(headline.int("x") == pyRound(1320 * 0.06))
        #expect(headline.int("y") == pyRound(2868 * 0.04))
        #expect(headline.int("w") == pyRound(1320 * 0.88))
        #expect(headline.int("fontSize") == 72)
        #expect(data.dict("subtitle")?.double("opacity") == 0.75)
    }

    @Test func layoutAScreenshotCentered() throws {
        let r = run("iphone-6.9-1320x2868", "--layout", "A")
        let ss = try #require(r.json?.dict("screenshot"))
        let ssH = pyRound(2868 * 0.74)
        let ssW = pyRound(Double(ssH) / phoneAspect)
        let ssX = pyRound(Double(1320 - ssW) / 2)
        #expect(ss.int("h") == ssH)
        #expect(ss.int("w") == ssW)
        #expect(ss.int("x") == ssX)
        #expect(ss.int("cornerRadius") == 32)
    }

    @Test func layoutDTallerThanA() throws {
        let a = try #require(run("iphone-6.9-1320x2868", "--layout", "A")
            .json?.dict("screenshot")?.int("h"))
        let d = try #require(run("iphone-6.9-1320x2868", "--layout", "D")
            .json?.dict("screenshot")?.int("h"))
        #expect(d > a)
    }
}

@Suite("Full-bleed and errors")
struct FullBleedAndErrors {
    @Test func fullBleedPassthrough() throws {
        let r = run("appletv-4k-3840x2160")
        #expect(r.exitCode == 0)
        let data = try #require(r.json)
        #expect(data.bool("full_bleed") == true)
        let ss = data.dict("screenshot")
        #expect(ss?.int("w") == 3840)
        #expect(ss?.int("h") == 2160)
        #expect(ss?.int("cornerRadius") == 0)
    }

    @Test func unknownLayoutRejected() {
        // Python's in-process test asserted compute_layout raises ValueError
        // for layout "Z"; at the CLI (the reachable surface) argparse choices
        // reject it — same protective intent, non-zero exit.
        let r = run("iphone-6.9-1320x2868", "--layout", "Z")
        #expect(r.exitCode != 0)
        #expect(r.stderr.contains("--layout"))
    }

    @Test func macUsesLandscapeAspect() throws {
        let r = run("mac-2880x1800", "--layout", "A")
        let ss = try #require(r.json?.dict("screenshot"))
        let macSSH = pyRound(1800 * 0.68)
        let macSSW = pyRound(Double(macSSH) * macAspect)
        #expect(ss.int("h") == macSSH)
        #expect(ss.int("w") == macSSW)
        #expect(ss.int("cornerRadius") == 16)
    }
}

@Suite("CLI shape and self-test")
struct LayoutCliShapeAndSelfTest {
    @Test func jsonStdoutShapeByDeviceKey() throws {
        let r = run("iphone-6.9-1320x2868", "--layout", "A")
        #expect(r.exitCode == 0, "stderr: \(r.stderr)")
        let data = try #require(r.json)   // shape assertion
        let device = data.dict("device")
        #expect(device?.int("w") == 1320)
        #expect(device?.int("h") == 2868)
        for key in ["headline", "subtitle", "screenshot"] {
            #expect(data[key] != nil, "missing key \(key)")
        }
    }

    @Test func fullBleedDeviceJSON() throws {
        let r = run("appletv-4k-3840x2160")
        #expect(r.exitCode == 0)
        #expect(try #require(r.json).bool("full_bleed") == true)
    }

    @Test func selfTestExitZero() {
        let r = run("--self-test")
        #expect(r.exitCode == 0, "stderr: \(r.stderr)")
        #expect(r.stdout.contains("self-test passed"))
    }

    @Test func unknownDeviceKeyExitsNonzero() {
        let r = run("no-such-device-key")
        #expect(r.exitCode != 0)
    }
}

@Suite("CLI entry-point coverage (ported from CLIInProcess)")
struct LayoutCLIEntryPoint {
    @Test func mainSelfTestOK() {
        #expect(run("--self-test").exitCode == 0)
    }

    @Test func mainListDevices() {
        let r = run("--list-devices")
        #expect(r.exitCode == 0)
        #expect(r.stdout.contains("iphone-6.9-1320x2868"))
    }

    @Test func mainDeviceKeyEmitsJSON() throws {
        let r = run("iphone-6.9-1320x2868", "--layout", "A")
        #expect(r.exitCode == 0)
        _ = try #require(r.json)
    }

    @Test func mainManualCanvasIOS() throws {
        let r = run("--w", "1320", "--h", "2868", "--platform", "ios", "--layout", "B")
        #expect(r.exitCode == 0)
        #expect(try #require(r.json)["device"] != nil)
    }

    @Test func mainFullBleedDevice() throws {
        let r = run("appletv-4k-3840x2160")
        #expect(r.exitCode == 0)
        #expect(try #require(r.json).bool("full_bleed") == true)
    }

    @Test func mainNoArgsHelpExit0() {
        let r = run()
        #expect(r.exitCode == 0)   // prints help, exits 0
    }

    @Test func resolveSpecByDeviceKey() throws {
        // Port of _resolve_spec direct-drive: the device key resolves to the
        // registry spec (w/h surfaced through the CLI device block).
        let r = run("iphone-6.9-1320x2868", "--layout", "A")
        let device = try #require(r.json?.dict("device"))
        #expect(device.int("w") == 1320)
        #expect(device.int("h") == 2868)
    }
}
