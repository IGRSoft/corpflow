// DeterministicRun.swift — deterministic dual-path orchestration, port of
// benchmark/lib/deterministic_run.py.
//
// Builds BOTH real TTT apps, records REAL metrics, writes a full-schema
// comparison BenchmarkRecord (mode="deterministic"), and rotates per-mode
// latest-3 history + a per-run detail file. No network, no live.

import Foundation

public enum DeterministicRun {
    public struct Result: Sendable {
        public var record: BenchmarkRecord
        public var exitCode: Int32   // 0 pass, 1 if a generated app's tests failed
    }

    /// YYYYmmddTHHMMSSZ -> YYYY-mm-ddTHH:MM:SSZ (matches deterministic_run._iso).
    public static func iso(from ts: String) -> String {
        let c = Array(ts)
        guard c.count >= 15 else { return ts }
        func s(_ a: Int, _ b: Int) -> String { String(c[a..<b]) }
        return "\(s(0,4))-\(s(4,6))-\(s(6,8))T\(s(9,11)):\(s(11,13)):\(s(13,15))Z"
    }

    public static func run(
        workdir: String, runID: String, timestamp: String, gitSHA: String,
        recordPath: String, history: String, runsDir: String,
        templateDir: String, pluginRoot: String, estimateCalcPath: String,
        estimateRunner: (([String]) -> String)? = nil
    ) throws -> Result {
        let withPM = try Generators.generateWithPlugin(
            workdir: workdir, templateDir: templateDir, pluginRoot: pluginRoot,
            estimateCalcPath: estimateCalcPath, estimateRunner: estimateRunner)
        let withoutPM = try Generators.generateWithoutPlugin(
            workdir: workdir, templateDir: templateDir, pluginRoot: pluginRoot)

        let record = makeRecord(
            runID: runID, timestampUTC: iso(from: timestamp), mode: .deterministic,
            gitSHA: gitSHA, budgetUSD: nil, with: withPM, without: withoutPM)

        // Write the point-in-time record, then rotate history + detail.
        let recordDir = (recordPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: recordDir, withIntermediateDirectories: true)
        try writeRecord(record, to: recordPath)
        try Rotation.rotate(historyPath: history, record: record.toJSON())
        try Rotation.rotateDetail(runsDir: runsDir, runID: runID, record: record.toJSON())

        let allPass = withPM.passFail == "pass" && withoutPM.passFail == "pass"
        return Result(record: record, exitCode: allPass ? 0 : 1)
    }
}
