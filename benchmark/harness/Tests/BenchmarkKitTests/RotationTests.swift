// RotationTests.swift — port of benchmark/tests/with-plugin/
// test_rotation_per_mode.py (12 tests). AC-7 per-mode latest-3 rotation.

import Foundation
import Testing
@testable import BenchmarkKit

private func rec(_ mode: Mode, _ ts: String, _ idx: Int = 0) -> JSONValue {
    let pm = PathMetrics(
        tokens: Tokens(input: nil, output: nil, total: nil), costUSD: nil,
        wallClockS: Double(idx), locProduced: 100, testCount: 9, coveragePct: 0.0,
        estimateComplexityScore: 0, stageCount: 1, passFail: "pass"
    )
    let record = makeRecord(
        runID: "\(mode.rawValue)-\(ts)-\(String(format: "%04d", idx))",
        timestampUTC: ts, mode: mode, gitSHA: "sha\(String(format: "%04d", idx))",
        budgetUSD: nil, with: pm, without: pm
    )
    return record.toJSON()
}

private func tempDir() -> String {
    let d = NSTemporaryDirectory() + "rotation-test-\(UUID().uuidString)"
    try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
    return d
}

private func readHistory(_ path: String) throws -> JSONValue {
    try JSONParser.parse(String(contentsOfFile: path, encoding: .utf8))
}

private func seed(_ historyPath: String) throws {
    for (i, ts) in ["2026-01-01T00:00:00Z", "2026-01-02T00:00:00Z",
                    "2026-01-03T00:00:00Z"].enumerated() {
        try Rotation.rotate(historyPath: historyPath, record: rec(.deterministic, ts, i))
    }
    for (i, ts) in ["2026-02-01T00:00:00Z", "2026-02-02T00:00:00Z",
                    "2026-02-03T00:00:00Z"].enumerated() {
        try Rotation.rotate(historyPath: historyPath, record: rec(.live, ts, i + 10))
    }
}

@Suite("Rotation keeps latest-3 per mode")
struct RotateKeepsLatestThreePerMode {
    @Test func seedKeepsAllSix() throws {
        let td = tempDir(); defer { try? FileManager.default.removeItem(atPath: td) }
        let history = td + "/history.json"
        try seed(history)
        let data = try readHistory(history)
        #expect(data["deterministic"]?.arrayItems?.count == 3)
        #expect(data["live"]?.arrayItems?.count == 3)
    }

    @Test func fourthDeterministicDropsOldestDeterministic() throws {
        let td = tempDir(); defer { try? FileManager.default.removeItem(atPath: td) }
        let history = td + "/history.json"
        try seed(history)
        try Rotation.rotate(historyPath: history,
                            record: rec(.deterministic, "2026-01-04T00:00:00Z", 99))
        let det = try readHistory(history)["deterministic"]?.arrayItems ?? []
        #expect(det.count == 3, "deterministic must remain at 3")
        let timestamps = det.compactMap { $0["timestamp_utc"]?.stringValue }
        #expect(!timestamps.contains("2026-01-01T00:00:00Z"), "oldest det should be dropped")
        #expect(timestamps.contains("2026-01-04T00:00:00Z"), "newest det should be present")
    }

    @Test func fourthDeterministicLeavesLiveUntouched() throws {
        let td = tempDir(); defer { try? FileManager.default.removeItem(atPath: td) }
        let history = td + "/history.json"
        try seed(history)
        let before = (try readHistory(history)["live"] ?? .null).serialized()
        try Rotation.rotate(historyPath: history,
                            record: rec(.deterministic, "2026-01-04T00:00:00Z", 99))
        let after = (try readHistory(history)["live"] ?? .null).serialized()
        #expect(before == after, "live bucket must be byte-identical after det rotation")
    }

    @Test func fourthLiveDropsOldestLive() throws {
        let td = tempDir(); defer { try? FileManager.default.removeItem(atPath: td) }
        let history = td + "/history.json"
        try seed(history)
        try Rotation.rotate(historyPath: history, record: rec(.live, "2026-02-04T00:00:00Z", 99))
        let live = try readHistory(history)["live"]?.arrayItems ?? []
        #expect(live.count == 3)
        let timestamps = live.compactMap { $0["timestamp_utc"]?.stringValue }
        #expect(!timestamps.contains("2026-02-01T00:00:00Z"), "oldest live should be dropped")
        #expect(timestamps.contains("2026-02-04T00:00:00Z"))
    }

    @Test func fourthLiveLeavesDeterministicUntouched() throws {
        let td = tempDir(); defer { try? FileManager.default.removeItem(atPath: td) }
        let history = td + "/history.json"
        try seed(history)
        let before = (try readHistory(history)["deterministic"] ?? .null).serialized()
        try Rotation.rotate(historyPath: history, record: rec(.live, "2026-02-04T00:00:00Z", 99))
        let after = (try readHistory(history)["deterministic"] ?? .null).serialized()
        #expect(before == after)
    }

    @Test func orderStableNewestLast() throws {
        let td = tempDir(); defer { try? FileManager.default.removeItem(atPath: td) }
        let history = td + "/history.json"
        try seed(history)
        try Rotation.rotate(historyPath: history,
                            record: rec(.deterministic, "2026-01-04T00:00:00Z", 99))
        let det = try readHistory(history)["deterministic"]?.arrayItems ?? []
        let timestamps = det.compactMap { $0["timestamp_utc"]?.stringValue }
        #expect(timestamps == timestamps.sorted(), "records must be sorted newest-last")
        #expect(timestamps.last == "2026-01-04T00:00:00Z")
    }

    @Test func emptyHistoryFileInitialised() throws {
        let td = tempDir(); defer { try? FileManager.default.removeItem(atPath: td) }
        let path = td + "/new_history.json"
        #expect(!FileManager.default.fileExists(atPath: path))
        try Rotation.rotate(historyPath: path,
                            record: rec(.deterministic, "2026-01-01T00:00:00Z", 1))
        #expect(FileManager.default.fileExists(atPath: path))
        let data = try readHistory(path)
        #expect(data["deterministic"]?.arrayItems?.count == 1)
        #expect(data["live"]?.arrayItems?.count == 0)
    }
}

@Suite("Atomic write")
struct AtomicWriteTests {
    @Test func noTmpFilesLeftAfterWrite() throws {
        let td = tempDir(); defer { try? FileManager.default.removeItem(atPath: td) }
        try Rotation.rotate(historyPath: td + "/history.json",
                            record: rec(.deterministic, "2026-01-01T00:00:00Z", 1))
        let leftovers = ((try? FileManager.default.contentsOfDirectory(atPath: td)) ?? [])
            .filter { $0.hasSuffix(".tmp") }
        #expect(leftovers.isEmpty, "stale tmp files: \(leftovers)")
    }

    @Test func historyIsValidJSONAfterWrite() throws {
        let td = tempDir(); defer { try? FileManager.default.removeItem(atPath: td) }
        let history = td + "/history.json"
        try Rotation.rotate(historyPath: history, record: rec(.live, "2026-01-01T00:00:00Z", 1))
        let data = try readHistory(history)   // throws if corrupt
        #expect(data["deterministic"] != nil)
        #expect(data["live"] != nil)
    }
}

@Suite("Rotate detail")
struct RotateDetailTests {
    @Test func detailFileWritten() throws {
        let td = tempDir(); defer { try? FileManager.default.removeItem(atPath: td) }
        let runs = td + "/runs"
        let record = rec(.deterministic, "2026-01-01T00:00:00Z", 1)
        let runID = record["run_id"]?.stringValue ?? ""
        let path = try Rotation.rotateDetail(runsDir: runs, runID: runID, record: record)
        #expect(FileManager.default.fileExists(atPath: path))
        let data = try readHistory(path)
        #expect(data["run_id"]?.stringValue == runID)
    }

    @Test func fourthDetailPrunesOldest() throws {
        let td = tempDir(); defer { try? FileManager.default.removeItem(atPath: td) }
        let runs = td + "/runs"
        for (i, ts) in ["2026-01-01T00:00:00Z", "2026-01-02T00:00:00Z",
                        "2026-01-03T00:00:00Z", "2026-01-04T00:00:00Z"].enumerated() {
            let record = rec(.deterministic, ts, i)
            try Rotation.rotateDetail(runsDir: runs,
                                      runID: record["run_id"]?.stringValue ?? "",
                                      record: record)
        }
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: runs + "/deterministic")) ?? [])
            .filter { $0.hasSuffix(".json") }
        #expect(files.count == 3, "expected 3 detail files, got \(files)")
    }

    @Test func liveDetailDoesNotTouchDeterministicDir() throws {
        let td = tempDir(); defer { try? FileManager.default.removeItem(atPath: td) }
        let runs = td + "/runs"
        let detRec = rec(.deterministic, "2026-01-01T00:00:00Z", 1)
        try Rotation.rotateDetail(runsDir: runs,
                                  runID: detRec["run_id"]?.stringValue ?? "", record: detRec)
        let before = Set((try? FileManager.default.contentsOfDirectory(atPath: runs + "/deterministic")) ?? [])
        for i in 0..<4 {
            let liveRec = rec(.live, "2026-02-0\(i + 1)T00:00:00Z", i + 10)
            try Rotation.rotateDetail(runsDir: runs,
                                      runID: liveRec["run_id"]?.stringValue ?? "", record: liveRec)
        }
        let after = Set((try? FileManager.default.contentsOfDirectory(atPath: runs + "/deterministic")) ?? [])
        #expect(before == after)
    }
}
