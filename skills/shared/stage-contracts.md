---
name: stage-contracts
description: Per-stage Inputs→Outputs→Validation contract for every workflow stage (PL/AR/TL/DV/DR/SR/QA/DC/RE/FN/ST/IR/ET). Use when authoring stage agents, implementing handoffs, or validating workflow completion.
---

# Stage Contracts Reference

Single source of truth for what each workflow stage consumes, produces, and how the orchestrator validates the handoff. Every stage agent's `## Completion Verification` section MUST link back here.

## How to Read a Contract

- **Inputs**: required `.context/` artifacts and metadata the stage reads before starting. Missing required inputs → `missing_input` escalation (see `agent-coordination` § Error Handling).
- **Outputs**: artifacts the stage MUST produce before setting `status: completed`. Each lists the minimum sections.
- **Validation**: the exact check the orchestrator runs on stage completion. If false, the stage is not considered complete.
- **Error File**: per-agent narrative path (`metadata.error_file`). Auto-derived from `metadata.agent` basename. See `task-system` § Metadata Fields.

## Contract Table

| Stage | Agent | Model | Required Inputs | Required Outputs | Validation | Error File |
|-------|-------|-------|-----------------|------------------|------------|------------|
| **PL** | product-manager | opus | User request; trigger flags | `.context/planning.md` with sections: Goal, Scope, Complexity Score, Stage Plan, Approval Required | `planning.md` exists + Complexity Score int 0–50 + Stage Plan lists downstream task subjects | `.context/errors/product-manager.md` |
| **AR** | software-architector | opus | `.context/planning.md` | `.context/analyzing.md` with sections: Architecture Decisions, Trade-offs, Patterns, Integration Points | `analyzing.md` exists + at least one decision with rationale | `.context/errors/software-architector.md` |
| **TL** | team-lead | sonnet | `.context/planning.md`, `.context/analyzing.md` | `.context/coordination.md` with sections: Task Breakdown, Parallel Streams, Assignments, Risks | `coordination.md` exists + task breakdown maps to DV sub-tasks | `.context/errors/team-lead.md` |
| **DV** | developer | opus | `.context/planning.md`, `.context/analyzing.md`, `.context/coordination.md` (if present) | `.context/development.md` with sections: Files Changed, Approach, Tests Added, Verification Command + actual code changes | `development.md` exists + git diff is non-empty + `.context/logs/build-*.log` shows success | `.context/errors/developer.md` |
| **DR** | technical-lead | sonnet | `.context/development.md` + source diff | `.context/developer-review.md` with sections: Code Quality, Test Coverage, Issues Found, Approval Status | `developer-review.md` exists + Approval Status ∈ {approved, needs-changes, rejected} | `.context/errors/technical-lead.md` |
| **SR** | security-reviewer | opus | `.context/development.md` + source diff | `.context/security-review.md` with sections: Threat Model, Findings, Severity, Remediation | `security-review.md` exists + no High/Critical findings unresolved | `.context/errors/security-reviewer.md` |
| **QA** | qa-engineer | sonnet | `.context/development.md`, `.context/developer-review.md` | `.context/testing.md` with sections: Test Plan, Results, Design Comparison (if UI), Regression Check | `testing.md` exists + `.context/logs/test-*.log` shows pass + no blocking defects | `.context/errors/qa-engineer.md` |
| **DC** | technical-writer | haiku | `.context/development.md`, `.context/analyzing.md` | `.context/documentation.md` with sections: Doc Changes, README Updates, API Docs | `documentation.md` exists + docs diff present | `.context/errors/technical-writer.md` |
| **RE** | release-engineer | haiku | `.context/development.md`, `.context/testing.md`, `.context/documentation.md` | `.context/release-prep.md` with sections: Version Bump, Changelog, Deployment Checklist | `release-prep.md` exists + version bump proposed + changelog entry drafted | `.context/errors/release-engineer.md` |
| **FN** | project-manager | opus | All upstream `.context/*.md` | `.context/complete.md` with sections: Summary, Files Changed, Stage Timings, Next Actions + commit/PR created | `complete.md` exists + commit created OR PR opened | `.context/errors/project-manager.md` |
| **ST** | stakeholder | sonnet | `.context/complete.md` | `.context/approval.md` with sections: Decision, Feedback, Follow-ups | `approval.md` exists + Decision ∈ {approved, rejected, changes-requested} | `.context/errors/stakeholder.md` |
| **IR** | incident-responder | sonnet | User incident report | `.context/incident-report.md` with sections: Required Fix, Constraints, Blast Radius, Verification Command | `incident-report.md` exists + all 4 sections non-empty | `.context/errors/incident-responder.md` |
| **ET** | ethics-reviewer | opus | `.context/planning.md` + high-risk keyword match | `.context/ethics-review.md` with sections: Risk Assessment, Mitigation, Decision | `ethics-review.md` exists + Decision ∈ {pass, block, conditional} | `.context/errors/ethics-reviewer.md` |

## Validation Protocol

The orchestrator runs validation between `TaskUpdate({status: "completed"})` and the next stage's `status: in_progress`:

1. **File check**: Read `metadata.context_files` for next stage — verify every path exists on disk. `metadata.error_file` is always present in `context_files` (orchestrator auto-appends on `TaskCreate`/`TaskUpdate`); treat its absence on disk as "no prior retries" (not a failure).
2. **Section check**: Grep the output artifact for required section headers.
3. **Side-artifact check**: For DV/QA stages, confirm corresponding `.context/logs/` capture exists (build/test logs).
4. **Metadata check**: Validate task `metadata` against `task-system` § JSON Schema.
5. **Error file check**: If `retry_count > 0`, `metadata.error_file` MUST exist on disk AND appear in `context_files`.

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

- `skills/shared/stage-codes.md` — code/agent/model lookup
- `skills/shared/task-system.md` — metadata schema, `error_file` derivation
- `skills/agent-coordination/SKILL.md` § Error Handling — retry/escalate matrix
- `skills/logging-conventions/SKILL.md` — raw capture paths (`.context/logs/`)
- `skills/task-folder-organization/SKILL.md` — artifact naming and retention
