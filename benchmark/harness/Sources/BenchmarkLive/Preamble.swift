// Preamble.swift — production-faithful stage-prompt assembly (REQ-1), port of
// benchmark/live/preamble.py.
//
// The live A/B benchmark must exercise the SAME cache-prefix byte layout the
// production orchestrator ships. `assembleStagePrompt` is a PURE function
// (inputs -> String, no I/O). Marker literals are byte-identical to
// cache-lint.sh so a captured live prompt-log lints with the production
// prefix_lint. Layout (binding):
//
//   [1] <<<contract-reminder>>>  CONTRACT_REMINDER   (byte-stable ALL stages)
//   [2] <<<worktask-header>>>    worktask_id/plan     (byte-stable ALL stages)
//   [3] <<<state-json>>>         inlined state.json   (evolves per stage)
//   [4] <<<stage-contract>>>     STAGE_CONTRACT[code] (byte-stable WITHIN stage)
//   [5] <<<task>>>               prompts/<stage>.txt  (dynamic per delegation)
//
// FORBIDDEN in [1][2][4]: timestamps, per-call ENV expansions, random IDs,
// retry counters, file mtimes, agent names beyond worktask_id, message IDs.

public enum Preamble {
    // Marker tags — MUST stay byte-identical to cache-lint.sh. Do not paraphrase.
    public static let markContract = "<<<contract-reminder>>>"
    public static let markHeader = "<<<worktask-header>>>"
    public static let markState = "<<<state-json>>>"
    public static let markContractStage = "<<<stage-contract>>>"
    public static let markTask = "<<<task>>>"

    // [1] contract-reminder — byte-identical for EVERY stage of EVERY worktask.
    public static let contractReminder = """
        You are a stage agent inside an igrsoft staged worktask. Binding contract:
        1. Read your required inputs from .context/ (paths per the task metadata).
        2. Produce your stage artifact at the required .context/ path; the first
           block MUST be YAML frontmatter (`---` / `handoff:`) per your stage
           template, and the body MUST use the mandatory kebab-case H2 anchors.
        3. Before returning, patch .context/state.json (read, merge, rewrite —
           preserve all existing keys): set stages.<CODE> completed + append facts
           and the handoff summary.
        4. On unrecoverable failure: append a classified entry to your
           .context/errors/<agent>.md and set verdict blocked/escalate — never
           fabricate results.
        5. Write only files your stage owns. No commit/push unless your contract
           says so. Never print or commit secrets.
        6. Return a concise handoff summary (verdict, key decisions,
           next_stage_focus) as your final message.
        """

    // [4] stage-contract — per-stage-type verbatim excerpt, keyed by stage code.
    // Byte-identical across repeat calls of the same stage.
    public static let stageContract: [String: String] = [
        "PL": "STAGE PL (Planning). Artifact: .context/planning-0.md. "
            + "Anchors: ## requirements, ## acceptance-criteria, ## scope, "
            + "## out-of-scope, ## risks, ## complexity, ## stages. "
            + "Verdict in frontmatter handoff.verdict.",
        "AR": "STAGE AR (Architecture). Artifact: .context/analyzing-0.md. "
            + "Anchors: ## decisions, ## trade-offs, ## patterns, "
            + "## integration-points, ## schemas, ## open-questions, ## risks.",
        "TL": "STAGE TL (Team Lead). Artifact: .context/coordination-0.md. "
            + "Anchors: ## fan-out, ## shared-snippets, ## sequence, ## risks.",
        "DV": "STAGE DV (Development). Artifact: .context/development-0.md. "
            + "Anchors: ## files-changed, ## tests-added, ## deviations, "
            + "## follow-ups. Produce real code changes + a green build.",
        "DR": "STAGE DR (Developer Review). Artifact: .context/developer-review-0.md. "
            + "Anchors: ## findings, ## verdict, ## blockers, ## follow-ups.",
        "SR": "STAGE SR (Security Review). Artifact: .context/security-review-0.md. "
            + "Anchors: ## findings, ## verdict, ## blockers, ## threat-model.",
        "QA": "STAGE QA (Testing). Artifact: .context/testing-0.md. "
            + "Anchors: ## results, ## coverage, ## regressions, ## verdict.",
        "DC": "STAGE DC (Documentation). Artifact: .context/documentation-0.md. "
            + "Anchors: ## files-changed, ## cross-references, ## follow-ups.",
        "RE": "STAGE RE (Release). Artifact: .context/release-0.md. "
            + "Anchors: ## artifacts, ## version, ## rollback-plan.",
        "FN": "STAGE FN (Finalization). Artifact: .context/complete-summary-0.md. "
            + "Anchors: ## summary, ## artifacts, ## followups, ## metrics.",
        "ST": "STAGE ST (Stakeholder). Artifact: .context/retrospective-0.md. "
            + "Anchors: ## decision, ## learnings, ## followups.",
    ]

    /// [2] worktask-header — ONLY the two required literals. No agent name, no
    /// timestamp, no run index. Byte-identical across every stage of one worktask.
    public static func header(worktaskID: String, planFile: String) -> String {
        "worktask_id: \(worktaskID)\nplan_file: \(planFile)"
    }

    /// Strip a single trailing newline (deterministic byte layout regardless of
    /// how the source file was saved) — mirrors Python str.rstrip("\n") which
    /// strips ALL trailing newlines.
    static func rstripNewlines(_ s: String) -> String {
        var t = s
        while t.hasSuffix("\n") { t.removeLast() }
        return t
    }

    /// Assemble one stage's stdin prompt in the binding [1][2][3][4][5] order.
    /// Pure: inputs -> string, no I/O. The cross-stage cacheable prefix is
    /// [1]+[2]; the within-stage prefix is [1]+[2]+[3]+[4].
    public static func assembleStagePrompt(
        _ stage: String,
        worktaskID: String,
        planFile: String,
        stateJSONText: String,
        taskText: String,
        stageContractOverride: String? = nil
    ) -> String {
        let contract = stageContractOverride ?? stageContract[stage] ?? ""
        let stateBody = rstripNewlines(stateJSONText)
        let taskBody = rstripNewlines(taskText)
        return "\(markContract)\n\(contractReminder)\n"
            + "\(markHeader)\n\(header(worktaskID: worktaskID, planFile: planFile))\n"
            + "\(markState)\n\(stateBody)\n"
            + "\(markContractStage)\n\(contract)\n"
            + "\(markTask)\n\(taskBody)\n"
    }
}
