// IncrementalPersistenceTests.swift — OI-2 (P2): per-stage BenchmarkRecord
// persistence. Before this change dispatch wrote the record ONLY at end-of-run,
// so a crash between stages lost ALL prior-stage usage (the live run lost
// PL/AR/TL/DV). Now runPipeline flushes an atomic partial after each completed
// stage; a throw at stage N must leave stages 1..N-1 on disk. Zero live
// dispatch — the Dispatching seam is injected with a stub that throws at N.

import Foundation
import Testing
@testable import BenchmarkKit
@testable import BenchmarkLive

/// Succeeds (returns canned per-stage usage stdout) for the first
/// `throwAtCallIndex - 1` calls, then throws on the `throwAtCallIndex`-th call.
/// 1-based: throwAtCallIndex == 3 means stages 1 and 2 succeed, stage 3 throws.
final class ThrowAtStageDispatcher: Dispatching, @unchecked Sendable {
    struct StageBoom: Error, CustomStringConvertible {
        let description = "injected stage failure (OI-2 crash simulation)"
    }
    private(set) var callCount = 0
    let throwAtCallIndex: Int
    let stageStdout: String

    init(throwAtCallIndex: Int, stageStdout: String) {
        self.throwAtCallIndex = throwAtCallIndex
        self.stageStdout = stageStdout
    }

    func run(argv: [String], promptText: String) throws -> String {
        callCount += 1
        if callCount >= throwAtCallIndex { throw StageBoom() }
        return stageStdout
    }
}

@Suite("OI-2 incremental per-stage persistence")
struct IncrementalPersistence {
    /// AC-OI2-3: a throw at stage N leaves a valid on-disk record with exactly
    /// stages 1..N-1, live_partial=true, real per-stage usage.
    @Test func throwAtStageNPersistsPriorStages() throws {
        // Real usage per stage so the persisted attribution is non-null.
        let stageStdout = "{\"usage\": {\"input_tokens\": 120, \"output_tokens\": 60}, "
            + "\"total_cost_usd\": 0.10}"
        // 4 stages; throw on the 3rd dispatch -> stages PL, AR persisted; TL throws.
        let stages = ["PL", "AR", "TL", "DV"]
        let dispatcher = ThrowAtStageDispatcher(throwAtCallIndex: 3, stageStdout: stageStdout)
        let (benchDir, prompts, record) = try makeLiveSandbox(stages: stages)
        defer { try? FileManager.default.removeItem(atPath: benchDir) }

        // Budget generous; estimate tiny -> gate never aborts, only the throw stops it.
        #expect(throws: ThrowAtStageDispatcher.StageBoom.self) {
            try Dispatch.dispatch(
                workdir: "oi2-throw", budget: 100.0, recordPath: record,
                dispatcher: dispatcher, env: ["ANTHROPIC_API_KEY": "present"],
                estimateRunner: fakeEstimateRunner(0.01), promptsDir: prompts,
                stages: stages, benchmarkDir: benchDir, stderr: { _ in },
                gitSHARunner: { _ in "canary7" })
        }
        // Two stages completed before the throw.
        #expect(dispatcher.callCount == 3)

        // The partial record survived the throw and is valid JSON.
        #expect(FileManager.default.fileExists(atPath: record),
                "per-stage partial must be on disk after a mid-pipeline throw")
        let data = try JSONParser.parse(try String(contentsOfFile: record, encoding: .utf8))
        #expect(data["live_partial"]?.boolValue == true)
        #expect(data["mode"]?.stringValue == "live")

        // Exactly stages 1..N-1 (PL, AR), with real usage.
        let persisted = data["stages"]?.arrayItems ?? []
        #expect(persisted.count == 2, "expected stages PL, AR; got \(persisted.count)")
        #expect(persisted.map { $0["stage"]?.stringValue } == ["PL", "AR"])
        for s in persisted {
            #expect(s["fresh_in"]?.intValue == 120)
            #expect(s["out"]?.intValue == 60)
            #expect(s["cost_usd"]?.doubleValue == 0.10)
        }
        // stage_count reflects the two dispatched stages.
        #expect(data["paths"]?["with"]?["stage_count"]?.intValue == 2)
    }

    /// AC-OI2-1 (clean run): on clean completion the terminal write flips
    /// live_partial back to false and the record holds all stages.
    @Test func cleanRunFlipsLivePartialFalse() throws {
        let stageStdout = "{\"usage\": {\"input_tokens\": 100, \"output_tokens\": 40}, "
            + "\"total_cost_usd\": 0.05}"
        let stages = ["PL", "AR", "TL"]
        let fake = RecordingFakeDispatcher(outputs: Array(repeating: stageStdout, count: 3))
        let (benchDir, prompts, record) = try makeLiveSandbox(stages: stages)
        defer { try? FileManager.default.removeItem(atPath: benchDir) }

        let rc = try Dispatch.dispatch(
            workdir: "oi2-clean", budget: 100.0, recordPath: record,
            dispatcher: fake, env: ["ANTHROPIC_API_KEY": "present"],
            estimateRunner: fakeEstimateRunner(0.01), promptsDir: prompts,
            stages: stages, benchmarkDir: benchDir, stderr: { _ in },
            gitSHARunner: { _ in "canary7" })
        #expect(rc == 0)
        let data = try JSONParser.parse(try String(contentsOfFile: record, encoding: .utf8))
        // live_partial is omit-when-false in the record schema (Metrics.swift):
        // a clean run flips it back off, so the key is absent (== not true).
        #expect(data["live_partial"]?.boolValue != true,
                "clean run must flip live_partial back off (absent/false)")
        #expect((data["stages"]?.arrayItems ?? []).count == 3)
        #expect(data["paths"]?["with"]?["pass_fail"]?.stringValue == "pass")
    }

    /// AC-OI2-1 (intermediate write happens): after stage 1 alone completes, a
    /// partial exists mid-run. Proven by throwing on the 2nd dispatch and reading
    /// the single-stage partial left behind.
    @Test func firstStagePersistedBeforeSecondDispatch() throws {
        let stageStdout = "{\"usage\": {\"input_tokens\": 10, \"output_tokens\": 5}, "
            + "\"total_cost_usd\": 0.01}"
        let stages = ["PL", "AR"]
        let dispatcher = ThrowAtStageDispatcher(throwAtCallIndex: 2, stageStdout: stageStdout)
        let (benchDir, prompts, record) = try makeLiveSandbox(stages: stages)
        defer { try? FileManager.default.removeItem(atPath: benchDir) }

        #expect(throws: ThrowAtStageDispatcher.StageBoom.self) {
            try Dispatch.dispatch(
                workdir: "oi2-first", budget: 100.0, recordPath: record,
                dispatcher: dispatcher, env: ["ANTHROPIC_API_KEY": "present"],
                estimateRunner: fakeEstimateRunner(0.01), promptsDir: prompts,
                stages: stages, benchmarkDir: benchDir, stderr: { _ in },
                gitSHARunner: { _ in "canary7" })
        }
        let data = try JSONParser.parse(try String(contentsOfFile: record, encoding: .utf8))
        #expect(data["live_partial"]?.boolValue == true)
        let persisted = data["stages"]?.arrayItems ?? []
        #expect(persisted.map { $0["stage"]?.stringValue } == ["PL"])
    }
}
