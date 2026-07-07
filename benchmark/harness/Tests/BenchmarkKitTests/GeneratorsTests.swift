// GeneratorsTests.swift — port of benchmark/tests/with-plugin/test_generators.py
// (20 tests). AC-5 generator real-output validation.
//
// Both generators copy the REAL benchmark/ttt-template (Swift package) into a
// temp workdir and run its Swift Testing suite via nested `swift test` — real
// loc/test_count/pass_fail, no network, no LLM, and (AC-8) the deterministic
// path never links BenchmarkLive (see PackageGraphTests).
//
// Generation is expensive (nested SwiftPM build), so one WITH and one WITHOUT
// result are memoized and shared across the three ported suites — the Python
// original regenerated per class purely for unittest isolation.

import Foundation
import Testing
@testable import BenchmarkKit

private let repoRoot: String = {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // BenchmarkKitTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // harness
        .deletingLastPathComponent()   // benchmark
        .deletingLastPathComponent()   // repo root
        .path
}()

private let templateDir = repoRoot + "/benchmark/ttt-template"
private let estimateCalc = repoRoot + "/skills/estimation-methodology/scripts/estimate-calc.py"

/// Memoized one-shot generation results shared by every suite in this file.
///
/// OI-1 (P1): these two `ttt_test_*` copies must be measured across three suites
/// (via `pm.appPath`), so they cannot be `defer`-swept per-suite. Instead the
/// nested `.build/` cache is already removed inside `GenLib.runAppTests`, and the
/// top-level copies are registered for `atexit` removal — so the process leaves
/// no `ttt_test_*` residue in $TMPDIR after the suite finishes.
private enum SharedGen {
    private static func trackForCleanup(_ path: String) {
        SharedGenCleanup.register(path)
    }

    static let withResult: PathMetrics = {
        let td = NSTemporaryDirectory() + "ttt_test_with_\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: td, withIntermediateDirectories: true)
        trackForCleanup(td)
        return try! Generators.generateWithPlugin(
            workdir: td, templateDir: templateDir, pluginRoot: repoRoot,
            estimateCalcPath: estimateCalc)
    }()
    static let withoutResult: PathMetrics = {
        let td = NSTemporaryDirectory() + "ttt_test_without_\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: td, withIntermediateDirectories: true)
        trackForCleanup(td)
        return try! Generators.generateWithoutPlugin(
            workdir: td, templateDir: templateDir, pluginRoot: repoRoot)
    }()
}

/// Process-exit sweeper for the memoized `SharedGen` copies. `atexit` fires once
/// the test process ends, guaranteeing no `ttt_test_*` dir outlives the run
/// regardless of how many suites read the memoized metrics. All mutable state
/// lives on the shared instance behind an NSLock (Swift 6: no mutable static).
private final class SharedGenCleanup: @unchecked Sendable {
    static let shared = SharedGenCleanup()

    private let lock = NSLock()
    private var paths: [String] = []

    private init() {
        atexit_b { [self] in
            lock.lock(); let toRemove = paths; lock.unlock()
            for p in toRemove { try? FileManager.default.removeItem(atPath: p) }
        }
    }

    func add(_ path: String) {
        lock.lock(); defer { lock.unlock() }
        paths.append(path)
    }

    static func register(_ path: String) { shared.add(path) }
}

@Suite("WITH-plugin generator", .serialized)
struct WithPluginGenerator {
    var pm: PathMetrics { SharedGen.withResult }

    @Test func passFailIsPass() {
        #expect(pm.passFail == "pass", "WITH generator app's Swift test suite must pass")
    }

    @Test func locProducedPositive() {
        #expect(pm.locProduced > 0)
    }

    @Test func testCountPositive() {
        #expect(pm.testCount > 0)
    }

    @Test func stageCountGreaterThanOne() {
        // Staged path must have >1 stages (process-overhead signal).
        #expect(pm.stageCount > 1, "WITH stage_count expected >1, got \(pm.stageCount)")
    }

    @Test func estimateComplexityScorePositive() {
        // WITH drives the real estimate-calc.py -> score must be > 0.
        #expect(pm.estimateComplexityScore > 0,
                "WITH complexity_score expected >0, got \(pm.estimateComplexityScore)")
    }

    @Test func tokensNullInDeterministic() {
        #expect(pm.tokens.input == nil)
        #expect(pm.tokens.output == nil)
        #expect(pm.tokens.total == nil)
    }

    @Test func wallClockSPositive() {
        #expect(pm.wallClockS > 0.0)
    }

    @Test func appDirContainsSwiftPackage() {
        let appDir = pm.appPath ?? ""
        #expect(FileManager.default.fileExists(atPath: appDir + "/Package.swift"),
                "Package.swift missing in \(appDir)")
        #expect(FileManager.default.fileExists(
            atPath: appDir + "/Sources/TicTacToeKit/Engine/Board.swift"),
            "TicTacToeKit engine missing in \(appDir)")
    }
}

@Suite("WITHOUT-plugin generator", .serialized)
struct WithoutPluginGenerator {
    var pm: PathMetrics { SharedGen.withoutResult }

    @Test func passFailIsPass() {
        #expect(pm.passFail == "pass", "WITHOUT generator app's Swift test suite must pass")
    }

    @Test func locProducedPositive() {
        #expect(pm.locProduced > 0)
    }

    @Test func testCountPositive() {
        #expect(pm.testCount > 0)
    }

    @Test func stageCountIsOne() {
        // WITHOUT is single-shot: stage_count must be exactly 1.
        #expect(pm.stageCount == 1, "WITHOUT stage_count expected 1, got \(pm.stageCount)")
    }

    @Test func estimateComplexityScoreIsZero() {
        #expect(pm.estimateComplexityScore == 0)
    }

    @Test func tokensNull() {
        #expect(pm.tokens.total == nil)
    }

    @Test func appDirContainsSwiftPackage() {
        let appDir = pm.appPath ?? ""
        #expect(FileManager.default.fileExists(atPath: appDir + "/Package.swift"),
                "Package.swift missing in \(appDir)")
    }
}

@Suite("Both generators match on quality", .serialized)
struct BothGeneratorsMatchOnQuality {
    var withPM: PathMetrics { SharedGen.withResult }
    var withoutPM: PathMetrics { SharedGen.withoutResult }

    @Test func locProducedEqual() {
        #expect(withPM.locProduced == withoutPM.locProduced,
                "same template must produce equal loc_produced")
    }

    @Test func testCountEqual() {
        #expect(withPM.testCount == withoutPM.testCount,
                "same template must produce equal test_count")
    }

    @Test func bothPass() {
        #expect(withPM.passFail == "pass")
        #expect(withoutPM.passFail == "pass")
    }

    @Test func stageCountDiffers() {
        // Process-overhead comparison: WITH has more stages than WITHOUT.
        #expect(withPM.stageCount > withoutPM.stageCount,
                "WITH must have higher stage_count than WITHOUT")
    }

    @Test func noLiveLinkage() {
        // Swift form of test_no_live_import: no BenchmarkKit source ever imports
        // BenchmarkLive (compile-level AC-8 is asserted in PackageGraphTests; this
        // is the source-text half, mirroring the Python sys.modules tripwire).
        let kitDir = repoRoot + "/benchmark/harness/Sources/BenchmarkKit"
        let fm = FileManager.default
        var offenders: [String] = []
        let files = (try? fm.contentsOfDirectory(atPath: kitDir)) ?? []
        #expect(!files.isEmpty, "BenchmarkKit source dir not found at \(kitDir)")
        for rel in files where rel.hasSuffix(".swift") {
            let text = (try? String(contentsOfFile: kitDir + "/" + rel, encoding: .utf8)) ?? ""
            if text.contains("import BenchmarkLive") { offenders.append(rel) }
        }
        #expect(offenders.isEmpty, "BenchmarkKit sources import BenchmarkLive: \(offenders)")
    }
}
