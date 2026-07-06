// BudgetEnforcementTests.swift — port of benchmark/tests/live/
// test_budget_enforcement.py (6 tests). Both gates proven WITHOUT any real
// LLM call; all dispatchers/estimators are injected fakes.

import Foundation
import Testing
@testable import BenchmarkKit
@testable import BenchmarkLive

@Suite("Pre-flight gate (a)")
struct PreflightGate {
    @Test func preflightDeclinesAndDispatchesNothing() throws {
        let tripwire = TripwireDispatcher()
        let (benchDir, prompts, record) = try makeLiveSandbox()
        defer { try? FileManager.default.removeItem(atPath: benchDir) }
        // 10 stages * $1.00/stage = $10 projection vs $1 budget -> decline (rc 2).
        let rc = try Dispatch.dispatch(
            workdir: "budget-preflight", budget: 1.00, recordPath: record,
            dispatcher: tripwire, env: ["ANTHROPIC_API_KEY": "present"],
            estimateRunner: fakeEstimateRunner(1.00), promptsDir: prompts,
            benchmarkDir: benchDir, stderr: { _ in })
        #expect(rc == 2)                                       // D5: pre-flight decline
        #expect(!tripwire.called)                              // dispatched nothing
        #expect(!FileManager.default.fileExists(atPath: record))  // no record on decline
    }

    @Test func budgetModuleThrowsOnProjectionOverBudget() {
        #expect(throws: Budget.BudgetExceeded.self) {
            try Budget.assertPreflightWithinBudget(
                budget: 0.50, stageCount: 10, estimateCalcPath: "/unused",
                runner: fakeEstimateRunner(1.00))
        }
    }

    @Test func budgetModuleAllowsProjectionWithinBudget() throws {
        let projection = try Budget.assertPreflightWithinBudget(
            budget: 100.0, stageCount: 10, estimateCalcPath: "/unused",
            runner: fakeEstimateRunner(1.00))
        #expect(abs(projection - 10.0) < 1e-6)
    }
}

@Suite("Running-tally gate (b)")
struct RunningTallyGate {
    @Test func runningTallyAbortsBeforeBreachingStage() throws {
        // Pre-flight uses the per-stage ESTIMATE ($0.20): 3 * 0.20 = 0.60 <= 1.00
        // budget -> pre-flight passes. REAL measured cost per stage is $0.45:
        //   stage 1: spent 0    -> dispatch -> spent 0.45
        //   stage 2: 0.45+0.20  -> dispatch -> spent 0.90
        //   stage 3: 0.90+0.20 > 1.00 -> ABORT before dispatching stage 3.
        let stageStdout = "{\"usage\": {\"input_tokens\": 100, \"output_tokens\": 50}, "
            + "\"total_cost_usd\": 0.45}"
        let fake = RecordingFakeDispatcher(outputs: [stageStdout, stageStdout, stageStdout])
        let (benchDir, prompts, record) = try makeLiveSandbox(stages: ["PL", "AR", "TL"])
        defer { try? FileManager.default.removeItem(atPath: benchDir) }
        let rc = try Dispatch.dispatch(
            workdir: "budget-tally", budget: 1.00, recordPath: record,
            dispatcher: fake, env: ["ANTHROPIC_API_KEY": "present"],
            estimateRunner: fakeEstimateRunner(0.20), promptsDir: prompts,
            stages: ["PL", "AR", "TL"], benchmarkDir: benchDir, stderr: { _ in })
        // Only 2 of 3 stages dispatched (aborted before the breaching 3rd).
        #expect(fake.calls.count == 2)
        #expect(rc == 4)                                       // D5: tally breach
        // Partial record written BEFORE rc=4 returned (D6).
        #expect(FileManager.default.fileExists(atPath: record))
        let data = try JSONParser.parse(try String(contentsOfFile: record, encoding: .utf8))
        #expect(data["live_partial"]?.boolValue == true)
        #expect(data["mode"]?.stringValue == "live")
        #expect(data["paths"]?["with"]?["pass_fail"]?.stringValue == "fail")
        #expect(data["paths"]?["with"]?["stage_count"]?.intValue == 2)
    }

    @Test func runningTallyCanAffordLogic() {
        let tally = Budget.RunningTally(budget: 1.00)
        #expect(tally.canAfford(0.40))
        tally.add(0.40)
        #expect(tally.canAfford(0.40))    // 0.80 <= 1.00
        tally.add(0.40)
        #expect(!tally.canAfford(0.40))   // 1.20 > 1.00
    }

    @Test func runningTallyNeverFabricatesOnNilCost() {
        let tally = Budget.RunningTally(budget: 1.00)
        tally.add(nil)   // unmeasured stage contributes nothing
        #expect(tally.spentUSD == 0.0)
    }

    @Test func layer3DegradationMarksPartialAndReturnsRC4() throws {
        // Fake returns "{}" (no usage anywhere; no audit.jsonl) -> Layer 3 ->
        // live_partial + rc=4 with the record still written (D6).
        let fake = RecordingFakeDispatcher()
        let (benchDir, prompts, record) = try makeLiveSandbox(stages: ["PL"])
        defer { try? FileManager.default.removeItem(atPath: benchDir) }
        let rc = try Dispatch.dispatch(
            workdir: "budget-degraded", budget: 100.0, recordPath: record,
            dispatcher: fake, env: ["ANTHROPIC_API_KEY": "present"],
            estimateRunner: fakeEstimateRunner(0.01), promptsDir: prompts,
            stages: ["PL"], benchmarkDir: benchDir, stderr: { _ in })
        #expect(rc == 4)
        let data = try JSONParser.parse(try String(contentsOfFile: record, encoding: .utf8))
        #expect(data["live_partial"]?.boolValue == true)
        // Never fabricate: all token fields null.
        let tokens = data["paths"]?["with"]?["tokens"]
        #expect(tokens?["in"]?.isNull == true)
        #expect(tokens?["total"]?.isNull == true)
    }
}
