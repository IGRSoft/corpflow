// ReportTests.swift — port of benchmark/tests/with-plugin/test_report.py
// (8 tests): result.html rendering + app-path surfacing + analysis-row degrade.

import Foundation
import Testing
@testable import BenchmarkKit

private func sampleHistory() -> JSONValue {
    let withP = PathMetrics(
        tokens: Tokens(input: 100, output: 20, total: 120), costUSD: 1.5,
        wallClockS: 0.04, locProduced: 275, testCount: 9, coveragePct: 0.0,
        estimateComplexityScore: 15, stageCount: 5, passFail: "pass",
        appPath: "benchmark/workdirs/RUNID/with"
    )
    let withoutP = PathMetrics(
        tokens: Tokens(input: nil, output: nil, total: nil), costUSD: nil,
        wallClockS: 0.001, locProduced: 275, testCount: 9, coveragePct: 0.0,
        estimateComplexityScore: 0, stageCount: 1, passFail: "pass",
        appPath: "benchmark/workdirs/RUNID/without"
    )
    let record = makeRecord(runID: "RUNID", timestampUTC: "2026-07-01T00:00:00Z",
                            mode: .deterministic, gitSHA: "abc1234", budgetUSD: nil,
                            with: withP, without: withoutP)
    return .object([("deterministic", .array([record.toJSON()]))])
}

private func cacheBearingRecord() -> JSONValue {
    let withP = PathMetrics(
        tokens: Tokens(input: 108592, output: 13160, total: 121752,
                       cacheRead: 677604, cacheCreation: 129094),
        costUSD: 2.5, wallClockS: 1.0, locProduced: 275, testCount: 9,
        coveragePct: 0.0, estimateComplexityScore: 15, stageCount: 3,
        passFail: "pass", appPath: "benchmark/workdirs/CACHE/with"
    )
    let withoutP = PathMetrics(
        tokens: Tokens(input: 1000, output: 100, total: 1100), costUSD: nil,
        wallClockS: 0.1, locProduced: 275, testCount: 9, coveragePct: 0.0,
        estimateComplexityScore: 0, stageCount: 1, passFail: "pass",
        appPath: "benchmark/workdirs/CACHE/without"
    )
    let stages = [
        StageAttribution(stage: "estimate", freshIn: 33482, cacheCreation: 11639,
                         cacheRead: 23022, out: 997, costUSD: 0.1),
        StageAttribution(stage: "create", freshIn: 37652, cacheCreation: 56772,
                         cacheRead: 207310, out: 4227, costUSD: 0.5),
        StageAttribution(stage: "test", freshIn: 37458, cacheCreation: 60683,
                         cacheRead: 447272, out: 7936, costUSD: 0.9),
    ]
    return makeRecord(runID: "CACHE", timestampUTC: "2026-07-01T01:00:00Z",
                      mode: .live, gitSHA: "abc1234", budgetUSD: 5.0,
                      with: withP, without: withoutP, stages: stages).toJSON()
}

/// Mirror the real on-disk legacy live record: 3 token keys, no cache, no stages.
private func legacyOnDiskLiveRecord() -> JSONValue {
    .object([
        ("run_id", .string("OLDLIVE")),
        ("timestamp_utc", .string("2026-06-01T00:00:00Z")),
        ("mode", .string("live")),
        ("git_sha", .string("old1234")),
        ("budget_usd", .double(5.0)),
        ("paths", .object([
            ("with", .object([
                ("tokens", .object([("in", .int(574557)), ("out", .int(7329)),
                                    ("total", .int(581886))])),
                ("cost_usd", .double(3.0)), ("wall_clock_s", .double(1.0)),
                ("loc_produced", .int(275)), ("test_count", .int(9)),
                ("coverage_pct", .double(0.0)),
                ("estimate_complexity_score", .int(0)), ("stage_count", .int(10)),
                ("pass_fail", .string("pass")),
            ])),
            ("without", .object([
                ("tokens", .object([("in", .null), ("out", .null), ("total", .null)])),
                ("cost_usd", .null), ("wall_clock_s", .double(0.1)),
                ("loc_produced", .int(275)), ("test_count", .int(9)),
                ("coverage_pct", .double(0.0)),
                ("estimate_complexity_score", .int(0)), ("stage_count", .int(1)),
                ("pass_fail", .string("pass")),
            ])),
        ])),
        ("comparison", .object([])),
    ])
}

@Suite("Report rendering")
struct ReportRender {
    @Test func containsAllMetricsAndAppPaths() {
        let out = Report.renderHTML(history: sampleHistory())
        #expect(out.contains("<html"))
        for token in ["WITH plugin", "WITHOUT plugin", "tokens total",
                      "complexity score", "stage count", "cost (USD)", "RUNID"] {
            #expect(out.contains(token), "missing token: \(token)")
        }
        #expect(out.contains("benchmark/workdirs/RUNID/with"))
        #expect(out.contains("benchmark/workdirs/RUNID/without"))
        #expect(out.contains("+4"))   // stage_count delta 5 - 1 = 4
    }

    @Test func appPathFallbackWhenMissing() {
        // Remove app_path from the with path; conventional path must surface.
        var hist = sampleHistory()
        if case .object(var top) = hist,
           case .array(var recs) = top[0].1,
           case .object(var recPairs) = recs[0] {
            for (i, pair) in recPairs.enumerated() where pair.0 == "paths" {
                if case .object(var paths) = pair.1,
                   case .object(var withPairs) = paths[0].1 {
                    withPairs.removeAll { $0.0 == "app_path" }
                    paths[0].1 = .object(withPairs)
                    recPairs[i].1 = .object(paths)
                }
            }
            recs[0] = .object(recPairs)
            top[0].1 = .array(recs)
            hist = .object(top)
        }
        let out = Report.renderHTML(history: hist)
        #expect(out.contains("benchmark/workdirs/RUNID/with"))
    }

    @Test func emptyHistoryIsSafe() {
        let out = Report.renderHTML(history: .object([]))
        #expect(out.contains("No benchmark results"))
    }

    @Test func buildReportWritesFile() throws {
        let d = NSTemporaryDirectory() + "report-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: d) }
        let histPath = d + "/history.json"
        let outPath = d + "/result.html"
        try sampleHistory().serialized().write(toFile: histPath, atomically: true, encoding: .utf8)
        try Report.buildReport(historyPath: histPath, outPath: outPath)
        #expect(FileManager.default.fileExists(atPath: outPath))
        let content = try String(contentsOfFile: outPath, encoding: .utf8)
        #expect(content.contains("RUNID"))
    }

    @Test func buildReportMissingHistoryIsSafe() throws {
        let d = NSTemporaryDirectory() + "report-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: d) }
        let outPath = d + "/result.html"
        try Report.buildReport(historyPath: d + "/nope.json", outPath: outPath)
        #expect(FileManager.default.fileExists(atPath: outPath))
        let content = try String(contentsOfFile: outPath, encoding: .utf8)
        #expect(content.contains("No benchmark results"))
    }
}

@Suite("Analysis rows")
struct AnalysisRowsTests {
    @Test func analysisRowsRenderForCacheRecord() {
        let out = Report.renderHTML(history: .object([("live", .array([cacheBearingRecord()]))]))
        for label in ["input:output ratio", "cache-hit %", "per-stage token share",
                      "tokens per LOC", "WITH-vs-WITHOUT premium"] {
            #expect(out.contains(label), "missing analysis label: \(label)")
        }
        // cache-hit % = 677604 / (108592+129094+677604) = 74.03%
        #expect(out.contains("74.03%"))
        #expect(out.contains("estimate"))
        #expect(out.contains("create"))
        #expect(out.contains("test"))
        #expect(out.contains("cache read"))
        #expect(out.contains("cache creation"))
    }

    @Test func analysisRowsDegradeToEmdashForLegacyRecord() {
        let out = Report.renderHTML(history: .object([("live", .array([legacyOnDiskLiveRecord()]))]))
        #expect(out.contains("<html"))
        #expect(out.contains("OLDLIVE"))
        #expect(out.contains("cache-hit %"))   // label still shows
        #expect(out.contains("&mdash;"))       // but degrades to em-dash
        #expect(out.contains("input:output ratio"))
    }

    @Test func reportRendersExistingOnDiskLiveRecordShape() {
        let out = Report.renderHTML(history: .object([("live", .array([legacyOnDiskLiveRecord()]))]))
        #expect(out.contains("581,886"))   // tokens total, formatted
        #expect(out.contains("tokens total"))
        #expect(out.contains("&mdash;"))   // cache-derived rows degrade cleanly
    }
}
