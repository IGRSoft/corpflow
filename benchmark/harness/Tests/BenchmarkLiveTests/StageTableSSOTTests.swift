// StageTableSSOTTests.swift — port of benchmark/tests/with-plugin/
// test_stage_table_ssot.py (3 tests). STAGE_TABLE is the machine-checked SSOT
// for per-stage (model, effort) tiers, pinned against
// skills/shared/stage-codes.md's Model column (parsed at test time, not
// hand-copied). Swift imports STAGE_TABLE directly — the test target
// legitimately links BenchmarkLive (no tripwire concern, AR ad4/patterns).

import Foundation
import Testing
@testable import BenchmarkLive

/// Model-id -> tier-alias map (STAGE_TABLE stores concrete IDs; stage-codes.md
/// stores the alias). Mirrors skills/shared/model-selection.md.
private let modelIDToAlias = [
    "claude-opus-4-8": "opus",
    "claude-sonnet-4-6": "sonnet",
    "claude-haiku-4-5": "haiku",
]

/// Effort tiers are NOT in stage-codes.md (that file tracks model only); pinned
/// as a small literal map per the canonical orchestration contract (RK-A7:
/// avoid brittle prose parsing for the effort field).
private let expectedEffort = [
    "PL": "high", "AR": "xhigh", "TL": "medium", "DV": "xhigh", "DR": "xhigh",
    "SR": "xhigh", "QA": "high", "DC": "low", "FN": "medium", "ST": "medium",
]

/// Parse `| CODE | Stage | agent | model |` rows from stage-codes.md's Primary
/// Stages table. Returns [stage_code: model_alias]. Defensive: skips header /
/// separator rows and anything not matching 4 pipe-delimited cells.
private func parseStageCodesModelColumn() throws -> [String: String] {
    let path = liveTestsRepoRoot + "/skills/shared/stage-codes.md"
    let text = try String(contentsOfFile: path, encoding: .utf8)
    var mapping: [String: String] = [:]
    let rowRE = try NSRegularExpression(
        pattern: #"^\|\s*([A-Z]{2,3})\s*\|\s*[^|]+\|\s*[^|]+\|\s*(opus|sonnet|haiku)\s*\|\s*$"#,
        options: [.anchorsMatchLines])
    let range = NSRange(text.startIndex..., in: text)
    for m in rowRE.matches(in: text, range: range) {
        guard let codeR = Range(m.range(at: 1), in: text),
              let modelR = Range(m.range(at: 2), in: text) else { continue }
        mapping[String(text[codeR])] = String(text[modelR])
    }
    return mapping
}

@Suite("STAGE_TABLE SSOT vs stage-codes.md")
struct StageTableSSOT {
    @Test func stageCodesMDModelColumnMatchesStageTable() throws {
        let docModels = try parseStageCodesModelColumn()
        #expect(!docModels.isEmpty, "failed to parse any rows from stage-codes.md")
        #expect(!STAGE_TABLE.isEmpty)
        var mismatches: [String] = []
        for (code, entry) in STAGE_TABLE {
            guard let expectedAlias = docModels[code] else { continue }  // e.g. IR
            let actualAlias = modelIDToAlias[entry.model] ?? entry.model
            if actualAlias != expectedAlias {
                mismatches.append("\(code): STAGE_TABLE=\(actualAlias) (\(entry.model)) "
                    + "vs stage-codes.md=\(expectedAlias)")
            }
        }
        #expect(mismatches.isEmpty,
                "STAGE_TABLE model tier drifted from stage-codes.md: \(mismatches.joined(separator: "; "))")
    }

    @Test func drRowIsOpusXhigh() {
        let dr = STAGE_TABLE["DR"]
        #expect(dr?.agent == "igrsoft:technical-lead")
        #expect(dr?.model == "claude-opus-4-8")
        #expect(dr?.effort == "xhigh")
    }

    @Test func effortTiersMatchExpectedMap() {
        var mismatches: [String] = []
        for (code, entry) in STAGE_TABLE {
            guard let expected = expectedEffort[code] else { continue }
            if entry.effort != expected {
                mismatches.append("\(code): STAGE_TABLE effort=\(entry.effort) vs expected=\(expected)")
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches.joined(separator: "; "))")
    }

    @Test func stageTableCoversTheFullTenStagePipeline() {
        // D3: SR IS in the live pipeline; the table covers exactly the 10 stages.
        #expect(Set(STAGE_TABLE.keys) == Set(Budget.pipelineStages))
        #expect(Budget.pipelineStages == ["PL", "AR", "TL", "DV", "DR", "SR",
                                          "QA", "DC", "FN", "ST"])
    }
}
