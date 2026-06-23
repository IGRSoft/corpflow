---
name: stage-contracts
description: Per-stage Inputs→Outputs→Validation contract for every worktask stage (PL/AR/TL/DV/DR/SR/QA/DC/RE/FN/ST/IR/ET). Use when authoring stage agents, implementing handoffs, or validating worktask completion.
---

# Stage Contracts Reference

Single source of truth for what each stage consumes, produces, and how the orchestrator validates the handoff. Every stage agent's `## Completion Verification` section MUST link back here.

## How to Read a Contract

- **Inputs**: `.context/` artifacts and metadata read before starting. Missing → `missing_input` escalation (see `agent-coordination` § Error Handling).
- **Outputs**: artifacts produced before `status: completed`, each with minimum sections. **Every output MUST start with a `---\nhandoff:\n` YAML frontmatter block** per `skills/worktask/references/handoff-protocol.md#frontmatter-schema` (required fields in that file's per-stage matrix).
- **Validation**: the exact check the orchestrator runs on completion. If false, the stage is not complete.
- **Error File**: per-agent narrative path (`metadata.error_file`), auto-derived from `metadata.agent` basename. See `task-system` § Metadata Fields.

## Required Inputs (handoff-protocol)

Every stage agent reads inputs in this order, anchor-first:

1. Read `.context/state.json` (the worktask ledger). Extract `facts.decisions`, `facts.open_questions`, `handoffs`, `run_index`, and `stages` relevant to your stage.
2. Resolve `N = task.metadata.run_index ?? state.run_index ?? 0`. All stage artifacts for this run use `<basename>-${N}.md`.
3. Read only the listed anchors in upstream artifacts (e.g. `analyzing-N.md#decisions`, `planning-N.md#requirements`). Do **not** read whole files unless an anchor is absent.
4. Deep-read a full artifact only on retry (`retry_count > 0`) or when the frontmatter `next_stage_focus` explicitly names a non-anchored section.

**Run Index Resolution** (two-step resolver — see `agents/product-manager.md § Stage Artifact Naming`):
1. `task.metadata.run_index` → `<basename>-${N}.md`.
2. Newest glob `<basename>-*.md` (highest N) when metadata is absent.

**Backward-compatibility fallback (F1)**: If `.context/state.json` is absent, fall back to `metadata.context_files` (legacy mode), reading the listed files in full. Rationale and full F1 description: `skills/shared/legacy-fallback-f1.md`.

To surface F1 entries, agents MUST emit one telemetry line:

```bash
mkdir -p .context/logs
N="${run_index:-0}"
printf '%s\t%s\t%s\t%s\n' \
  "$(date -u +%FT%TZ)" \
  "${metadata_agent:-unknown}" \
  "F1" \
  "state.json absent; using metadata.context_files" \
  >> ".context/logs/fallback-${N}.log"
```

Then proceed with the legacy read. The fallback log is consumed by `/cost-report` to flag worktasks that lost cache hits silently.

> Agents MUST NOT restate this F1 telemetry snippet, the run-index resolver, or the atomic-write pseudocode in their own files — link to `#f1-telemetry`, `#run-index-resolution`, or `handoff-protocol.md#atomic-write` instead. Drift checker: `cache-lint.sh --frontmatter-template-lint`.

### #run-index-resolution

Two-step resolver (canonical), as in **Run Index Resolution** above: (1) `task.metadata.run_index` → `<basename>-${N}.md`; (2) newest glob `<basename>-*.md` (highest N) when metadata is absent.

### #f1-telemetry

See the F1 paragraph and bash snippet immediately above. Cross-references: `handoff-protocol.md#fallback-paths` (F1..F4 matrix), `/cost-report § Cache Performance` (operator surface).

## Required Outputs (handoff-protocol)

Every stage's output artifact MUST:

1. Start with `---\nhandoff:\n` YAML frontmatter (≤30 lines, ≤200 tokens) matching the per-stage required-field matrix in `skills/worktask/references/handoff-protocol.md#frontmatter-schema`.
2. Use H2 anchors from the per-stage allow-list in `handoff-protocol.md#anchor-allow-list` (kebab-case, no spaces, no underscores).
3. Patch `.context/state.json` atomically (read → merge → temp → fsync → rename per `handoff-protocol.md#atomic-write`) with `stages.<CODE>` (status, artifact, verdict, retry_count) and `handoffs["<PREV>→<CODE>"]` (≤300-char summary ending in `ref:` pointer).

## Contract Table

All artifact paths use `<basename>-N.md` (`N = task.metadata.run_index`; resolver in **Run Index Resolution** above).

| Stage | Agent | Model | Required Inputs | Required Outputs | Validation | Error File |
|-------|-------|-------|-----------------|------------------|------------|------------|
| **PL** | product-manager | opus | User request; trigger flags | `.context/<plan_file>` (`planning-N.md` where N = next free integer ≥ 0; see `agents/product-manager.md § Plan File & Run Index Naming`) with sections: Goal, Scope, Complexity Score, Stage Plan, Approval Required + `.context/designs/figma-registry.md` (if Figma URLs provided) | `<plan_file>` exists + Complexity Score int 0–50 + Stage Plan lists downstream task subjects + `metadata.plan_file = <plan_file>` AND `metadata.run_index = N` stamped on every downstream task | `.context/errors/product-manager.md` |
| **AR** | software-architector | opus | `.context/<plan_file>` (resolved via `task.metadata.plan_file`; fallback: newest `.context/planning-*.md`) | `.context/analyzing-N.md` with sections: Architecture Decisions, Trade-offs, Patterns, Integration Points | `analyzing-N.md` exists + at least one decision with rationale | `.context/errors/software-architector.md` |
| **TL** | team-lead | sonnet | `.context/<plan_file>` (resolved per AR rule), `.context/analyzing-N.md` | `.context/coordination-N.md` with sections: Task Breakdown, Parallel Streams, Assignments, Risks | `coordination-N.md` exists + task breakdown maps to DV sub-tasks | `.context/errors/team-lead.md` |
| **DV** | developer | opus | `.context/<plan_file>` (resolved per AR rule), `.context/analyzing-N.md`, `.context/coordination-N.md` (if present) | `.context/development-N.md` with sections: Files Changed, Approach, Tests Added, Verification Command + actual code changes | `development-N.md` exists + git diff is non-empty + `.context/logs/build-*.log` shows success | `.context/errors/developer.md` |
| **DR** | technical-lead | sonnet | `.context/development-N.md` + source diff | `.context/developer-review-N.md` with sections: Code Quality, Test Coverage, Issues Found, Approval Status | `developer-review-N.md` exists + Approval Status ∈ {approved, needs-changes, rejected} | `.context/errors/technical-lead.md` |
| **SR** | security-reviewer | fable | `.context/development-N.md` + source diff | `.context/security-review-N.md` with sections: Threat Model, Findings, Severity, Remediation | `security-review-N.md` exists + no High/Critical findings unresolved | `.context/errors/security-reviewer.md` |
| **QA** | qa-engineer | sonnet | `.context/development-N.md`, `.context/developer-review-N.md` + `.context/designs/figma-registry.md` (if present; else glob `.context/designs/figma-*.png`) | `.context/testing-N.md` with sections: Test Plan, Results, Design Comparison (if UI), Regression Check | `testing-N.md` exists + `.context/logs/test-*.log` shows pass + no blocking defects + if `figma-registry.md` present, `testing-N.md § Design Comparison` has one row per registry entry | `.context/errors/qa-engineer.md` |
| **DC** | technical-writer | haiku | `.context/development-N.md`, `.context/analyzing-N.md` | `.context/documentation-N.md` with sections: Doc Changes, README Updates, API Docs | `documentation-N.md` exists + docs diff present | `.context/errors/technical-writer.md` |
| **RE** | release-engineer | haiku | `.context/development-N.md`, `.context/testing-N.md`, `.context/documentation-N.md` | `.context/release-N.md` with sections: Version Bump, Changelog, Deployment Checklist | `release-N.md` exists + version bump proposed + changelog entry drafted | `.context/errors/release-engineer.md` |
| **FN** | project-manager | opus | All upstream `.context/*-N.md` | `.context/complete-summary-N.md` with sections: Summary, Files Changed, Stage Timings, Next Actions + `.context/attachments/PR instructions.md` + `.context/attachments/Review request.md` (templates per `skills/worktask/references/conductor-attachments.md`) + commit/PR created | `complete-summary-N.md` exists + both attachments exist + commit created OR PR opened | `.context/errors/project-manager.md` |
| **ST** | stakeholder | sonnet | `.context/complete-summary-N.md` | `.context/retrospective-N.md` with sections: Decision, Feedback, Follow-ups, Self-Improvement + **optional** `.context/learnings.md` (only when in-scope user changes detected — see `skills/self-improvement/SKILL.md`) | `retrospective-N.md` exists + Decision ∈ {approved, rejected, changes-requested} + `self-improvement` skill invocation recorded (either `learnings.md` present or log entry `Result: no-changes` in `.context/logs/self-improve-*.log`) | `.context/errors/stakeholder.md` |
| **IR** | incident-responder | sonnet | User incident report | `.context/incident-N.md` with sections: Required Fix, Constraints, Blast Radius, Verification Command | `incident-N.md` exists + all 4 sections non-empty | `.context/errors/incident-responder.md` |
| **ET** | ethics-reviewer | fable | `.context/<plan_file>` (resolved per AR rule) + high-risk keyword match | `.context/ethics-review-N.md` with sections: Risk Assessment, Mitigation, Decision | `ethics-review-N.md` exists + Decision ∈ {pass, block, conditional} | `.context/errors/ethics-reviewer.md` |

## Validation Protocol

The orchestrator runs validation between `TaskUpdate({status: "completed"})` and the next stage's `status: in_progress`:

1. **File check**: Read `metadata.context_refs` (anchor-based, preferred) or `metadata.context_files` (legacy fallback) for next stage — verify every referenced file exists on disk. `metadata.error_file` is always present in `context_files` (orchestrator auto-appends on `TaskCreate`/`TaskUpdate`); treat its absence on disk as "no prior retries" (not a failure).
2. **Frontmatter / typed-return check**: When the stage's `Task()` dispatch returned a **valid typed object** (the orchestrator passed the stage `schema` from `handoff-protocol.md#handoff-schemas` and the runtime honored it), that typed return **SUPERSEDES** this step — the verdict and facts are taken from the validated object and mapped via `handoff-protocol.md#schema-to-state-map`; the `head -1`/`grep -c '^handoff:'` grep is skipped (its only job — recovering the verdict from prose — is already done structurally). When **no** typed return is present (the runtime dispatch primitive does not accept a `schema` argument, or the stage returned no typed object), this grep is the path: `head -1 <artifact>` MUST equal `---`; `grep -c '^handoff:' <artifact>` MUST equal `1` within the top-of-file block. Missing frontmatter triggers fallback path F3 (orchestrator derives a minimal handoff record). The `.context/<artifact>-N.md` + `handoff:` frontmatter is written by the agent in BOTH cases — it remains the on-disk durability/compression form and the F4 regeneration source, never replaced by the typed return.
3. **Anchor lint (DR gate)**: For each produced artifact, verify all H2 headings match the per-stage allow-list in `skills/worktask/references/handoff-protocol.md#anchor-allow-list`. DR runs `cache-lint.sh --anchor-lint <artifact>` as a stage gate. CI runs the same on PRs touching `skills/` or `agents/` as a safety net.
4. **Section check**: Grep the output artifact for required section headers.
5. **Side-artifact check**: For DV/QA stages, confirm corresponding `.context/logs/` capture exists (build/test logs).
6. **Metadata check**: Validate task `metadata` against `task-system` § JSON Schema.
7. **Error file check**: If `retry_count > 0`, `metadata.error_file` MUST exist on disk AND appear in `context_files`. If `metadata.error_file` is set but the path does NOT exist on disk (e.g. orchestrator stamped the path but no agent has appended yet), treat the situation as `retry_count = 0` (no prior retries) — do NOT fail validation. The file is created lazily by the first appending agent (mkdir -p its parent, then append the retry block).
8. **state.json patch check**: After Task() returns, orchestrator re-reads `.context/state.json`. If `stages.<CODE>.status` is still `in_progress`, parse the artifact's `handoff:` frontmatter and atomic-merge into state.json (third belt-and-suspenders layer; see `handoff-protocol.md#fallback-paths` F2/F3).

Failure at any step → do NOT transition. Append a `missing_input` entry to the *next* stage's error file and block until resolved.

## Cross-Plugin Stages

When a stage is delegated to a qualified agent (e.g., `apple-developer:ios-developer` takes over DV):

- `metadata.agent = "apple-developer:ios-developer"` (full qualified name)
- `metadata.error_file = ".context/errors/ios-developer.md"` (last segment)
- Collision fallback (two plugins with same basename) → `.context/errors/apple-developer-ios-developer.md`
- Output artifact path is unchanged — `.context/development-N.md` regardless of which plugin implemented DV

## Multi-Run Within a Stage

When TL splits DV into DV0/DV1/DV2 (parallel streams):

- Each sub-task has its own `retry_count`
- All write to the same `.context/errors/developer.md` with distinct section headers (`## DV0 Retry 1 — …`, `## DV1 Retry 1 — …`)
- Output artifact is a single `.context/development-N.md` — each sub-task appends its "Files Changed" block

## Per-Stage Frontmatter Templates

Canonical YAML templates for the `handoff:` block atop every stage artifact. Each agent's `## Handoff Protocol` pastes the matching block verbatim (with substitutions) into `.context/<artifact>-N.md` (N resolved per `#run-index-resolution`). These are the single source of truth — agents MUST NOT diverge from the field shape below. To change a template, edit here, then re-run `cache-lint.sh --frontmatter-template-lint agents/*.md` to revalidate every agent's inline copy.

> **Typed-return equivalent.** Each frontmatter template below has a typed-return JSON-Schema counterpart
> (`<CODE>Handoff`) in `skills/worktask/references/handoff-protocol.md#handoff-schemas`. When the runtime
> dispatch primitive accepts a `schema` argument, a stage returns that typed object as a *parallel,
> validated* channel — and the orchestrator maps it onto `state.json` via
> `handoff-protocol.md#schema-to-state-map`. The two channels share one verdict vocabulary per stage
> (`handoff-protocol.md#frontmatter-schema § Per-stage required-field matrix`). The on-disk `handoff:`
> frontmatter below is STILL written either way — it is the cache-friendly on-disk compression form and the
> F4 regeneration source. See **Validation Protocol** step 2 for how a present typed return supersedes
> the frontmatter grep.

### #tpl-pl — Planning (product-manager)

```yaml
---
handoff:
  stage: PL
  verdict: ok                  # ok / blocked / escalate
  summary: "<one-line summary ≤200 chars>"
  key_decisions:
    - { id: pd1, summary: "<decision>", anchor: "planning-N.md#scope" }
  next_stage_focus: "<imperative: what AR must grep/design>"
  open_questions:
    - "q1: <question text> (AR to decide)"
  refs:
    spec: .context/attachments/<spec-file>
    plan: .context/planning-N.md#requirements
---
```

Prev→this label: `USER→PL`.

### #tpl-ar — Architecture (software-architector)

```yaml
---
handoff:
  stage: AR
  verdict: ok                  # ok / blocked / escalate
  summary: "<one-line summary ≤200 chars>"
  key_decisions:
    - { id: ad1, summary: "<decision>", anchor: "analyzing-N.md#decisions" }
  next_stage_focus: "<imperative: what TL must fan-out>"
  open_questions:
    - "q3: <question text> (TL to decide)"
  refs:
    plan: .context/planning-N.md#requirements
    decisions: analyzing-N.md#decisions
---
```

Prev→this label: `PL→AR`. Skip-exploration short-circuit applies — see `agent-coordination/SKILL.md § Orchestrator → PL0 Handoff`.

### #tpl-tl — Team Lead (team-lead)

```yaml
---
handoff:
  stage: TL
  verdict: ok                  # ok / blocked / escalate
  summary: "<one-line coordination summary ≤200 chars>"
  next_stage_focus: "<imperative: DV batch order + parallelization>"
  refs:
    plan: .context/planning-N.md#requirements
    arch: .context/analyzing-N.md#decisions
    fan_out: coordination-N.md#fan-out
---
```

Prev→this label: `AR→TL`. Skip-exploration short-circuit applies.

### #tpl-dv — Development (developer)

```yaml
---
handoff:
  stage: DV
  verdict: ok                  # ok / blocked / escalate
  summary: "<N files modified, M tests added>"
  files_touched:
    - path/to/file1.md
    - path/to/file2.md
  next_stage_focus: "<imperative: what DR/QA must focus on>"
  refs:
    decisions: analyzing-N.md#decisions
    coordination: coordination-N.md#fan-out
    tests: development-N.md#tests-added
---
```

Prev→this label: `TL→DV`.

### #tpl-dr — Developer Review (technical-lead)

```yaml
---
handoff:
  stage: DR
  verdict: pass                # pass / fail
  summary: "<N files reviewed. M findings, all addressed / K blockers remain>"
  key_decisions:
    - { id: dr1, summary: "<finding or approval>", anchor: "developer-review-N.md#findings" }
  refs:
    dev: development-N.md#files-changed
    findings: developer-review-N.md#findings
---
```

Prev→this label: `DV→DR`.

### #tpl-sr — Security Review (security-reviewer)

```yaml
---
handoff:
  stage: SR
  verdict: pass                # pass / fail
  summary: "<N files reviewed. M security findings>"
  key_decisions:
    - { id: sr1, summary: "<security finding>", anchor: "security-review-N.md#findings" }
  refs:
    dev: development-N.md#files-changed
    findings: security-review-N.md#findings
---
```

Prev→this label: `DR→SR`.

### #tpl-qa — QA (qa-engineer)

```yaml
---
handoff:
  stage: QA
  verdict: go                  # go / no-go
  summary: "<N unit tests pass, M integration checks. Coverage X%>"
  files_touched:
    - tests/added/test-file.sh
  key_decisions:
    - { id: qa1, summary: "Coverage X%, target met", anchor: "testing-N.md#coverage" }
  refs:
    dev: development-N.md#files-changed
    results: testing-N.md#results
---
```

Prev→this label: `DR→QA` (or `SR→QA` when SR runs).

### #tpl-dc — Documentation (technical-writer)

```yaml
---
handoff:
  stage: DC
  verdict: ok                  # ok / blocked / escalate
  summary: "Updated N documentation files. Cross-references added."
  files_touched:
    - docs/file1.md
  refs:
    dev: development-N.md#files-changed
    docs: documentation-N.md#files-changed
---
```

Prev→this label: `QA→DC`.

### #tpl-re — Release Engineering (release-engineer)

```yaml
---
handoff:
  stage: RE
  verdict: ok                  # ok / blocked
  summary: "Release artifacts prepared. Version bumped to X.Y.Z"
  files_touched:
    - plugin.json
    - MEMORY.md
  key_decisions:
    - { id: re1, summary: "Version X.Y.Z", anchor: "release-N.md#version" }
  refs:
    artifacts: release-N.md#artifacts
    version: release-N.md#version
---
```

Prev→this label: `DC→RE`.

### #tpl-fn — Finalization (project-manager)

```yaml
---
handoff:
  stage: FN
  verdict: ok                  # ok / blocked
  summary: "All artifacts aggregated. complete-summary-N.md ready for ST approval."
  files_touched:
    - .context/complete-summary-N.md
  next_stage_focus: "ST approves merge and confirms MEMORY.md version bump"
  refs:
    summary: .context/complete-summary-N.md
    ledger: .context/state.json
---
```

Prev→this label: `RE→FN` (or `DC→FN` when RE is absent).

### #tpl-st — Stakeholder (stakeholder)

```yaml
---
handoff:
  stage: ST
  verdict: approve             # approve / reject
  summary: "Approved. <N follow-ups filed or 'No follow-ups'>."
  key_decisions:
    - { id: st1, summary: "Approve merge", anchor: "complete-summary-N.md#decision" }
  refs:
    summary: .context/complete-summary-N.md
---
```

Prev→this label: `FN→ST`.

### #tpl-ir — Incident Response (incident-responder)

```yaml
---
handoff:
  stage: IR
  verdict: ok                  # ok / escalate
  summary: "Root cause: <X>. Fix plan: <Y>. Blast radius: <Z>"
  key_decisions:
    - { id: ir1, summary: "Root cause identified", anchor: "incident-N.md#root-cause" }
  next_stage_focus: "DV implements fix; QA runs regression"
  refs:
    root_cause: incident-N.md#root-cause
    fix_plan: incident-N.md#fix-plan
---
```

Prev→this label: `USER→IR`.

### #tpl-et — Ethics Review (ethics-reviewer)

```yaml
---
handoff:
  stage: ET
  verdict: pass                # pass / fail (block/conditional → fail with key_decisions)
  summary: "Ethics review complete. Score: <X>/100. Status: <APPROVED|CONDITIONS|BLOCKED>."
  key_decisions:
    - { id: et1, summary: "Compliance verdict", anchor: "ethics-review-N.md#findings" }
  next_stage_focus: "Invoking stage resumes after ET verdict"
  refs:
    review: .context/ethics-review-N.md
    ledger: .context/state.json
---
```

Prev→this label: `<invoker>→ET` (whichever stage triggered the ethics gate).

## Completion Verification — REQUIRED before return

Single source of truth for what every stage agent verifies before `status: completed`. Each agent's `## Handoff Protocol` MUST reference this checklist, not restate it. **Agents MUST repeat the numbered step outcomes verbatim in their return summary.** Execute in order:

1. **Artifact frontmatter**: Your artifact (`.context/<artifact>-N.md`) MUST start with `---\nhandoff:` YAML frontmatter conforming to the per-stage template at `stage-contracts.md#tpl-<CODE>`.
2. **Required fields**: Frontmatter MUST include all required fields for your stage `<CODE>` per `skills/worktask/references/handoff-protocol.md#frontmatter-schema` § Per-stage required-field matrix.
3. **Artifact filename**: Artifact MUST use the canonical name from `handoff-protocol.md#stage-artifact-map`. Non-canonical names (e.g. `architecture-0.md` instead of `analyzing-0.md`) break the SubagentStop safety net.
4. **Patch state.json**: `.context/state.json` MUST be patched with `stages.<CODE>` (`status`, `artifact`, `verdict`, `retry_count`) and `handoffs["<PREV>→<CODE>"]` (≤300-char summary ending with `ref:` pointer). `<PREV>→<CODE>` is documented in the template's footer (e.g. `PL→AR`, `USER→IR`).
5. **Atomic write**: Use `handoff-protocol.md#atomic-write` (read → merge → temp → `sync` → `mv -f`). NEVER write `.context/state.json` directly.

```bash
# Inline atomic-merge — run BEFORE returning (steps 4+5 combined)
_sf=".context/state.json"
_tmp="${_sf}.tmp.$$"
jq --arg code "<CODE>" --arg artifact "<artifact>-N.md" --arg verdict "<pass|fail>" \
   --arg prev_code "<PREV>" --arg summary "<≤300-char summary> ref:<artifact>" \
   '.stages[$code] += {status:"completed", artifact:$artifact, verdict:$verdict} |
    .handoffs[($prev_code + "→" + $code)] = $summary' \
   "$_sf" > "$_tmp" && sync "$_tmp" && mv -f "$_tmp" "$_sf"
```

The orchestrator verifies `stages.<CODE>.status == "completed"` after the task returns. If still `in_progress`, the SubagentStop hook (`state-merge.sh`) repairs the ledger from the artifact's frontmatter (F2 fallback). If the artifact itself lacks frontmatter, the orchestrator derives a minimal handoff record from the agent's return text (F3) — but downstream cache hits collapse, so producing valid frontmatter is mandatory in steady state.

## Cross References

- `skills/worktask/references/handoff-protocol.md` — canonical state.json + frontmatter + anchor specs
- `skills/shared/stage-codes.md` — code/agent/model lookup
- `skills/shared/task-system.md` — metadata schema, `error_file` derivation, `context_refs`/`state_file`
- `skills/agent-coordination/SKILL.md` § Error Handling — retry/escalate matrix
- `skills/logging-conventions/SKILL.md` — raw capture paths (`.context/logs/`)
- `skills/task-folder-organization/SKILL.md` — artifact naming and retention
- `skills/self-improvement/SKILL.md` — optional `.context/learnings.md` produced at ST
