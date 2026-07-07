// EstimateCalcTests.swift — port of tests/python/test_estimate_calc.py
// (21 behaviors) against the UNCHANGED skills/estimation-methodology/scripts/
// estimate-calc.py, driven via `python3` subprocess (Swift cannot import the
// module in-process; every in-process Python behavior maps to its CLI
// equivalent — same arithmetic contracts, AC-4).

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

private let script = repoRoot + "/skills/estimation-methodology/scripts/estimate-calc.py"

private func run(_ args: String...) -> ScriptResult {
    ScriptRunner.run(script: script, args)
}

private func complexity(factors: [Int]) -> (total: Int, band: String)? {
    let r = ScriptRunner.run(script: script, ["--factors"] + factors.map(String.init))
    guard r.exitCode == 0, let c = r.json?.dict("complexity"),
          let total = c.int("total"), let band = c.string("band") else { return nil }
    return (total, band)
}

@Suite("Complexity band boundaries (AC-4)")
struct ComplexityBandBoundaries {
    @Test func sum10IsLow() {
        let c = complexity(factors: [2, 2, 2, 2, 2])
        #expect(c?.total == 10)
        #expect(c?.band == "LOW")
    }

    @Test func sum15IsMedium() {
        let c = complexity(factors: [3, 3, 3, 3, 3])
        #expect(c?.total == 15)
        #expect(c?.band == "MEDIUM")
    }

    @Test func sum20IsHigh() {
        let c = complexity(factors: [4, 4, 4, 4, 4])
        #expect(c?.total == 20)
        #expect(c?.band == "HIGH")
    }

    @Test func sum25ClampsHigh() {
        let c = complexity(factors: [5, 5, 5, 5, 5])
        #expect(c?.total == 25)
        #expect(c?.band == "HIGH")
    }

    @Test func bandEdges11And17And18() {
        let e11 = complexity(factors: [2, 2, 2, 2, 3])
        #expect(e11?.total == 11)
        #expect(e11?.band == "MEDIUM")
        let e17 = complexity(factors: [3, 4, 3, 4, 3])
        #expect(e17?.total == 17)
        #expect(e17?.band == "MEDIUM")
        let e18 = complexity(factors: [4, 4, 4, 3, 3])
        #expect(e18?.total == 18)
        #expect(e18?.band == "HIGH")
    }

    @Test func belowRangeClampsLow() {
        let c = complexity(factors: [0, 0, 0, 0, 0])
        #expect(c?.total == 0)
        #expect(c?.band == "LOW")
    }
}

@Suite("AI cost arithmetic (AC-4)")
struct AiCostArithmetic {
    @Test func sonnet100kMediumStandard() {
        // 100000/1e6 * 3.0 * (1+0.2) * 1.0 = 0.36
        let r = run("--tokens", "100000", "--model", "sonnet",
                    "--retry-complexity", "medium", "--codebase-type", "standard")
        #expect(r.exitCode == 0)
        let usd = r.json?.dict("ai_cost")?.double("usd")
        #expect(abs((usd ?? 0) - 0.36) < 1e-6)
    }

    @Test func haiku50kHighNovel() {
        // 50000/1e6 * 0.25 * (1+0.5) * 2.0 = 0.0375
        let r = run("--tokens", "50000", "--model", "haiku",
                    "--retry-complexity", "high", "--codebase-type", "novel")
        #expect(r.exitCode == 0)
        let usd = r.json?.dict("ai_cost")?.double("usd")
        #expect(abs((usd ?? 0) - 0.0375) < 1e-6)
    }

    @Test func unknownModelIsRejectedAtTheCLI() {
        // Python's in-process test asserted ai_cost() falls back to the sonnet
        // rate for unknown models; the CLI layer (the only surface a Swift
        // test can reach) instead REJECTS unknown models via argparse choices
        // — the same protective intent (no silent wrong-rate cost). rc=2.
        let r = run("--tokens", "100000", "--model", "nonexistent")
        #expect(r.exitCode == 2)
        #expect(r.stderr.contains("--model"))
    }
}

@Suite("Hours arithmetic (AC-4)")
struct HoursArithmetic {
    @Test func mSeniorBaseHours() {
        // M = (4,5) SP, senior multiplier 6 -> base 24 / 30 hours.
        let r = run("--size", "M", "--level", "senior")
        #expect(r.exitCode == 0)
        let base = r.json?.dict("base_hours")
        #expect(base?.double("min") == 24.0)
        #expect(base?.double("max") == 30.0)
    }

    @Test func mSeniorBufferedTotal() {
        let r = run("--size", "M", "--level", "senior")
        let total = r.json?.dict("total_hours")
        #expect(total?.double("min") == 27.6)
        #expect(total?.double("max") == 34.5)
    }

    @Test func tshirtMLookup() {
        // TSHIRT_SP["M"] == (4, 5), surfaced via the CLI sp block.
        let r = run("--size", "M", "--level", "senior")
        let sp = r.json?.dict("sp")
        #expect(sp?.int("min") == 4)
        #expect(sp?.int("max") == 5)
    }
}

@Suite("CLI shape and self-test")
struct CliShapeAndSelfTest {
    @Test func jsonStdoutShape() throws {
        let r = run("--size", "M", "--level", "senior", "--rate", "150",
                    "--tokens", "100000", "--model", "sonnet",
                    "--factors", "3", "3", "3", "3", "3")
        #expect(r.exitCode == 0, "stderr: \(r.stderr)")
        let data = try #require(r.json)   // shape assertion: parses as JSON object
        let total = data.dict("total_hours")
        #expect(total?.double("min") == 27.6)
        #expect(total?.double("max") == 34.5)
        #expect(abs((data.dict("ai_cost")?.double("usd") ?? 0) - 0.36) < 1e-6)
        #expect(data.dict("complexity")?.int("total") == 15)
        #expect(data.dict("complexity")?.string("band") == "MEDIUM")
    }

    @Test func selfTestExitZero() throws {
        let r = run("--self-test")
        #expect(r.exitCode == 0, "stderr: \(r.stderr)")
        let payload = try #require(r.json)
        #expect(payload.string("self_test") == "ok")
    }

    @Test func noArgsExitsNonzero() {
        // No meaningful input -> help on stderr + exit 1.
        let r = run()
        #expect(r.exitCode == 1)
    }
}

@Suite("CLI entry-point coverage (ported from CLIInProcess)")
struct CLIEntryPoint {
    // The Python originals drove main() in-process purely so coverage.py could
    // record the argparse lines; Swift reaches the same entry point via the
    // CLI (subprocess), asserting the same observable behaviors.

    @Test func mainSelfTestOK() {
        let r = run("--self-test")
        #expect(r.exitCode == 0)
        #expect(r.stdout.contains("self_test"))
    }

    @Test func mainSizeLevelTotalHours() {
        let r = run("--size", "M", "--level", "senior", "--rate", "150")
        #expect(r.exitCode == 0)
        let total = r.json?.dict("total_hours")
        #expect(total?.double("min") == 27.6)
        #expect(total?.double("max") == 34.5)
    }

    @Test func mainFactorsOnlyBand() {
        let r = run("--factors", "3", "3", "2", "2", "3")
        #expect(r.exitCode == 0)
        #expect(r.json?.dict("complexity")?.string("band") == "MEDIUM")
    }

    @Test func mainTokensOnlyAICost() {
        let r = run("--tokens", "100000", "--model", "sonnet",
                    "--retry-complexity", "medium", "--codebase-type", "standard")
        #expect(r.exitCode == 0)
        let usd = r.json?.dict("ai_cost")?.double("usd") ?? 0
        #expect(abs(usd - 0.36) < 1e-4)
    }

    @Test func mainNoInputExits1() {
        let r = run()
        #expect(r.exitCode == 1)
    }

    @Test func sizeLevelParseAndRunDirectly() {
        // Port of _build_parser()/_run() direct-drive: --size L --level mid
        // must yield both an sp block and total_hours.
        let r = run("--size", "L", "--level", "mid")
        #expect(r.exitCode == 0)
        #expect(r.json?.dict("sp") != nil)
        #expect(r.json?.dict("total_hours") != nil)
    }
}
