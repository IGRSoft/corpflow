// LiveGateTests.swift — port of benchmark/tests/live/test_live_gate.py (7) +
// NEW dependency-graph assertion (AC-8 link-level, AR ad4) + capture-mode
// variant coverage.
//
// The Python end-to-end "run the real deterministic benchmark" test is NOT
// ported here: executing run-benchmark.sh from inside `swift test` would nest
// full SwiftPM builds (and, mid-migration, would race the T4 seam retarget).
// Its coverage lives at gate G3 (`make benchmark` runs the real deterministic
// path offline). The static shell-source guards ARE ported below.

import Foundation
import Testing
@testable import BenchmarkKit
@testable import BenchmarkLive

@Suite("Default path never reaches live (AC-8 static)")
struct DefaultPathNeverReachesLive {
    @Test func runBenchmarkDeterministicBranchIsLiveFree() throws {
        let src = try String(
            contentsOfFile: liveTestsRepoRoot + "/benchmark/run-benchmark.sh",
            encoding: .utf8)
        #expect(src.contains("if [ \"$LIVE\" = \"1\" ]"))
        // Split on the LIVE guard; the deterministic else-branch must be live-free.
        let parts = src.components(separatedBy: "\nelse")
        #expect(parts.count >= 2, "run-benchmark.sh must have the LIVE/else split")
        let detBranch = parts.dropFirst().joined(separator: "\nelse")
        #expect(!detBranch.contains("live/dispatch.py"))
        #expect(!detBranch.contains("benchmark/live"))
        #expect(!detBranch.contains("bench-live"))
        #expect(!detBranch.contains("BenchmarkLive"))
    }

    @Test func benchDeterministicSourceDoesNotImportLive() throws {
        // deterministic executable + BenchmarkKit sources never import the live
        // world (the compile-level half is PackageGraphTests in BenchmarkKitTests).
        let dir = liveTestsRepoRoot + "/benchmark/harness/Sources/bench-deterministic"
        let files = try FileManager.default.contentsOfDirectory(atPath: dir)
        for f in files where f.hasSuffix(".swift") {
            let src = try String(contentsOfFile: dir + "/" + f, encoding: .utf8)
            #expect(!src.contains("import BenchmarkLive"),
                    "bench-deterministic/\(f) imports BenchmarkLive")
        }
    }

    @Test func manifestDependencyGraphKeepsDeterministicWorldLiveFree() throws {
        // NEW (ad4): text-level Package.swift assertion — the bench-deterministic
        // and bench-report target declarations depend ONLY on BenchmarkKit.
        let manifest = try String(
            contentsOfFile: liveTestsRepoRoot + "/benchmark/harness/Package.swift",
            encoding: .utf8)
        for target in ["bench-deterministic", "bench-report"] {
            // Anchor on the TARGET declaration (the products section also
            // carries `name: "<target>"` but has no dependencies list).
            let marker = ".executableTarget(name: \"\(target)\""
            let range = try #require(manifest.range(of: marker),
                                     "\(target) target missing from manifest")
            // The declaration line: dependencies list must be exactly BenchmarkKit.
            let lineEnd = manifest[range.upperBound...].firstIndex(of: "\n")
                ?? manifest.endIndex
            let decl = String(manifest[range.upperBound..<lineEnd])
            #expect(decl.contains("dependencies: [\"BenchmarkKit\"]"),
                    "\(target) must depend only on BenchmarkKit, got: \(decl)")
            #expect(!decl.contains("BenchmarkLive"))
        }
    }
}

// `.serialized`: dispatchFailureCarriesChildStderr spawns a real child through
// SubprocessDispatcher → Subprocess.run (a thread in waitUntilExit + two pipe
// drains). Serialized so this suite adds at most one concurrent child, avoiding
// the libdispatch-pool exhaustion that deadlocks a fully parallel `swift test`.
@Suite("Live adapter only dispatches via the seam", .serialized)
struct LiveAdapterOnlyDispatchesViaSeam {
    @Test func tripwireIsTheOnlyDispatchRoute() throws {
        let tripwire = TripwireDispatcher()
        let (benchDir, _, record) = try makeLiveSandbox(stages: ["PL"])
        defer { try? FileManager.default.removeItem(atPath: benchDir) }
        // Budget huge so pre-flight passes; credential present; fake estimate.
        // The tripwire throws on first dispatch -> proves the seam is the route.
        #expect(throws: TripwireDispatcher.Tripped.self) {
            _ = try Dispatch.dispatch(
                workdir: "gate-run", budget: 10_000.0, recordPath: record,
                dispatcher: tripwire,
                env: ["ANTHROPIC_API_KEY": "present-not-logged"],
                estimateRunner: fakeEstimateRunner(0.01),
                promptsDir: benchDir + "/live/prompts",
                stages: ["PL"], benchmarkDir: benchDir, stderr: { _ in })
        }
        #expect(tripwire.called)
    }

    @Test func fakeDispatcherMakesNoSubprocess() throws {
        // A run with a recording fake completes with ZERO real calls and writes
        // a record. Proves the full pipeline is exercisable without spend.
        let fake = RecordingFakeDispatcher(outputs: [
            "{\"usage\": {\"input_tokens\": 10, \"output_tokens\": 5}, \"total_cost_usd\": 0.001}",
        ])
        let (benchDir, prompts, record) = try makeLiveSandbox(stages: ["PL"])
        defer { try? FileManager.default.removeItem(atPath: benchDir) }
        let rc = try Dispatch.dispatch(
            workdir: "gate-fake", budget: 10_000.0, recordPath: record,
            dispatcher: fake, env: ["ANTHROPIC_API_KEY": "present"],
            estimateRunner: fakeEstimateRunner(0.01), promptsDir: prompts,
            stages: ["PL"], benchmarkDir: benchDir, stderr: { _ in })
        #expect(rc == 0)
        #expect(FileManager.default.fileExists(atPath: record))
        #expect(fake.calls.count == 1)
        // The argv targets headless `claude -p` but was never executed (fake).
        let argv = fake.calls[0].argv
        #expect(Array(argv.prefix(2)) == ["claude", "-p"])
        #expect(argv.contains("--output-format"))
        #expect(argv.contains("--permission-mode"))
        #expect(argv.contains("default"))
    }

    @Test func captureModeVariantsProduceTheRightOutputFormat() {
        // Frozen shape (ad2) with json; stream-json is the coverage variant.
        let json = Dispatch.buildStageArgv(stage: "PL", captureMode: .json)
        let stream = Dispatch.buildStageArgv(stage: "PL", captureMode: .streamJSON)
        #expect(json.contains("json") && !json.contains("stream-json"))
        #expect(stream.contains("stream-json"))
        // stream-json REQUIRES --verbose on this CLI generation (reproduced
        // live: "When using --print, --output-format=stream-json requires
        // --verbose", rc=1). json mode must NOT carry it (frozen ad2 shape).
        #expect(stream.contains("--verbose"))
        #expect(!json.contains("--verbose"))
        // Both keep the frozen prefix/flags.
        for argv in [json, stream] {
            #expect(Array(argv.prefix(2)) == ["claude", "-p"])
            #expect(argv.contains("--model"))
            #expect(argv.contains("--effort"))
            #expect(argv.contains("--agent"))
        }
    }

    @Test func dispatchFailureCarriesChildStderr() {
        // QA finding 2a: a failing dispatch must surface the child's stderr
        // (truncated) — otherwise live failures are undiagnosable. Uses a
        // local bash child; no network, no claude.
        let dispatcher = SubprocessDispatcher()
        do {
            _ = try dispatcher.run(
                argv: ["bash", "-c", "echo BOOM-DIAGNOSTIC >&2; exit 3"],
                promptText: "ignored")
            Issue.record("expected DispatchFailure")
        } catch let e as DispatchFailure {
            #expect(e.description.contains("rc=3"))
            #expect(e.description.contains("BOOM-DIAGNOSTIC"),
                    "stderr snippet missing from: \(e.description)")
            #expect(!e.description.contains("ignored"),
                    "prompt text must never leak into dispatch errors")
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }
}

@Suite("Stage table model rows")
struct StageTableModel {
    @Test func drRowUsesOpusXhigh() {
        let dr = STAGE_TABLE["DR"]
        #expect(dr?.agent == "igrsoft:technical-lead")
        #expect(dr?.model == "claude-opus-4-8")
        #expect(dr?.effort == "xhigh")
    }

    @Test func drModelIsOpusNotSonnet() {
        let dr = STAGE_TABLE["DR"]
        #expect(dr?.model == "claude-opus-4-8")
        #expect(dr?.effort == "xhigh")
        #expect(dr?.model.contains("sonnet") == false)
    }
}
