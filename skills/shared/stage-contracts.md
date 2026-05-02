---
name: stage-contracts
description: Per-stage Inputs→Outputs→Validation contract for every workflow stage (PL/AR/TL/DV/DR/SR/QA/DC/RE/FN/ST/IR/ET). Use when authoring stage agents, implementing handoffs, or validating workflow completion.
---

# Stage Contracts Reference

Single source of truth for what each workflow stage consumes, produces, and how the orchestrator validates the handoff. Every stage agent's `## Completion Verification` section MUST link back here.

## How to Read a Contract

- **Inputs**: required `.context/` artifacts and metadata the stage reads before starting. Missing required inputs → `missing_input` escalation (see `agent-coordination` § Error Handling).
- **Outputs**: artifacts the stage MUST produce before setting `status: completed`. Each lists the minimum sections. **Every output artifact MUST start with a `---\nhandoff:\n` YAML frontmatter block** conforming to the schema in `skills/workflow/references/handoff-protocol.md#frontmatter-schema`. Per-stage required fields are defined in that file's per-stage matrix.
- **Validation**: the exact check the orchestrator runs on stage completion. If false, the stage is not considered complete.
- **Error File**: per-agent narrative path (`metadata.error_file`). Auto-derived from `metadata.agent` basename. See `task-system` § Metadata Fields.

## Required Inputs (handoff-protocol)

Every stage agent reads inputs in this order, anchor-first:

1. Read `.context/state.json` (the workflow ledger). Extract `facts.decisions`, `facts.open_questions`, `handoffs`, and `stages` relevant to your stage.
2. Read only the listed anchors in upstream artifacts (e.g. `analyzing.md#decisions`, `planning-0.md#requirements`). Do **not** read whole files unless an anchor is absent.
3. Deep-read a full artifact only on retry (`retry_count > 0`) or when the frontmatter `next_stage_focus` explicitly names a non-anchored section.

**Backward-compatibility fallback**: If `.context/state.json` is absent, fall back to `metadata.context_files` (legacy mode) and read the listed files in full. Log `INFO: state.json not found, legacy mode` and proceed normally.

## Required Outputs (handoff-protocol)

Every stage's output artifact MUST:

1. Start with `---\nhandoff:\n` YAML frontmatter (≤30 lines, ≤200 tokens) matching the per-stage required-field matrix in `skills/workflow/references/handoff-protocol.md#frontmatter-schema`.
2. Use H2 anchors from the per-stage allow-list in `handoff-protocol.md#anchor-allow-list` (kebab-case, no spaces, no underscores).
3. Patch `.context/state.json` atomically (read → merge → temp → fsync → rename per `handoff-protocol.md#atomic-write`) with `stages.<CODE>` (status, artifact, verdict, retry_count) and `handoffs["<PREV>→<CODE>"]` (≤300-char summary ending in `ref:` pointer).

## Contract Table

| Stage | Agent | Model | Required Inputs | Required Outputs | Validation | Error File |
|-------|-------|-------|-----------------|------------------|------------|------------|
| **PL** | product-manager | opus | User request; trigger flags | `.context/<plan_file>` (`planning-N.md` where N = next free integer ≥ 0; see `agents/product-manager.md § Plan File Naming`) with sections: Goal, Scope, Complexity Score, Stage Plan, Approval Required + `.context/designs/figma-registry.md` (if Figma URLs provided) | `<plan_file>` exists + Complexity Score int 0–50 + Stage Plan lists downstream task subjects + `metadata.plan_file = <plan_file>` stamped on every downstream task | `.context/errors/product-manager.md` |
| **AR** | software-architector | opus | `.context/<plan_file>` (resolved via `task.metadata.plan_file`; fallback: newest `.context/planning-*.md`, then legacy `.context/planning.md`) | `.context/analyzing.md` with sections: Architecture Decisions, Trade-offs, Patterns, Integration Points | `analyzing.md` exists + at least one decision with rationale | `.context/errors/software-architector.md` |
| **TL** | team-lead | sonnet | `.context/<plan_file>` (resolved per AR rule), `.context/analyzing.md` | `.context/coordination.md` with sections: Task Breakdown, Parallel Streams, Assignments, Risks | `coordination.md` exists + task breakdown maps to DV sub-tasks | `.context/errors/team-lead.md` |
| **DV** | developer | opus | `.context/<plan_file>` (resolved per AR rule), `.context/analyzing.md`, `.context/coordination.md` (if present) | `.context/development.md` with sections: Files Changed, Approach, Tests Added, Verification Command + actual code changes | `development.md` exists + git diff is non-empty + `.context/logs/build-*.log` shows success | `.context/errors/developer.md` |
| **DR** | technical-lead | sonnet | `.context/development.md` + source diff | `.context/developer-review.md` with sections: Code Quality, Test Coverage, Issues Found, Approval Status | `developer-review.md` exists + Approval Status ∈ {approved, needs-changes, rejected} | `.context/errors/technical-lead.md` |
| **SR** | security-reviewer | opus | `.context/development.md` + source diff | `.context/security-review.md` with sections: Threat Model, Findings, Severity, Remediation | `security-review.md` exists + no High/Critical findings unresolved | `.context/errors/security-reviewer.md` |
| **QA** | qa-engineer | sonnet | `.context/development.md`, `.context/developer-review.md` + `.context/designs/figma-registry.md` (if present; else glob `.context/designs/figma-*.png`) | `.context/testing.md` with sections: Test Plan, Results, Design Comparison (if UI), Regression Check | `testing.md` exists + `.context/logs/test-*.log` shows pass + no blocking defects + if `figma-registry.md` present, `testing.md § Design Comparison` has one row per registry entry | `.context/errors/qa-engineer.md` |
| **DC** | technical-writer | haiku | `.context/development.md`, `.context/analyzing.md` | `.context/documentation.md` with sections: Doc Changes, README Updates, API Docs | `documentation.md` exists + docs diff present | `.context/errors/technical-writer.md` |
| **RE** | release-engineer | haiku | `.context/development.md`, `.context/testing.md`, `.context/documentation.md` | `.context/release-prep.md` with sections: Version Bump, Changelog, Deployment Checklist | `release-prep.md` exists + version bump proposed + changelog entry drafted | `.context/errors/release-engineer.md` |
| **FN** | project-manager | opus | All upstream `.context/*.md` | `.context/complete.md` with sections: Summary, Files Changed, Stage Timings, Next Actions + `.context/attachments/PR instructions.md` + `.context/attachments/Review request.md` (templates per `skills/workflow/references/conductor-attachments.md`) + commit/PR created | `complete.md` exists + both attachments exist + commit created OR PR opened | `.context/errors/project-manager.md` |
| **ST** | stakeholder | sonnet | `.context/complete.md` | `.context/approval.md` with sections: Decision, Feedback, Follow-ups, Self-Improvement + **optional** `.context/learnings.md` (only when in-scope user changes detected — see `skills/self-improvement/SKILL.md`) | `approval.md` exists + Decision ∈ {approved, rejected, changes-requested} + `self-improvement` skill invocation recorded (either `learnings.md` present or log entry `Result: no-changes` in `.context/logs/self-improve-*.log`) | `.context/errors/stakeholder.md` |
| **IR** | incident-responder | sonnet | User incident report | `.context/incident-report.md` with sections: Required Fix, Constraints, Blast Radius, Verification Command | `incident-report.md` exists + all 4 sections non-empty | `.context/errors/incident-responder.md` |
| **ET** | ethics-reviewer | opus | `.context/<plan_file>` (resolved per AR rule) + high-risk keyword match | `.context/ethics-review.md` with sections: Risk Assessment, Mitigation, Decision | `ethics-review.md` exists + Decision ∈ {pass, block, conditional} | `.context/errors/ethics-reviewer.md` |

## Validation Protocol

The orchestrator runs validation between `TaskUpdate({status: "completed"})` and the next stage's `status: in_progress`:

1. **File check**: Read `metadata.context_refs` (anchor-based, preferred) or `metadata.context_files` (legacy fallback) for next stage — verify every referenced file exists on disk. `metadata.error_file` is always present in `context_files` (orchestrator auto-appends on `TaskCreate`/`TaskUpdate`); treat its absence on disk as "no prior retries" (not a failure).
2. **Frontmatter check**: `head -1 <artifact>` MUST equal `---`; `grep -c '^handoff:' <artifact>` MUST equal `1` within the top-of-file block. Missing frontmatter triggers fallback path F3 (orchestrator derives a minimal handoff record).
3. **Anchor lint (DR gate)**: For each produced artifact, verify all H2 headings match the per-stage allow-list in `skills/workflow/references/handoff-protocol.md#anchor-allow-list`. DR runs `cache-lint.sh --anchor-lint <artifact>` as a stage gate. CI runs the same on PRs touching `skills/` or `agents/` as a safety net.
4. **Section check**: Grep the output artifact for required section headers.
5. **Side-artifact check**: For DV/QA stages, confirm corresponding `.context/logs/` capture exists (build/test logs).
6. **Metadata check**: Validate task `metadata` against `task-system` § JSON Schema.
7. **Error file check**: If `retry_count > 0`, `metadata.error_file` MUST exist on disk AND appear in `context_files`.
8. **state.json patch check**: After Task() returns, orchestrator re-reads `.context/state.json`. If `stages.<CODE>.status` is still `in_progress`, parse the artifact's `handoff:` frontmatter and atomic-merge into state.json (third belt-and-suspenders layer; see `handoff-protocol.md#fallback-paths` F2/F3).

Failure at any step → do NOT transition. Append a `missing_input` entry to the *next* stage's error file and block until resolved.

## Cross-Plugin Stages

When a stage is delegated to a qualified agent (e.g., `apple-developer:ios-developer` takes over DV for Apple platform tasks):

- `metadata.agent = "apple-developer:ios-developer"` (full qualified name)
- `metadata.error_file = ".context/errors/ios-developer.md"` (last segment)
- Collision fallback (two plugins with same basename) → `.context/errors/apple-developer-ios-developer.md`
- Output artifact path is unchanged — `.context/development.md` regardless of which plugin implemented DV

## Multi-Run Within a Stage

When TL splits DV into DV0/DV1/DV2 (parallel streams):

- Each sub-task has its own `retry_count`
- All write to the same `.context/errors/developer.md` with distinct section headers (`## DV0 Retry 1 — …`, `## DV1 Retry 1 — …`)
- Output artifact is a single `.context/development.md` — each sub-task appends its "Files Changed" block

## Cross References

- `skills/workflow/references/handoff-protocol.md` — canonical state.json + frontmatter + anchor specs
- `skills/shared/stage-codes.md` — code/agent/model lookup
- `skills/shared/task-system.md` — metadata schema, `error_file` derivation, `context_refs`/`state_file`
- `skills/agent-coordination/SKILL.md` § Error Handling — retry/escalate matrix
- `skills/logging-conventions/SKILL.md` — raw capture paths (`.context/logs/`)
- `skills/task-folder-organization/SKILL.md` — artifact naming and retention
- `skills/self-improvement/SKILL.md` — optional `.context/learnings.md` produced at ST
