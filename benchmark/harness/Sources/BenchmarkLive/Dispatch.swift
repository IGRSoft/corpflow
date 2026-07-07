// Dispatch.swift — live full-pipeline dispatch adapter, port of
// benchmark/live/dispatch.py.
//
// Reached ONLY via `run-benchmark.sh --live` -> bench-live (AC-8). Runs the full
// pipeline PL -> AR -> TL -> DV -> DR -> SR -> QA -> DC -> FN -> ST (SR IS in
// the live pipeline, AR delta D3), one stage per headless `claude -p` dispatch,
// summing REAL tokens/cost, budget-gated, credential-gated. Writes a full
// BenchmarkRecord (mode="live") to the record path given by the frozen seam.
//
// FROZEN seam argv: bench-live --workdir <run_id> --budget <usd> --record <path>
//
// Token/cost capture is LAYERED:
//   Layer 1: stage stdout (dual-mode: stream-json NDJSON or single json object;
//            see Coverage.swift) — usage + optional coverage manifest.
//   Layer 2: .context/logs/audit.jsonl `external_dispatch` lines for the stage.
//   Layer 3: tokens=null + record.live_partial=true. NEVER fabricate.
//
// D6: on a running-tally breach the partial record (live_partial=true) is
// written to disk BEFORE rc=4 returns — QA reads results/runs/live/*.json for
// rc=4 partials, not the shell exit.
//
// D6 (OI-2 extension): partial persistence is now INCREMENTAL, not breach-only.
// After EACH completed stage, runPipeline flushes a partial BenchmarkRecord
// (live_partial=true, stages 1..k so far) to the frozen --record path via an
// ATOMIC temp-file+rename write. A crash therefore loses at most the single
// in-flight stage — the prior live run lost PL/AR/TL/DV (the four largest
// stages) because the only write was end-of-run. The final clean-run write
// (buildLiveRecord, livePartial=false) is byte-equivalent to before: these are
// intermediate writes layered UNDER the existing terminal write, and the frozen
// seam argv (--workdir/--budget/--record/--stages) is unchanged (no new flag).
//
// DEPENDENCY INJECTION: the real `claude -p` call is behind the `Dispatching`
// protocol. Production = SubprocessDispatcher; tests inject fakes/tripwires so
// NO real LLM call / spend ever happens in the suite.

import BenchmarkKit
import Foundation

// MARK: - Stage table (public: SSOT test imports it)

/// Per-stage dispatch table: stage -> (agent, model_id, effort).
/// Models/efforts track skills/shared/stage-codes.md + model-selection.md.
public let STAGE_TABLE: [String: (agent: String, model: String, effort: String)] = [
    "PL": ("igrsoft:product-manager", "claude-opus-4-8", "high"),
    "AR": ("igrsoft:software-architector", "claude-opus-4-8", "xhigh"),
    "TL": ("igrsoft:team-lead", "claude-sonnet-4-6", "medium"),
    "DV": ("igrsoft:developer", "claude-opus-4-8", "xhigh"),
    "DR": ("igrsoft:technical-lead", "claude-opus-4-8", "xhigh"),
    "SR": ("igrsoft:security-reviewer", "claude-opus-4-8", "xhigh"),
    "QA": ("igrsoft:qa-engineer", "claude-sonnet-4-6", "high"),
    "DC": ("igrsoft:technical-writer", "claude-haiku-4-5", "low"),
    "FN": ("igrsoft:project-manager", "claude-opus-4-8", "medium"),
    "ST": ("igrsoft:stakeholder", "claude-sonnet-4-6", "medium"),
]

// MARK: - Types

/// Per-stage captured usage. nil fields mean "no real data" (never fabricated).
public struct StageUsage: Sendable, Equatable {
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var costUSD: Double?
    public var captureLayer: Int?     // 1, 2, or nil (Layer 3 = degraded)
    public var cacheRead: Int?
    public var cacheCreation: Int?
    public var coverage: StageCoverage?   // stream-json manifest (option 1)

    public init(inputTokens: Int? = nil, outputTokens: Int? = nil,
                costUSD: Double? = nil, captureLayer: Int? = nil,
                cacheRead: Int? = nil, cacheCreation: Int? = nil,
                coverage: StageCoverage? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.costUSD = costUSD
        self.captureLayer = captureLayer
        self.cacheRead = cacheRead
        self.cacheCreation = cacheCreation
        self.coverage = coverage
    }
}

/// Injectable dispatcher seam. Production shells `claude -p`; tests inject
/// fakes/tripwires. The ONLY route to a real LLM call.
public protocol Dispatching {
    func run(argv: [String], promptText: String) throws -> String
}

public struct DispatchFailure: Error, CustomStringConvertible {
    public let description: String
}

/// Production dispatcher: shell out to headless `claude -p`, prompt on stdin.
/// `workdir`, when set, becomes the subprocess cwd (claude -p has no --cwd).
/// Never echoes the full prompt or any credential in errors.
public struct SubprocessDispatcher: Dispatching {
    public var workdir: String?
    public init(workdir: String? = nil) { self.workdir = workdir }

    public func run(argv: [String], promptText: String) throws -> String {
        let r = Subprocess.run(argv, cwd: workdir, input: promptText)
        if r.exitCode != 0 {
            // Surface the child's stderr (truncated) so failures are
            // diagnosable — never the prompt, never any credential.
            let stderrSnippet = r.stderr
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(400)
            throw DispatchFailure(description:
                "claude -p failed (rc=\(r.exitCode)) for argv \(argv.prefix(6))…"
                + (stderrSnippet.isEmpty ? "" : " stderr: \(stderrSnippet)"))
        }
        return r.stdout
    }
}

// MARK: - Dispatch core

public enum Dispatch {
    /// Output-capture mode for the stage dispatch (coverage option 1).
    public enum CaptureMode: String, Sendable {
        case json = "json"                  // frozen single-object shape (ad2)
        case streamJSON = "stream-json"     // NDJSON with per-event coverage
    }

    /// Construct the exact headless `claude -p` argv for one stage (frozen
    /// shape, AR ad2): [claude, -p, --model, M, --effort, E, --permission-mode,
    /// default, --output-format, <mode>, --agent, A]. The prompt is fed on
    /// STDIN (assembled [1][2][3][4][5]); cwd is a subprocess kwarg.
    /// stream-json additionally requires --verbose on this CLI generation
    /// ("When using --print, --output-format=stream-json requires --verbose" —
    /// reproduced live, rc=1 otherwise); appended AFTER the frozen flags so the
    /// ported argv-shape assertions stay intact.
    public static func buildStageArgv(stage: String,
                                      captureMode: CaptureMode = .json) -> [String] {
        guard let entry = STAGE_TABLE[stage] else { return [] }
        var argv = [
            "claude", "-p",
            "--model", entry.model,
            "--effort", entry.effort,
            "--permission-mode", "default",
            "--output-format", captureMode.rawValue,
            "--agent", entry.agent,
        ]
        if captureMode == .streamJSON {
            argv.append("--verbose")
        }
        return argv
    }

    // MARK: layered usage capture

    /// Layer 2: scan audit.jsonl for this stage's `external_dispatch` usage.
    /// Keeps the LAST matching line. Defensive on every line.
    public static func captureLayer2(auditPath: String, stage: String) -> StageUsage? {
        guard let text = try? String(contentsOfFile: auditPath, encoding: .utf8) else {
            return nil
        }
        var found: StageUsage?
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let rec = try? JSONParser.parse(String(line)), case .object = rec,
                  rec["action"]?.stringValue == "external_dispatch",
                  let meta = rec["metadata"], meta[ "stage"]?.stringValue == stage
            else { continue }
            let usage = meta["usage"]
            let inTok = usage?["input_tokens"]?.intValue
            let outTok = usage?["output_tokens"]?.intValue
            let cr = usage?["cache_read_input_tokens"]?.intValue
            let cc = usage?["cache_creation_input_tokens"]?.intValue
            let cost = usage?["cost_usd"]?.doubleValue ?? usage?["total_cost_usd"]?.doubleValue
            if inTok == nil && outTok == nil && cost == nil && cr == nil && cc == nil {
                continue
            }
            found = StageUsage(inputTokens: inTok, outputTokens: outTok, costUSD: cost,
                               captureLayer: 2, cacheRead: cr, cacheCreation: cc)
        }
        return found
    }

    /// Apply the capture layers in priority order. Never fabricates.
    /// Layer 1 (stdout, dual-mode) -> Layer 2 (audit.jsonl) -> Layer 3 (all nil).
    /// A stream-json coverage manifest survives even when usage falls to Layer 2.
    public static func captureStageUsage(stdout: String, auditPath: String,
                                         stage: String) -> StageUsage {
        let parsed = Coverage.parse(stdout)
        if let parsed, parsed.hasUsage {
            return StageUsage(inputTokens: parsed.inputTokens,
                              outputTokens: parsed.outputTokens,
                              costUSD: parsed.costUSD, captureLayer: 1,
                              cacheRead: parsed.cacheRead,
                              cacheCreation: parsed.cacheCreation,
                              coverage: parsed.coverage)
        }
        if var layer2 = captureLayer2(auditPath: auditPath, stage: stage) {
            layer2.coverage = parsed?.coverage   // manifest (if any) rides along
            return layer2
        }
        // Layer 3: graceful degradation — no real usage; flag partial upstream.
        return StageUsage(captureLayer: nil, coverage: parsed?.coverage)
    }

    // MARK: pipeline

    static func sumOpt(_ values: [Int?]) -> Int? {
        let real = values.compactMap { $0 }
        return real.isEmpty ? nil : real.reduce(0, +)
    }

    static func sumOpt(_ values: [Double?]) -> Double? {
        let real = values.compactMap { $0 }
        return real.isEmpty ? nil : real.reduce(0, +)
    }

    static func readStateJSONText(workdirPath: String) -> String {
        let statePath = workdirPath + "/.context/state.json"
        return (try? String(contentsOfFile: statePath, encoding: .utf8)) ?? ""
    }

    /// Dispatch stages under the running-tally gate. Returns
    /// (perStageUsages, livePartial, stagesDispatched). The stage prompt is
    /// ASSEMBLED via Preamble.assembleStagePrompt (REQ-1). Gate (b): before each
    /// stage, if spent + next_estimate > budget, ABORT before the breaching
    /// dispatch and return what completed so far, flagged partial.
    ///
    /// OI-2: after EACH completed stage, `persistPartial` is invoked with the
    /// stages captured so far (live_partial forced true — an in-progress run is
    /// by definition partial). `dispatch` wires this to an atomic per-stage
    /// record write; tests inject a recorder to assert stages 1..N-1 survive a
    /// throw at N. The callback runs AFTER the usage is appended, so a crash
    /// between the write and the next dispatch loses at most the in-flight stage.
    /// If the dispatcher throws, the last successful `persistPartial` snapshot is
    /// already on disk — the throw propagates unchanged (tests assert the
    /// tripwire), it does not swallow or rewrite the surviving partial.
    public static func runPipeline(
        workdirPath: String, budget: Double, promptsDir: String, auditPath: String,
        dispatcher: Dispatching, estimateCalcPath: String,
        estimateRunner: (([String]) throws -> String)? = nil,
        stages: [String] = Budget.pipelineStages,
        worktaskID: String = "benchmark-ttt",
        planFile: String = ".context/planning-0.md",
        captureMode: CaptureMode = .json,
        persistPartial: (([(String, StageUsage)], _ dispatched: Int) throws -> Void)? = nil
    ) throws -> (usages: [(String, StageUsage)], livePartial: Bool, dispatched: Int) {
        let tally = Budget.RunningTally(budget: budget)
        var usages: [(String, StageUsage)] = []
        var livePartial = false
        var dispatched = 0

        // Section [3]: read once per pipeline from the workdir.
        let stateJSONText = readStateJSONText(workdirPath: workdirPath)

        for stage in stages {
            let nextEstimate = Budget.estimateStageCost(
                estimateCalcPath: estimateCalcPath, runner: estimateRunner)
            if !tally.canAfford(nextEstimate) {
                livePartial = true
                break
            }

            // Missing prompt file is a hard error (matches the Python port,
            // where open() raised) — never silently dispatch an empty [5].
            let promptPath = promptsDir + "/\(stage.lowercased()).txt"
            let taskText = try String(contentsOfFile: promptPath, encoding: .utf8)
            let promptText = Preamble.assembleStagePrompt(
                stage, worktaskID: worktaskID, planFile: planFile,
                stateJSONText: stateJSONText, taskText: taskText)
            let argv = buildStageArgv(stage: stage, captureMode: captureMode)
            // A throw here propagates with the prior stages' partial ALREADY on
            // disk (persisted at the end of the previous iteration) — OI-2.
            let stdout = try dispatcher.run(argv: argv, promptText: promptText)
            let usage = captureStageUsage(stdout: stdout, auditPath: auditPath,
                                          stage: stage)
            usages.append((stage, usage))
            dispatched += 1

            if usage.captureLayer == nil {
                // Layer-3 degradation on any stage marks the record partial.
                livePartial = true
            }
            tally.add(usage.costUSD)

            // OI-2: flush the partial (stages 1..k) atomically after this stage.
            try persistPartial?(usages, dispatched)
        }
        return (usages, livePartial, dispatched)
    }

    /// Assemble the live BenchmarkRecord from captured per-stage usage. WITH
    /// path: summed real tokens/cost + summed cache fields; per-stage
    /// record.stages carries attribution (+ coverage when captured). WITHOUT
    /// path: the no-LLM baseline. pass_fail "fail" when partial.
    public static func buildLiveRecord(
        runID: String, timestampUTC: String, gitSHA: String, budget: Double,
        usages: [(String, StageUsage)], stagesDispatched: Int, livePartial: Bool
    ) -> BenchmarkRecord {
        let stageUsages = usages.map(\.1)
        let inTotal = sumOpt(stageUsages.map(\.inputTokens))
        let outTotal = sumOpt(stageUsages.map(\.outputTokens))
        let tokTotal: Int? = (inTotal == nil && outTotal == nil)
            ? nil : (inTotal ?? 0) + (outTotal ?? 0)
        let costTotal = sumOpt(stageUsages.map(\.costUSD))
        let crTotal = sumOpt(stageUsages.map(\.cacheRead))
        let ccTotal = sumOpt(stageUsages.map(\.cacheCreation))

        let stageAttributions = usages.map { name, u in
            StageAttribution(stage: name, freshIn: u.inputTokens,
                             cacheCreation: u.cacheCreation, cacheRead: u.cacheRead,
                             out: u.outputTokens, costUSD: u.costUSD,
                             coverage: u.coverage)
        }

        let withPass = livePartial ? "fail" : "pass"
        let withP = PathMetrics(
            tokens: Tokens(input: inTotal, output: outTotal, total: tokTotal,
                           cacheRead: crTotal, cacheCreation: ccTotal),
            costUSD: costTotal, wallClockS: 0.0, locProduced: 0, testCount: 0,
            coveragePct: 0.0, estimateComplexityScore: 0,
            stageCount: stagesDispatched, passFail: withPass
        )
        let withoutP = PathMetrics(
            tokens: Tokens(input: nil, output: nil, total: nil), costUSD: nil,
            wallClockS: 0.0, locProduced: 0, testCount: 0, coveragePct: 0.0,
            estimateComplexityScore: 0, stageCount: 1, passFail: "pass"
        )
        return makeRecord(runID: runID, timestampUTC: timestampUTC, mode: .live,
                          gitSHA: gitSHA, budgetUSD: budget, with: withP,
                          without: withoutP, livePartial: livePartial,
                          stages: stageAttributions)
    }

    // MARK: entry point

    /// Run the full live pipeline end-to-end and write the BenchmarkRecord.
    /// Exit-code contract (D5): 0 ok, 2 pre-flight budget decline (dispatch
    /// nothing), 3 no credential (frozen msg to stderr), 4 running-tally breach
    /// or degradation (partial record WRITTEN first, D6). Errors thrown by the
    /// dispatcher propagate (tests assert the tripwire).
    public static func dispatch(
        workdir: String, budget: Double, recordPath: String,
        dispatcher: Dispatching? = nil,
        env: [String: String]? = nil,
        estimateRunner: (([String]) throws -> String)? = nil,
        promptsDir: String? = nil,
        stages: [String] = Budget.pipelineStages,
        cliLoginRunner: (() throws -> String)? = nil,
        benchmarkDir: String,
        captureMode: CaptureMode = .json,
        stderr: ((String) -> Void)? = nil,
        // Internal DI only — NOT part of the frozen bench-live CLI seam. Default
        // (nil) shells the real `git rev-parse` (gitSHA7), unchanged production
        // behavior. Tests inject a stub so no real subprocess runs: Swift
        // Testing's parallel executor can deadlock several concurrent
        // Subprocess.run dispatch-group waits (observed hang, OI-2 test fix).
        gitSHARunner: ((String) -> String)? = nil
    ) throws -> Int32 {
        let warn = stderr ?? { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
        let workdirPath = benchmarkDir + "/workdirs/" + workdir
        let auditPath = workdirPath + "/.context/logs/audit.jsonl"
        let prompts = promptsDir ?? benchmarkDir + "/live/prompts"
        let pluginRoot = (benchmarkDir as NSString).deletingLastPathComponent
        let estimateCalc = pluginRoot
            + "/skills/estimation-methodology/scripts/estimate-calc.py"

        let runID = workdir   // the seam passes run_id as --workdir
        let timestampUTC = nowISO()
        let gitSHA = gitSHARunner?(pluginRoot) ?? gitSHA7(repoRoot: pluginRoot)

        // Default production dispatcher binds this run's workdir as cwd.
        let effectiveDispatcher = dispatcher ?? SubprocessDispatcher(workdir: workdirPath)

        // 1. Credential probe — before ANY dispatch. Never reveals the key or
        //    any CLI-login identity — only presence is checked.
        do {
            try Credentials.requireCredential(env: env, cliLoginRunner: cliLoginRunner)
        } catch let e as Credentials.CredentialError {
            warn(e.description)
            return 3
        }

        // 2. Pre-flight budget gate — dispatch nothing if projection breaches.
        do {
            try Budget.assertPreflightWithinBudget(
                budget: budget, stageCount: stages.count,
                estimateCalcPath: estimateCalc, runner: estimateRunner)
        } catch let e as Budget.BudgetExceeded {
            warn(e.description)
            return 2
        }

        // OI-2: the record dir must exist BEFORE the first per-stage partial
        // flush (previously created only just before the terminal write).
        let recordDir = (recordPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: recordDir,
                                                withIntermediateDirectories: true)

        // 3. Per-stage dispatch under the running-tally gate. After each stage
        //    completes, atomically persist a partial (live_partial=true) so a
        //    crash loses at most the in-flight stage (D6 / OI-2). writeRecord
        //    writes atomically=true (Foundation temp-file + rename), so a crash
        //    mid-write never corrupts the prior good partial (R2).
        let result = try runPipeline(
            workdirPath: workdirPath, budget: budget, promptsDir: prompts,
            auditPath: auditPath, dispatcher: effectiveDispatcher,
            estimateCalcPath: estimateCalc, estimateRunner: estimateRunner,
            stages: stages, captureMode: captureMode,
            persistPartial: { partialUsages, partialDispatched in
                let partial = buildLiveRecord(
                    runID: runID, timestampUTC: timestampUTC, gitSHA: gitSHA,
                    budget: budget, usages: partialUsages,
                    stagesDispatched: partialDispatched, livePartial: true)
                try writeRecord(partial, to: recordPath)
            })

        // 4. Terminal write (full schema, mode="live"). On a clean run this
        //    flips live_partial back to false and is byte-equivalent to the
        //    pre-OI-2 output. Partial runs still write here too — BEFORE rc=4
        //    returns (D6).
        let record = buildLiveRecord(
            runID: runID, timestampUTC: timestampUTC, gitSHA: gitSHA,
            budget: budget, usages: result.usages,
            stagesDispatched: result.dispatched, livePartial: result.livePartial)
        try writeRecord(record, to: recordPath)

        if result.livePartial {
            warn("live run partial: \(result.dispatched)/\(stages.count) stages; "
                + "record written to \(recordPath)")
            return 4
        }
        return 0
    }

    // MARK: small helpers

    public static func nowISO() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    public static func gitSHA7(repoRoot: String) -> String {
        let r = Subprocess.run(["git", "-C", repoRoot, "rev-parse", "--short=7", "HEAD"])
        let sha = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return (r.exitCode == 0 && !sha.isEmpty) ? sha : "nogit"
    }
}
