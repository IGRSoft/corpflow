<!--
TEMPLATE. Copy to the root of an integrating plugin as CORPFLOW.md and replace every
<PLACEHOLDER>. Normative contract: corpflow skills/cross-plugin-handoff/references/plugin-contract.md.

Keep it self-contained: a user can delete it and have a plugin with no corpflow coupling left, or add
it and have one. Splitting it into a directory of references rebuilds the diffuse coupling it
replaced.
-->

# corpflow Integration — <PLUGIN>

This is the **only** file in <PLUGIN> that knows corpflow exists. Delete it and the plugin is
standalone with no other edit; restore it and the plugin participates in worktasks again. Nothing in
`agents/`, `commands/`, `skills/`, or `hooks/` may reference corpflow — see § Keeping the seam single.

corpflow injects `Read CORPFLOW.md and follow it` into every delegation prompt, so agents reach this
file without a preamble of their own.

## Are we in a worktask?

`.context/state.json` exists → yes; otherwise every rule below is inert and <PLUGIN> behaves as it
does with corpflow uninstalled. Read that file first — it carries the current stage, `run_index`, the
plan file path, and `metadata.*` for the dispatched task.

## Pipeline

Eleven stages, PL→AR→TL→DV→DR→SR→QA→DC→RE→FN→ST. PL0 sizes the run and may drop AR, TL, and DC on
small tasks, so **never assume a stage ran** — read `state.json` instead of inferring. The emergency
pipeline is six stages (IR→DV→QA→DC→FN→ST) and skips both approval gates.

### Stages owned by <PLUGIN>

<PLUGIN> owns these stages when dispatched:

| Stage | <PLUGIN> agent | Handoff data |
|---|---|---|
| AR (Architecture) | `<architect-agent>` | planning context + platform constraints — **consultation only**, corpflow retains the stage |
| DV (Development) | `<router-agent>`, `<specialist-agents>` | planning + architecture context |
| DR (Developer Review) | `<code-fixer-agent>` | `metadata.gate_blockers[]` + minimal-diff remediation |
| SR (Security) | `<security-auditor-agent>` | development context + <PLATFORM> security checklist |
| QA (Quality) | `<test-generator-agent>` | development context + test requirements |
| DV-support | `<support-agents>` | scoped findings returned to the parent DV agent, which owns the artifact |

**DV-support agents do not own a stage.** They return a compressed summary to the parent DV agent and
do **not** patch `state.json`.

## Evidence declaration

| Field | Value |
|---|---|
| `requires_screenshots` default | `<true\|false>` |
| Build Evidence adapter | `<adapter>` |
| Error file | `.context/errors/<agent-basename>.md` |

<EVIDENCE-NOTES: what counts as Build Evidence on this platform, and what does not. For UI platforms,
state that statically produced renders do not satisfy DV exit when `metadata.ui_visual_check: true`.>

## Artifacts

Write to `.context/`. Nothing else in the repository is yours to create.

| Stage | Artifact |
|---|---|
| AR | `.context/<platform>-architecture.md` (consultation output, ≤500-token return summary) |
| DV | `.context/development-<N>.md` |
| DR | `.context/developer-review-<N>.md` |
| SR | `.context/security-review-<N>.md` |
| QA | `.context/qa-<N>.md` |
| IR | `.context/incident-report.md` |

`<N>` is `run_index` from `state.json`; basenames are canonical, only the suffix changes per run.
Filenames are a backward-compat convenience for corpflow's `SubagentStop` hook — **the frontmatter
below is the actual contract**, and an artifact without it breaks the three-layer recovery net
(agent → orchestrator fallback → hook) whatever it is called.

Error narratives go to `.context/errors/<agent-basename>.md` — the agent file's basename, not the
qualified id.

## Handoff frontmatter (BINDING)

Emit this on every stage artifact, **unconditionally**, even on failure:

```yaml
---
handoff:
  from: "<plugin>:<agent>"
  to: "corpflow:<next-stage-agent>"
  stage: "<STAGE-CODE>"
  run_index: <N>
  status: "completed" | "blocked" | "partial"
  verdict: "pass" | "fail" | "needs_changes"
  artifacts: [".context/<artifact>.md"]
  metadata:
    <per-stage required fields — see the matrix below>
---
```

Per-stage required `metadata.*`:

| Stage | Required metadata |
|---|---|
| AR | `patterns_selected[]`, `constraints[]` |
| DV | `files_changed[]`, `tests_run`, `build_status`, `requires_screenshots`, `ui_visual_check` |
| DR | `gate_blockers[]`, `severity_counts{}` |
| SR | `findings[]` with CWE mapping, `severity_counts{}` |
| QA | `tests_added[]`, `coverage_delta`, `suite_status` |

A blocked stage still emits frontmatter — `status: "blocked"` with `error_escalated_to:` naming the
stage that must resolve it.

## Patching state.json

Run corpflow's `state-patch.sh --stage <CODE> --prev <PREV>` when its path is supplied, via the
prompt or `task.metadata.state_patch_script`; it merges `tasks.<ID>` and `handoffs[FROM→TO]` from
your frontmatter.

- Path **not** supplied → skip silently. Never hand-roll a `jq` merge.
- Patch **fails** → proceed and return normally; the `SubagentStop` hook reconstructs the merge from
  your frontmatter — that is what unconditional emission buys.
- Never write `state.json` directly. It is orchestrator-owned.

## Return summary (≤500 tokens)

corpflow merges your return text into the next stage's context, so it is a budget, not a suggestion.

```markdown
## <STAGE> Summary — <plugin>:<agent>
**Verdict**: pass | fail | needs_changes
**Artifact**: .context/<file>.md
**Changed**: <n> files — <the 3–5 that matter>
**Evidence**: <build/test/screenshot status>
**Blockers**: <none | what blocks and which stage must resolve it>
**For next stage**: <what the next stage needs that is not obvious from the artifact>
```

Compress by dropping P2/P3 detail and pointing at the artifact. Never truncate mid-structure — a
half-written table costs the next stage more than an omitted section.

## Gate feedback on re-dispatch

On re-dispatch after a DR or QA rejection, `metadata.gate_blockers[]` carries the findings. Address
every entry or explain in the artifact why one is not actionable. Do not re-litigate the gate;
a disputed blocker is escalated via `error_escalated_to:`, not ignored.

## Frontmatter templates

Copy the block for the active stage.

### DV
```yaml
handoff:
  from: "<plugin>:<dv-agent>"
  to: "corpflow:technical-lead"
  stage: "DV"
  run_index: <N>
  status: "completed"
  verdict: "pass"
  artifacts: [".context/development-<N>.md"]
  metadata:
    files_changed: []
    tests_run: ""
    build_status: "pass"
    requires_screenshots: <true|false>
    ui_visual_check: <true|false>
```

### AR (consultation)
```yaml
handoff:
  from: "<plugin>:<architect-agent>"
  to: "corpflow:software-architector"
  stage: "AR"
  run_index: <N>
  status: "completed"
  verdict: "pass"
  artifacts: [".context/<platform>-architecture.md"]
  metadata:
    patterns_selected: []
    constraints: []
```

### DV-support

No `state.json` patch, parent DV agent owns the artifact:
```yaml
handoff:
  from: "<plugin>:<support-agent>"
  to: "<plugin>:<parent-dv-agent>"
  stage: "DV"
  run_index: <N>
  status: "completed"
  verdict: "pass"
  artifacts: []
  metadata:
    support_role: "<performance|dependencies|accessibility>"
    findings: []
```

### IR (emergency)
```yaml
handoff:
  from: "<plugin>:<agent>"
  to: "corpflow:incident-responder"
  stage: "IR"
  run_index: <N>
  status: "completed"
  verdict: "pass"
  artifacts: [".context/incident-report.md"]
  metadata:
    root_cause: ""
    hotfix_constraints: []
```

## Orchestrator agent roles

Some of this plugin's own commands run a multi-stage flow that borrows orchestrator agents — an
architect for a design pass, a reviewer for a DR gate. Those commands name the **role**, never the
id, so this table stays the only place an id appears. Resolve the role here before dispatching; if
this file is absent the plugin is standalone and those phases are skipped, not failed.

### Role table

| Role named in a command | Agent id |
|---|---|
| the orchestrator's product manager | `corpflow:product-manager` |
| the orchestrator's architect | `corpflow:software-architector` |
| the orchestrator's DR reviewer | `corpflow:technical-lead` |
| the orchestrator's QA engineer | `corpflow:qa-engineer` |
| the orchestrator's technical writer | `corpflow:technical-writer` |
| the orchestrator's security reviewer | `corpflow:security-reviewer` |
| the orchestrator's ethics reviewer | `corpflow:ethics-reviewer` |
| the orchestrator's project manager | `corpflow:project-manager` |
| the orchestrator's worktask engineer | `corpflow:workflow-engineer` |
| the orchestrator's platform router | `corpflow:developer` |
| the orchestrator's meta-prompt engineer | `corpflow:prompt-engineer` |

### Standards are referenced by id

Shared **standards** are referenced by id directly (`corpflow:code-comment-standard`,
`corpflow:security-review-process`, `corpflow:claude-constitution`, `corpflow:logging-conventions`).
They are vocabulary rather than orchestration: copying them into each plugin lets the wording drift,
and a drifting standard is worse than a named one.

## Keeping the seam single

A corpflow contract change moves this file and nothing else in <PLUGIN> — a property that only holds
if it is defended:

- Do not add a corpflow reference to an agent, command, skill, or hook. A rule an agent needs belongs
  here, and corpflow's dispatch injection delivers it.
- Do not split this file into a directory of references. One file is the contract.
- Hooks describing orchestrator interop say "the orchestrator" generically: they work under corpflow
  or standalone, and naming corpflow in a comment re-couples a file that had no reason to be.
- <PLUGIN>'s own version does not track corpflow's. Record the corpflow version this file targets
  below and bump it when the contract changes.

| | |
|---|---|
| Targets corpflow | `<version>` |
| Contract source | `corpflow skills/cross-plugin-handoff/references/plugin-contract.md` |
