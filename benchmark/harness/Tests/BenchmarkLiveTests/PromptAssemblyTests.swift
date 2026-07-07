// PromptAssemblyTests.swift — port of benchmark/tests/live/
// test_prompt_assembly.py (6 tests). REQ-1 preamble fidelity: [1][2][3][4][5]
// binding order + cross-stage byte-identity of the [1]+[2] cacheable prefix.

import Foundation
import Testing
@testable import BenchmarkKit
@testable import BenchmarkLive

@Suite("Pure assembler")
struct PureAssembler {
    @Test func markersPresentInBindingOrder() throws {
        let prompt = Preamble.assembleStagePrompt(
            "PL", worktaskID: "wf-x", planFile: ".context/planning-0.md",
            stateJSONText: "{\"stages\":{}}", taskText: "do PL")
        let order = [Preamble.markContract, Preamble.markHeader, Preamble.markState,
                     Preamble.markContractStage, Preamble.markTask]
        var positions: [String.Index] = []
        for m in order {
            let r = try #require(prompt.range(of: m), "marker \(m) missing")
            positions.append(r.lowerBound)
        }
        #expect(positions == positions.sorted(),
                "markers must appear in [1][2][3][4][5] binding order")
    }

    @Test func prefix12ByteIdenticalAcrossStages() {
        let state = "{\"stages\":{\"PL\":{\"status\":\"completed\"}}}"
        let pPL = Preamble.assembleStagePrompt(
            "PL", worktaskID: "wf-x", planFile: ".context/planning-0.md",
            stateJSONText: state, taskText: "pl body")
        let pAR = Preamble.assembleStagePrompt(
            "AR", worktaskID: "wf-x", planFile: ".context/planning-0.md",
            stateJSONText: state, taskText: "ar body")
        // [1] contract-reminder byte-identical.
        #expect(section(pPL, Preamble.markContract) == section(pAR, Preamble.markContract))
        // [2] worktask-header byte-identical (same worktask_id + plan_file).
        #expect(section(pPL, Preamble.markHeader) == section(pAR, Preamble.markHeader))
    }

    @Test func stageContractDiffersPerStageButStableWithinStage() {
        func assemble(_ stage: String) -> String {
            Preamble.assembleStagePrompt(stage, worktaskID: "wf-x", planFile: "p",
                                         stateJSONText: "{}", taskText: "t")
        }
        let pl = assemble("PL")
        let ar = assemble("AR")
        #expect(section(pl, Preamble.markContractStage)
                != section(ar, Preamble.markContractStage))
        let pl2 = assemble("PL")
        #expect(section(pl, Preamble.markContractStage)
                == section(pl2, Preamble.markContractStage))
    }

    @Test func headerContainsOnlyRequiredLiterals() {
        let h = Preamble.header(worktaskID: "wf-x", planFile: ".context/planning-0.md")
        #expect(h.contains("worktask_id: wf-x"))
        #expect(h.contains("plan_file: .context/planning-0.md"))
        // No forbidden tokens: no agent name, no timestamp digits pattern.
        #expect(!h.contains("software-architector"))
        #expect(!h.contains("T00:"))
    }
}

@Suite("Dispatch wiring")
struct DispatchWiring {
    private func runTwoStages() throws -> RecordingFakeDispatcher {
        let fake = RecordingFakeDispatcher(outputs: ["{}", "{}"])
        let tmp = NSTemporaryDirectory() + "wiring-\(UUID().uuidString)"
        let prompts = tmp + "/prompts"
        try FileManager.default.createDirectory(atPath: prompts, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        for stg in ["pl", "ar"] {
            try "\(stg) task body\n".write(toFile: prompts + "/\(stg).txt",
                                           atomically: true, encoding: .utf8)
        }
        let result = try Dispatch.runPipeline(
            workdirPath: tmp + "/wd", budget: 100.0, promptsDir: prompts,
            auditPath: tmp + "/audit.jsonl", dispatcher: fake,
            estimateCalcPath: "/unused", estimateRunner: fakeEstimateRunner(0.01),
            stages: ["PL", "AR"], worktaskID: "wf-live",
            planFile: ".context/planning-0.md")
        #expect(result.dispatched == 2)
        return fake
    }

    @Test func dispatcherGetsAssembledPromptWithAllMarkers() throws {
        let fake = try runTwoStages()
        let firstPrompt = fake.calls[0].prompt
        for marker in ["<<<contract-reminder>>>", "<<<worktask-header>>>",
                       "<<<state-json>>>", "<<<stage-contract>>>", "<<<task>>>"] {
            #expect(firstPrompt.contains(marker), "missing \(marker)")
        }
        // [5] carries the dynamic task body.
        #expect(firstPrompt.contains("pl task body"))
    }

    @Test func prefix12ByteIdenticalAcrossDispatchedStages() throws {
        let fake = try runTwoStages()
        let pPL = fake.calls[0].prompt
        let pAR = fake.calls[1].prompt
        #expect(section(pPL, "<<<contract-reminder>>>")
                == section(pAR, "<<<contract-reminder>>>"))
        #expect(section(pPL, "<<<worktask-header>>>")
                == section(pAR, "<<<worktask-header>>>"))
        // [5] task bodies differ per stage.
        #expect(section(pPL, "<<<task>>>") != section(pAR, "<<<task>>>"))
    }
}
