// Generators.swift — deterministic WITH/WITHOUT generators, port of
// benchmark/with-plugin/generate.py + without-plugin/generate.py.
//
// WITH path: drives the REAL estimate-calc.py (subprocess) for the complexity
// score + estimated ai_cost, then materializes the ttt-template as N staged
// operations (stage_count = process-overhead signal, >1).
// WITHOUT path: single-shot copy, stage_count == 1, complexity score 0.
// Both copy benchmark/ttt-template/ (excluding .build/.swiftpm) into the workdir.
//
// Deterministic mode only. No network, no LLM, never imports BenchmarkLive.

import Foundation

public enum Generators {
    /// Five complexity factors for the TTT workload (small, well-understood).
    static let factors = ["3", "3", "3", "3", "3"]
    static let expectedTokens = "100000"

    /// OI-1 (P1): run `body` against a freshly-created ephemeral workdir and
    /// remove that workdir on EVERY exit path — normal return, thrown error, or
    /// early return inside `body`. Callers that generate a throwaway app copy
    /// (tests, ad-hoc measurements) use this instead of hand-rolling a
    /// `NSTemporaryDirectory()` dir they then leak (the two ENOSPC live kills).
    /// The `defer` is scoped to the workdir this helper OWNS — a persistent
    /// `--workdir` passed to `generateWith*` directly is never touched (R3).
    @discardableResult
    public static func withEphemeralWorkdir<T>(
        prefix: String = "ttt_gen_",
        _ body: (_ workdir: String) throws -> T
    ) throws -> T {
        let fm = FileManager.default
        let workdir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent(prefix + UUID().uuidString)
        try fm.createDirectory(atPath: workdir, withIntermediateDirectories: true)
        defer { try? fm.removeItemIfExists(atPath: workdir) }
        return try body(workdir)
    }

    /// Drive the REAL estimate-calc.py. Returns (complexityTotal, aiCostUSD?).
    /// On any failure the cost degrades to nil (never fabricated) — the score
    /// falls back to 0 so a broken estimate never crashes a deterministic run.
    public static func runEstimate(estimateCalcPath: String,
                                   runner: (([String]) -> String)? = nil)
        -> (score: Int, cost: Double?) {
        let argv = [
            "python3", estimateCalcPath,
            "--size", "M", "--level", "senior",
            "--factors", factors[0], factors[1], factors[2], factors[3], factors[4],
            "--tokens", expectedTokens, "--model", "sonnet",
        ]
        let stdout: String
        if let runner {
            stdout = runner(argv)
        } else {
            let r = Subprocess.run(argv)
            guard r.exitCode == 0 else { return (0, nil) }
            stdout = r.stdout
        }
        guard let parsed = try? JSONParser.parse(stdout) else { return (0, nil) }
        let score = parsed["complexity"]?["total"]?.intValue ?? 0
        let cost = parsed["ai_cost"]?["usd"]?.doubleValue
        return (score, cost)
    }

    /// WITH generator: staged scaffold driven by the real estimate.
    public static func generateWithPlugin(
        workdir: String, templateDir: String, pluginRoot: String, estimateCalcPath: String,
        estimateRunner: (([String]) -> String)? = nil
    ) throws -> PathMetrics {
        let appDir = (workdir as NSString).appendingPathComponent("with")
        let timer = GenLib.Timer(); timer.start()
        let (score, _) = runEstimate(estimateCalcPath: estimateCalcPath, runner: estimateRunner)
        let stageCount = try GenLib.copyTemplateStaged(templateDir: templateDir, dest: appDir)
        let elapsed = timer.elapsed
        // Deterministic mode records cost as null (estimate is not real spend).
        return GenLib.buildPathMetrics(
            appDir: appDir, pluginRoot: pluginRoot, stageCount: stageCount,
            estimateComplexityScore: score, costUSD: nil, wallClockS: elapsed
        )
    }

    /// WITHOUT generator: single-shot copy, no estimate, no staging.
    public static func generateWithoutPlugin(
        workdir: String, templateDir: String, pluginRoot: String
    ) throws -> PathMetrics {
        let appDir = (workdir as NSString).appendingPathComponent("without")
        let timer = GenLib.Timer(); timer.start()
        let stageCount = try GenLib.copyTemplateSingleShot(templateDir: templateDir, dest: appDir)
        let elapsed = timer.elapsed
        return GenLib.buildPathMetrics(
            appDir: appDir, pluginRoot: pluginRoot, stageCount: stageCount,
            estimateComplexityScore: 0, costUSD: nil, wallClockS: elapsed
        )
    }
}
