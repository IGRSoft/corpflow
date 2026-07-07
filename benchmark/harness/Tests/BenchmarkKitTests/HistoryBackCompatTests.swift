// HistoryBackCompatTests.swift — NEW suite (AR risk R1): the Swift schema MUST
// decode today's REAL benchmark/results/history.json (vendored verbatim under
// Fixtures/). The vendored copy includes a legacy live record whose tokens
// carry only 3 keys (in/out/total, no cache keys) and float artifacts like
// 0.6807679999999999 — decode must tolerate all of it, and rotation on a copy
// must preserve the other mode's bucket byte-identically.

import Foundation
import Testing
@testable import BenchmarkKit

private func fixtureText() throws -> String {
    let url = try #require(Bundle.module.url(forResource: "history", withExtension: "json",
                                             subdirectory: "Fixtures"))
    return try String(contentsOf: url, encoding: .utf8)
}

@Suite("History back-compat (vendored real history.json)")
struct HistoryBackCompat {
    @Test func vendoredHistoryParses() throws {
        let parsed = try JSONParser.parse(try fixtureText())
        #expect(parsed["deterministic"]?.arrayItems?.count == 3)
        #expect(parsed["live"]?.arrayItems?.count == 1)
    }

    @Test func everyRecordDecodesThroughSchema() throws {
        let parsed = try JSONParser.parse(try fixtureText())
        for mode in ["deterministic", "live"] {
            for recJSON in parsed[mode]?.arrayItems ?? [] {
                let rec = BenchmarkRecord.fromJSON(recJSON)
                #expect(!rec.runID.isEmpty)
                #expect(rec.mode.rawValue == mode)
                #expect(rec.pathWith != nil)
                #expect(rec.pathWithout != nil)
            }
        }
    }

    @Test func legacyLiveRecordTokensDecodeWithNilCache() throws {
        let parsed = try JSONParser.parse(try fixtureText())
        let live = try #require(parsed["live"]?.arrayItems?.first)
        let rec = BenchmarkRecord.fromJSON(live)
        let tokens = try #require(rec.pathWith?.tokens)
        #expect(tokens.input == 574557)
        #expect(tokens.output == 7329)
        #expect(tokens.total == 581886)
        // Legacy record lacks cache keys — decode yields nil, never fabricated.
        #expect(tokens.cacheRead == nil)
        #expect(tokens.cacheCreation == nil)
        #expect(rec.pathWith?.costUSD == 1.241815)
        #expect(rec.stages.isEmpty)
        #expect(!rec.livePartial)
    }

    @Test func deterministicRecordsCarryAppPathAndFiveTokenKeys() throws {
        let parsed = try JSONParser.parse(try fixtureText())
        for recJSON in parsed["deterministic"]?.arrayItems ?? [] {
            let tokenKeys = (recJSON["paths"]?["with"]?["tokens"]?.objectPairs ?? []).map(\.0)
            #expect(tokenKeys == ["in", "out", "total", "cache_read", "cache_creation"])
            let rec = BenchmarkRecord.fromJSON(recJSON)
            #expect(rec.pathWith?.appPath?.hasPrefix("benchmark/workdirs/") == true)
        }
    }

    @Test func floatArtifactsSurviveReserialization() throws {
        // Python emitted 0.035500000000000004 / 0.6807679999999999 — the ordered
        // serializer must round-trip these doubles exactly (shortest-round-trip
        // repr identical to Python's).
        let parsed = try JSONParser.parse(try fixtureText())
        let text = parsed.serialized()
        #expect(text.contains("0.035500000000000004"))
        #expect(text.contains("0.6807679999999999"))
    }

    @Test func rotationOnRealHistoryPreservesOtherMode() throws {
        // Copy the vendored file to a temp path, rotate in a new deterministic
        // record, and assert the live bucket stays byte-identical + det stays 3.
        let td = NSTemporaryDirectory() + "backcompat-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: td, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: td) }
        let historyPath = td + "/history.json"
        try (try fixtureText()).write(toFile: historyPath, atomically: true, encoding: .utf8)

        let liveBefore = (try JSONParser.parse(
            try String(contentsOfFile: historyPath, encoding: .utf8))["live"] ?? .null).serialized()

        let pm = PathMetrics(
            tokens: Tokens(input: nil, output: nil, total: nil), costUSD: nil,
            wallClockS: 0.01, locProduced: 500, testCount: 48, coveragePct: 0.0,
            estimateComplexityScore: 15, stageCount: 9, passFail: "pass",
            appPath: "benchmark/workdirs/new/with"
        )
        let newRec = makeRecord(runID: "deterministic-new", timestampUTC: "2026-07-06T00:00:00Z",
                                mode: .deterministic, gitSHA: "abc1234", budgetUSD: nil,
                                with: pm, without: pm)
        try Rotation.rotate(historyPath: historyPath, record: newRec.toJSON())

        let after = try JSONParser.parse(try String(contentsOfFile: historyPath, encoding: .utf8))
        #expect((after["live"] ?? .null).serialized() == liveBefore,
                "live bucket must be untouched by a deterministic rotation")
        let det = after["deterministic"]?.arrayItems ?? []
        #expect(det.count == 3)
        #expect(det.last?["run_id"]?.stringValue == "deterministic-new")
    }
}
