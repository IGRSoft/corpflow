#!/usr/bin/env python3
"""benchmark/live/preamble.py — production-faithful stage-prompt assembly (REQ-1).

The live A/B benchmark must exercise the SAME cache-prefix byte layout the
production orchestrator ships, otherwise its per-stage `cache_read` /
`cache_creation` attribution measures the CLI's own session caching rather than
the `[1]+[2]+[4]` prefix reuse we intend to optimize (planning-0.md FINDING-1,
analyzing-0.md#decisions AD-1).

`assemble_stage_prompt()` is a PURE function (inputs -> string, no I/O, stdlib
only). The dispatcher's imperative shell reads `prompts/<stage>.txt` (section
[5], the dynamic task text) and the workdir's `.context/state.json` (section
[3]) and passes them here. This module is imported ONLY from `dispatch.py`,
which is itself reached ONLY on `--live` — the AC-8 deterministic tripwire
(test_live_gate.py) stays intact because nothing in the deterministic path
imports `benchmark/live/`.

Layout (binding — skills/worktask/references/handoff-protocol.md#cache-prefix,
skills/worktask/SKILL.md "Cache-Friendly Prompt Layout"):

    [1] <<<contract-reminder>>>  CONTRACT_REMINDER   (byte-stable ALL stages)
    [2] <<<worktask-header>>>    worktask_id/plan     (byte-stable ALL stages)
    [3] <<<state-json>>>         inlined state.json   (evolves per stage)
    [4] <<<stage-contract>>>     STAGE_CONTRACT[code] (byte-stable WITHIN stage)
    [5] <<<task>>>               prompts/<stage>.txt  (dynamic per delegation)

Marker literals match cache-lint.sh:191-194 EXACTLY so a captured live
prompt-log can be linted by the same `prefix_lint` that guards production.

FORBIDDEN in [1][2][4] (handoff-protocol.md#cache-prefix:614-624): timestamps,
per-call ENV expansions, random IDs, retry counters, file mtimes, agent names
beyond worktask_id, message IDs. Everything here is a static literal or one of
the two required [2] literals (worktask_id, plan_file). cache-lint's new L1
forbidden-token scanner (Batch 3) enforces this over a captured prompt-log.
"""

from __future__ import annotations

# Marker tags — MUST stay byte-identical to cache-lint.sh:191-194 and to the
# coordination-0.md#shared-snippets list. Do not paraphrase.
MARK_CONTRACT = "<<<contract-reminder>>>"
MARK_HEADER = "<<<worktask-header>>>"
MARK_STATE = "<<<state-json>>>"
MARK_CONTRACT_STAGE = "<<<stage-contract>>>"
MARK_TASK = "<<<task>>>"

# ---------------------------------------------------------------------------
# [1] contract-reminder — a module-level constant literal. NO timestamp / ENV /
# ID / agent-name. Byte-identical for EVERY stage of EVERY worktask.
# ---------------------------------------------------------------------------
CONTRACT_REMINDER = (
    "You are a stage agent inside an igrsoft staged worktask. Binding contract:\n"
    "1. Read your required inputs from .context/ (paths per the task metadata).\n"
    "2. Produce your stage artifact at the required .context/ path; the first\n"
    "   block MUST be YAML frontmatter (`---` / `handoff:`) per your stage\n"
    "   template, and the body MUST use the mandatory kebab-case H2 anchors.\n"
    "3. Before returning, patch .context/state.json (read, merge, rewrite —\n"
    "   preserve all existing keys): set stages.<CODE> completed + append facts\n"
    "   and the handoff summary.\n"
    "4. On unrecoverable failure: append a classified entry to your\n"
    "   .context/errors/<agent>.md and set verdict blocked/escalate — never\n"
    "   fabricate results.\n"
    "5. Write only files your stage owns. No commit/push unless your contract\n"
    "   says so. Never print or commit secrets.\n"
    "6. Return a concise handoff summary (verdict, key decisions,\n"
    "   next_stage_focus) as your final message."
)

# ---------------------------------------------------------------------------
# [4] stage-contract — per-stage-type verbatim excerpt, keyed by stage code.
# Byte-identical across repeat calls of the same stage. A fixed constant map
# (no I/O in the hot path) mirrors skills/shared/stage-contracts.md intent for
# the benchmark workload; each entry names the artifact + mandatory anchors.
# ---------------------------------------------------------------------------
STAGE_CONTRACT: dict[str, str] = {
    "PL": (
        "STAGE PL (Planning). Artifact: .context/planning-0.md. "
        "Anchors: ## requirements, ## acceptance-criteria, ## scope, "
        "## out-of-scope, ## risks, ## complexity, ## stages. "
        "Verdict in frontmatter handoff.verdict."
    ),
    "AR": (
        "STAGE AR (Architecture). Artifact: .context/analyzing-0.md. "
        "Anchors: ## decisions, ## trade-offs, ## patterns, "
        "## integration-points, ## schemas, ## open-questions, ## risks."
    ),
    "TL": (
        "STAGE TL (Team Lead). Artifact: .context/coordination-0.md. "
        "Anchors: ## fan-out, ## shared-snippets, ## sequence, ## risks."
    ),
    "DV": (
        "STAGE DV (Development). Artifact: .context/development-0.md. "
        "Anchors: ## files-changed, ## tests-added, ## deviations, "
        "## follow-ups. Produce real code changes + a green build."
    ),
    "DR": (
        "STAGE DR (Developer Review). Artifact: .context/developer-review-0.md. "
        "Anchors: ## findings, ## verdict, ## blockers, ## follow-ups."
    ),
    "SR": (
        "STAGE SR (Security Review). Artifact: .context/security-review-0.md. "
        "Anchors: ## findings, ## verdict, ## blockers, ## threat-model."
    ),
    "QA": (
        "STAGE QA (Testing). Artifact: .context/testing-0.md. "
        "Anchors: ## results, ## coverage, ## regressions, ## verdict."
    ),
    "DC": (
        "STAGE DC (Documentation). Artifact: .context/documentation-0.md. "
        "Anchors: ## files-changed, ## cross-references, ## follow-ups."
    ),
    "RE": (
        "STAGE RE (Release). Artifact: .context/release-0.md. "
        "Anchors: ## artifacts, ## version, ## rollback-plan."
    ),
    "FN": (
        "STAGE FN (Finalization). Artifact: .context/complete-summary-0.md. "
        "Anchors: ## summary, ## artifacts, ## followups, ## metrics."
    ),
    "ST": (
        "STAGE ST (Stakeholder). Artifact: .context/retrospective-0.md. "
        "Anchors: ## decision, ## learnings, ## followups."
    ),
}


def header(worktask_id: str, plan_file: str) -> str:
    """[2] worktask-header — ONLY the two required literals (worktask_id,
    plan_file). No agent name, no timestamp, no run index. Byte-identical across
    every stage of one worktask (handoff-protocol.md#cache-prefix:626-631)."""
    return f"worktask_id: {worktask_id}\nplan_file: {plan_file}"


def assemble_stage_prompt(
    stage: str,
    *,
    worktask_id: str,
    plan_file: str,
    state_json_text: str,
    task_text: str,
    stage_contract: str | None = None,
) -> str:
    """Assemble one stage's stdin prompt in the binding [1][2][3][4][5] order.

    Pure: inputs -> string, no I/O. `stage_contract` defaults to
    STAGE_CONTRACT[stage]; callers may inject a custom [4] for testing. The
    cross-stage cacheable prefix is [1]+[2]; the within-stage prefix is
    [1]+[2]+[3]+[4]. Section [3] (state.json) is the ONLY block that legitimately
    varies per stage, placed AFTER [1][2] and BEFORE [4] exactly as production.
    """
    if stage_contract is None:
        stage_contract = STAGE_CONTRACT.get(stage, "")
    # Strip a single trailing newline from injected bodies so the assembled
    # byte layout is deterministic regardless of how the source file was saved.
    state_body = state_json_text.rstrip("\n")
    task_body = task_text.rstrip("\n")
    return (
        f"{MARK_CONTRACT}\n{CONTRACT_REMINDER}\n"
        f"{MARK_HEADER}\n{header(worktask_id, plan_file)}\n"
        f"{MARK_STATE}\n{state_body}\n"
        f"{MARK_CONTRACT_STAGE}\n{stage_contract}\n"
        f"{MARK_TASK}\n{task_body}\n"
    )
