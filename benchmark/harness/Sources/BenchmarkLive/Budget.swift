// Budget.swift — budget enforcement for live dispatch, port of
// benchmark/live/budget.py.
//
// Two gates:
//   (a) PRE-FLIGHT estimate before stage 1: projection > budget -> decline
//       BEFORE any dispatch (rc=2 at the Dispatch layer).
//   (b) RUNNING-TALLY abort before EACH stage: spent + next_estimate > budget ->
//       abort, partial record with live_partial=true written BEFORE rc=4 (D6).
//
// Neither gate fabricates spend — the tally only accumulates REAL per-stage
// costs the capture layers actually returned (None adds nothing).

import BenchmarkKit
import Foundation

public enum Budget {
    /// Per-stage expected token budget used ONLY for cost ESTIMATION.
    public static let perStageExpectedTokens = 40_000

    /// The 10-stage full pipeline (PL -> ... -> ST) the live WITH-path runs.
    /// SR is IN the live pipeline (AR delta D3) even when a given worktask
    /// drops it as a stage.
    public static let pipelineStages = ["PL", "AR", "TL", "DV", "DR", "SR",
                                        "QA", "DC", "FN", "ST"]

    public struct BudgetExceeded: Error, CustomStringConvertible {
        public let description: String
    }

    /// Project one stage's USD cost via the REAL estimate-calc.py `ai_cost`
    /// chain. `runner` is injectable ((argv) -> String stdout); defaults to a
    /// subprocess call. On ANY parse/exec failure returns 0.0 defensively — a
    /// failed ESTIMATE must never block a run on its own.
    public static func estimateStageCost(
        tokens: Int = perStageExpectedTokens,
        model: String = "opus",
        retryComplexity: String = "high",
        estimateCalcPath: String,
        runner: (([String]) throws -> String)? = nil
    ) -> Double {
        let argv = ["python3", estimateCalcPath,
                    "--tokens", String(tokens),
                    "--model", model,
                    "--retry-complexity", retryComplexity]
        let stdout: String
        if let runner {
            guard let out = try? runner(argv) else { return 0.0 }
            stdout = out
        } else {
            let r = Subprocess.run(argv)
            guard r.exitCode == 0 else { return 0.0 }
            stdout = r.stdout
        }
        guard let parsed = try? JSONParser.parse(stdout),
              let usd = parsed["ai_cost"]?["usd"]?.doubleValue else { return 0.0 }
        return usd
    }

    /// Whole-run projection = per-stage estimate * stage count.
    public static func preflightProjection(
        stageCount: Int, estimateCalcPath: String,
        runner: (([String]) throws -> String)? = nil
    ) -> Double {
        estimateStageCost(estimateCalcPath: estimateCalcPath, runner: runner)
            * Double(stageCount)
    }

    /// Gate (a). Throws BudgetExceeded if the projection exceeds budget; else
    /// returns the projection. Dispatch NOTHING on failure.
    @discardableResult
    public static func assertPreflightWithinBudget(
        budget: Double, stageCount: Int, estimateCalcPath: String,
        runner: (([String]) throws -> String)? = nil
    ) throws -> Double {
        let projection = preflightProjection(
            stageCount: stageCount, estimateCalcPath: estimateCalcPath, runner: runner)
        if projection > budget {
            throw BudgetExceeded(description: String(
                format: "pre-flight projection $%.4f exceeds budget $%.4f for %d stages; dispatching nothing",
                projection, budget, stageCount))
        }
        return projection
    }

    /// Gate (b). Accumulates REAL per-stage spend; decides if the next stage fits.
    public final class RunningTally {
        public let budget: Double
        public private(set) var spentUSD: Double = 0.0

        public init(budget: Double) { self.budget = budget }

        /// True iff dispatching the next stage would NOT breach the cap.
        public func canAfford(_ nextStageEstimate: Double) -> Bool {
            spentUSD + nextStageEstimate <= budget
        }

        /// Add a stage's REAL measured cost. nil (unmeasured) adds nothing —
        /// never fabricates; the record is independently flagged live_partial.
        public func add(_ realCost: Double?) {
            if let realCost { spentUSD += realCost }
        }
    }
}
