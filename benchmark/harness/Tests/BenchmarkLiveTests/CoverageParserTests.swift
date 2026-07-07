// CoverageParserTests.swift — NEW suite for the dual-mode capture parser
// (coverage option 1). Never fabricates: unparseable -> nil.

import Foundation
import Testing
@testable import BenchmarkKit
@testable import BenchmarkLive

@Suite("Coverage dual-mode parser")
struct CoverageParser {
    @Test func singleObjectJSONYieldsUsageNoCoverage() {
        let stdout = "{\"usage\": {\"input_tokens\": 100, \"output_tokens\": 20, "
            + "\"cache_read_input_tokens\": 5000, \"cache_creation_input_tokens\": 300}, "
            + "\"total_cost_usd\": 0.42}"
        let parsed = Coverage.parse(stdout)
        #expect(parsed?.inputTokens == 100)
        #expect(parsed?.outputTokens == 20)
        #expect(parsed?.cacheRead == 5000)
        #expect(parsed?.cacheCreation == 300)
        #expect(parsed?.costUSD == 0.42)
        #expect(parsed?.coverage == nil)
    }

    @Test func streamJSONYieldsCoverageManifestAndResultUsage() {
        let lines = [
            // Task tool_use -> agent
            "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\","
                + "\"name\":\"Task\",\"input\":{\"subagent_type\":\"apple-developer:macos-developer\","
                + "\"prompt\":\"build\"}}]}}",
            // Skill tool_use -> skill
            "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\","
                + "\"name\":\"Skill\",\"input\":{\"skill\":\"swiftui-skills\"}}]}}",
            // Skill invoking a slash command form -> command
            "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\","
                + "\"name\":\"Skill\",\"input\":{\"skill\":\"/swiftui-review\"}}]}}",
            // Plain tool_use (counts toward tool_calls only)
            "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\","
                + "\"name\":\"Bash\",\"input\":{\"command\":\"swift test\"}}]}}",
            // Terminal result line: usage + cost (Layer-1 shape)
            "{\"type\":\"result\",\"usage\":{\"input_tokens\":1000,\"output_tokens\":50,"
                + "\"cache_read_input_tokens\":9000,\"cache_creation_input_tokens\":800},"
                + "\"total_cost_usd\":1.25}",
        ]
        let parsed = Coverage.parse(lines.joined(separator: "\n"))
        #expect(parsed?.inputTokens == 1000)
        #expect(parsed?.outputTokens == 50)
        #expect(parsed?.cacheRead == 9000)
        #expect(parsed?.cacheCreation == 800)
        #expect(parsed?.costUSD == 1.25)
        let cov = parsed?.coverage
        #expect(cov?.agents == ["apple-developer:macos-developer"])
        #expect(cov?.skills == ["swiftui-skills"])
        #expect(cov?.commands == ["/swiftui-review"])
        #expect(cov?.toolCalls == 4)
    }

    @Test func streamWithoutResultLineKeepsCoverageUsageNil() {
        let lines = [
            "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\","
                + "\"name\":\"Skill\",\"input\":{\"skill\":\"swift-testing-entry\"}}]}}",
            "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\","
                + "\"text\":\"working\"}]}}",
        ]
        let parsed = Coverage.parse(lines.joined(separator: "\n"))
        #expect(parsed != nil)
        #expect(parsed?.hasUsage == false)
        #expect(parsed?.coverage?.skills == ["swift-testing-entry"])
        #expect(parsed?.coverage?.toolCalls == 1)
    }

    @Test func garbageYieldsNil() {
        #expect(Coverage.parse("") == nil)
        #expect(Coverage.parse("not json at all") == nil)
        #expect(Coverage.parse("{\"no_usage\": true}") == nil)
        // Multi-line garbage
        #expect(Coverage.parse("garbage\nmore garbage\n") == nil)
    }

    @Test func captureStageUsageFallsBackToAuditLayer2KeepingCoverage() throws {
        // stdout: stream events with coverage but NO result usage; audit.jsonl
        // carries Layer-2 usage for the stage -> combined (layer 2 + manifest).
        let tmp = NSTemporaryDirectory() + "coverage-l2-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        let audit = tmp + "/audit.jsonl"
        let auditLine = "{\"action\":\"external_dispatch\",\"metadata\":{\"stage\":\"DV\","
            + "\"usage\":{\"input_tokens\":777,\"output_tokens\":33,\"cost_usd\":0.9}}}"
        try (auditLine + "\n").write(toFile: audit, atomically: true, encoding: .utf8)

        let stdout = [
            "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\","
                + "\"name\":\"Task\",\"input\":{\"subagent_type\":\"apple-developer:ios-developer\"}}]}}",
            "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"…\"}]}}",
        ].joined(separator: "\n")

        let usage = Dispatch.captureStageUsage(stdout: stdout, auditPath: audit, stage: "DV")
        #expect(usage.captureLayer == 2)
        #expect(usage.inputTokens == 777)
        #expect(usage.outputTokens == 33)
        #expect(usage.costUSD == 0.9)
        #expect(usage.coverage?.agents == ["apple-developer:ios-developer"])
    }

    @Test func captureStageUsageLayer3WhenNothingYields() {
        let usage = Dispatch.captureStageUsage(stdout: "", auditPath: "/nonexistent",
                                               stage: "PL")
        #expect(usage.captureLayer == nil)
        #expect(usage.inputTokens == nil)
        #expect(usage.costUSD == nil)
        #expect(usage.coverage == nil)
    }

    @Test func coverageManifestRidesIntoTheRecordStages() throws {
        // End-to-end: a stream-json stage output produces a record whose
        // stages[0] carries the additive coverage object AFTER cost_usd (D2).
        let streamOut = [
            "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\","
                + "\"name\":\"Skill\",\"input\":{\"skill\":\"accessibility-patterns\"}}]}}",
            "{\"type\":\"result\",\"usage\":{\"input_tokens\":10,\"output_tokens\":5},"
                + "\"total_cost_usd\":0.01}",
        ].joined(separator: "\n")
        let fake = RecordingFakeDispatcher(outputs: [streamOut])
        let (benchDir, prompts, record) = try makeLiveSandbox(stages: ["PL"])
        defer { try? FileManager.default.removeItem(atPath: benchDir) }
        let rc = try Dispatch.dispatch(
            workdir: "coverage-e2e", budget: 100.0, recordPath: record,
            dispatcher: fake, env: ["ANTHROPIC_API_KEY": "present"],
            estimateRunner: fakeEstimateRunner(0.01), promptsDir: prompts,
            stages: ["PL"], benchmarkDir: benchDir,
            captureMode: .streamJSON, stderr: { _ in })
        #expect(rc == 0)
        let data = try JSONParser.parse(try String(contentsOfFile: record, encoding: .utf8))
        let s0 = data["stages"]?.arrayItems?.first
        let keys = (s0?.objectPairs ?? []).map(\.0)
        #expect(keys == ["stage", "fresh_in", "cache_creation", "cache_read", "out",
                         "cost_usd", "coverage"])
        #expect(s0?["coverage"]?["skills"]?.arrayItems?.first?.stringValue
                == "accessibility-patterns")
    }
}
