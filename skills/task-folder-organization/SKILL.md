---
name: task-folder-organization
description: Use when setting up task folders, organizing worktask artifacts, or resolving artifact paths. Context folder structure (.context/) with artifact naming and path resolution.
version: 0.3.0
---

# Task Folder Organization

**Category**: Task Management · **Priority**: High · **Applies to**: all tasks and features

Every project keeps **one `.context/` folder at the project root** holding all worktask artifacts: one location, a full audit trail from plan to deploy, preserved decision context, and a single unit to gitignore or commit. Under `/megatask` it lives inside each worktree (`.worktrees/<group>/<issue#>/.context/`), never in the main repo root.

## Layout

Flat — every `.md` sits directly in `.context/`; `designs/`, `images/`, `errors/`, and `logs/` are the only subdirectories.

```
.context/
├── <basename>-N.md   # stage artifacts, run-numbered (§ Stage Artifacts)
├── state.json        # worktask ledger; shared across runs, re-seeded each PL run
├── gh-issue.json     # run-independent .context ↔ GitHub issue anchor
├── milestone.json    # GitHub milestone context (under /megatask)
├── deployment.md     # deployment plan (optional)
├── designs/          # CANONICAL Figma assets: figma-*.png + figma-registry.md + Pencil .pen mockups
├── images/           # user-attached screenshots + DV implementation screenshots (NOT Figma)
├── errors/           # per-agent escalation narratives
└── logs/             # runtime capture logs (build/test/monitor/sim/incident/hotfix)
```

Per-variant layouts, asset naming, and worked examples: `references/examples.md`.

### Run-Index Naming

Stage artifacts are `<basename>-N.md`, N = `task.metadata.run_index` — an integer PL0 stamps on every downstream task, starting at 0. A PL0 rerun (scope change, re-plan) increments N, and `planning-1.md`, `architecture-1.md`, … land beside run 0's files, which are preserved.

`state.json`, `gh-issue.json`, `designs/`, `images/`, `errors/`, and `logs/` are **shared across all runs**, never duplicated per run. `state.json` is re-seeded (metadata wiped) each PL run, so the durable `.context ↔ issue` binding lives in `gh-issue.json` — that is what lets a follow-up run comment on the existing issue instead of opening a duplicate (`skills/gh-issue-dedup`).

### Stage Artifacts

Canonical stage→basename map: `skills/worktask/references/handoff-protocol.md#stage-artifact-map`; stage→agent: `skills/shared/stage-codes.md`. Path-resolution mirror:

| Artifact | Stage | Owner | Variant |
|---|---|---|---|
| planning-N.md | PL | product-manager | standard |
| architecture-N.md | AR | software-architector | standard |
| coordination-N.md | TL | team-lead | standard |
| development-<N>[-<stream>].md | DV | developer | all |
| developer-review-N.md | DR | technical-lead | all |
| security-review-N.md | SR | security-reviewer | `--secure` |
| testing-N.md | QA | qa-engineer | all |
| documentation-N.md | DC | technical-writer | standard |
| release-N.md | RE | release-engineer | `--secure`, emergency |
| complete-summary-N.md | FN | project-manager | all |
| retrospective-N.md | ST | stakeholder | standard |
| incident-N.md | IR | incident-responder | emergency |
| ethics-review-N.md | ET | ethics-reviewer | on demand |

#### Variant column

Standard = 9-stage `PL→AR→TL→DV→DR→QA→DC→FN→ST` (dynamic sizing may omit stages); `--secure` = 11-stage, adding SR and RE; emergency = `IR→DV→DR→QA→RE→FN`.

DV fans out as ledger tasks — one artifact per `DV<k>` row, `development-N-<stream>.md`: `skills/worktask/references/handoff-protocol.md § DV fan-out — ledger tasks`.

#### Artifact content

Each artifact opens with a header (task id, date, author agent), then purpose, stage content, next steps, and references to related documents.

### Canonical Figma Asset Directory

**`.context/designs/` is the single canonical directory for all Figma assets** — per-frame screenshots (`figma-*.png`), the registry (`figma-registry.md`), and Pencil `.pen` mockups all live here. PM (PL stage), the orchestrator, and QA all point at it, so the two directories never disagree.

- **Writer**: `product-manager` (PL) persists PNGs in-turn via `Bash(curl:*)` and writes `figma-registry.md` — `skills/worktask/references/pl0-procedure.md § Figma Design Capture`.
- **Reader**: `qa-engineer` (QA) reads `figma-registry.md` and compares it against each persisted frame — `agents/qa-engineer.md § Design Comparison (Visual QA)`.
- **Never write Figma assets to `.context/images/`** — that directory holds user-attached screenshots/diagrams and DV implementation screenshots (per-task `screenshots-<TASK_ID>.md` manifests).

#### Figma Filename Grammar

`figma-[screen]-[state]-[node-id].png` — per-frame children use the child name/id, the container overview uses the container's. See `skills/shared/figma-capture.md § Capture Workflow`.

### Per-Agent Error Files (`errors/`)

One escalation narrative per agent, created on failure, so parallel stages (QA+DC, TL-split DV streams, megatask tracks) cannot clobber each other and per-agent failure history survives.

- Path `.context/errors/<agent-basename>.md`; basename = last `:`-separated segment of `metadata.agent` (`developer`, `qa-engineer`, `ios-developer` for `apple-developer:ios-developer`). On cross-plugin collision, join with `-`: `apple-developer-ios-developer.md`.
- Append-only: one `## Retry N — <ts>` section per failure, each followed by a machine-readable metadata line (classification, task_id, retry_count).
- One agent across several tasks (TL split `DV0`/`DV1`/`DV2`) → a single `developer.md` with per-task sections (`## DV0 Retry 1`, `## DV1 Retry 1`, …).

### Runtime Logs (`logs/`)

Raw runtime capture — background `Bash` stdout, `Monitor` streams, simulator captures, incident tails — and therefore **distinct from `errors/`** (narrative escalation per agent). The `errors/` vs `logs/` split table, filename grammar (`<kind>-<scope>-<timestamp>.log`), examples, and cleanup policy are canonical in `skills/logging-conventions/SKILL.md § The Split`; not restated here, to avoid drift.

### Milestone Context File (`milestone.json`)

Written when the run is under `/megatask`: `milestone` (number, title, due date), `issues[]` sorted by priority with branch names, `execution` (current issue, completed/pending arrays), and `summary` counts. Schema: [Megatask](../megatask/SKILL.md).

## Common Pitfalls

| Don't | Do |
|---|---|
| Document in ad-hoc locations | Create `.context/` even for a small task |
| Skip ledger initialization | Seed and patch `state.json` at every stage |
| Add subfolders beyond `designs/`, `images/`, `errors/`, `logs/` | Keep every `.md` in the `.context/` root |
| Keep more than one `.context/` per project | One per project; under `/megatask`, inside the worktree, not the repo root |
| Write `.context/error.md` (retired path) | Append to `.context/errors/<agent>.md` per agent |
| Record only WHAT changed | Record the WHY behind each decision |
| Reuse a stale folder | Archive or clear `.context/` when starting a new task |
