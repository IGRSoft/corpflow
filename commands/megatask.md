---
name: megatask
description: Orchestrate many worktasks across a GitHub milestone or an explicit issue array, ordered by a dependency/blocker DAG and priority, each issue in its own isolated worktree.
argument-hint: '<milestone-N> | --issues N,N,N [--secure] [--platform apple|android|web|all] [--dry-run]'
version: 0.1.0
model: opus
allowed-tools: Read, Glob, Grep, Bash(mkdir:*), Bash(gh:*), Bash(git:*), Bash(jq:*), TaskCreate, TaskUpdate, TaskGet, TaskList, Task(igrsoft:product-manager), Task(igrsoft:workflow-engineer), Task(igrsoft:project-manager)
related:
  - skills/megatask/SKILL.md
  - skills/megatask/references/dependency-graph.md
  - skills/megatask/references/schemas.md
  - skills/shared/milestone-helpers/SKILL.md
  - hooks/megatask-monitor.sh
  - commands/worktask.md
  - commands/pm-milestone.md
  - agents/workflow-engineer.md
---

> **EXECUTION MODEL (BINDING)** — megatask is the **meta-orchestrator**: it owns the issue set,
> builds the dependency DAG, and launches one **`/worktask`** per issue. It does NOT implement code
> itself. Each per-issue worktask is worktree-isolated and runs **unattended** — megatask stamps
> `plan_gate: "bypass"` and `fn_gate: "bypass"` on every per-issue `PL0` because a batch cannot stop
> for per-issue plan/finalization approval. Review surface is the **per-issue PR**. megatask keeps
> exactly **one** human checkpoint of its own: the **R1 batch confirmation** (Phase 1) — it presents
> the resolved issue set, the DAG, and the PR count, and waits for `AskUserQuestion` approval before
> launching anything. `--dry-run` stops after the DAG is built (no worktrees, no PRs).

# Megatask Command

Orchestrate a batch of worktasks across a GitHub milestone or an explicit array of issues. Megatask
resolves the issue set, parses **dependencies / blockers / priority**, builds a directed acyclic
graph (DAG), and executes issues in **topological + priority order** — never starting an issue whose
blockers have not merged — each in an isolated git worktree, each producing its own PR.

> **CRITICAL CONSTRAINTS**
> - MUST use TaskCreate/TaskUpdate/TaskGet/TaskList for orchestrator + per-issue state. Do NOT use Claude Code's built-in plan mode.
> - Megatask MUST NOT contain stage logic (PL/AR/DV/…). Stages belong to `/worktask`. Megatask only sequences worktasks.
> - If a dependency **cycle** is detected, STOP and report the cycle — do NOT guess an order.
> - If Task tools are unavailable, STOP and report. Do NOT fall back to alternative planning.

## Usage

```
/megatask N                      # All open issues in GitHub milestone N
/megatask N --issues 12,15       # Subset: only issues 12,15 within milestone N
/megatask --issues 12,15,18      # Explicit issue array (no milestone grouping required)
/megatask N --dry-run            # Build + print the DAG and plan; create nothing
```

`N` (a bare positional integer) selects a GitHub milestone. `--issues` supplies an explicit set. At
least one of the two MUST be present. When both are present, `--issues` filters within milestone `N`.

## Options

| Option | Effect |
|--------|--------|
| `N` (positional) | GitHub milestone number — execute its open issues |
| `--issues N,N,N` | Explicit issue array (comma-separated). May span milestones or have none |
| `--secure` | Forward `--secure` to every per-issue worktask (11-stage pipeline) |
| `--platform <apple\|android\|web\|all>` | Forward `--platform` to every per-issue worktask |
| `--dry-run` | Resolve issues, build the DAG, print the execution plan — create no worktrees, no PRs |
| `--secure`, `--platform` and other per-issue worktask flags are forwarded verbatim into each issue's `/worktask` invocation. |

> Cross-issue concurrency (`parallel_tracks`) is **orchestrator-derived**, never a flag — see
> Phase 2 § Track Derivation. Intra-issue async (whether one issue's DV0 splits into DV0/DV1/…) is
> owned by that issue's **TL stage**, orthogonal to the track count.

## Examples

```bash
/megatask 7                          # Execute milestone 7 by DAG + priority
/megatask 7 --secure                 # …with the 11-stage secure pipeline per issue
/megatask --issues 101,102,103       # Execute an explicit, cross-milestone issue set
/megatask 7 --dry-run                # Preview the DAG/order without touching git
```

## Phase 1: Resolve & Plan (execute immediately)

> **BINDING — Pre-work Prohibition**: Phase 1 creates NO worktrees and modifies NO project files.
> Only `mkdir -p .worktrees/<group>` and reads/`gh` queries are permitted until the R1 gate clears.

1. **Parse arguments** — extract the positional milestone `N` (if any), `--issues`, and forwarded
   flags (`--secure`, `--platform`, …). Validate that `N` OR `--issues` is present; otherwise STOP
   with a usage error.

2. **Resolve the issue set**:
   ```bash
   # Milestone mode
   gh api "/repos/{owner}/{repo}/milestones/${N}" --jq '.title'           # validate milestone exists
   gh api "/repos/{owner}/{repo}/issues?milestone=${N}&state=open" --paginate \
     --jq '.[] | {number, title, labels: [.labels[].name], body}'
   # Array mode (per issue)
   gh issue view "${ISSUE}" --json number,title,labels,body,state
   ```
   Drop issues that are `closed` or that already have a linked PR (auto-detect via
   `hasExistingPR` — see `skills/shared/milestone-helpers/SKILL.md`); record them as `skipped_has_pr`.

3. **Build the dependency DAG** — for each issue, parse the body for `Depends on: #N` and
   `Blocks: #M` lines (the format `/pm-milestone` writes) and the priority label (`P0`–`P3`).
   Construct `blocked_by[]` / `blocks[]` adjacency. **Normalize edges** so `A Blocks B` and
   `B Depends on A` collapse to a single edge `A → B`. Drop edges to issues outside the resolved set
   (record them as `external_dependency` notes — they do not gate execution but ARE surfaced).
   Full algorithm + schema: `skills/megatask/references/dependency-graph.md`.

4. **Detect cycles & compute order** — run a topological sort with a **priority tiebreak**
   (P0 before P1 …; FIFO by issue number within a tier). If a cycle exists, STOP and report the
   participating issues — do NOT proceed.

5. **Seed orchestrator.json** — atomic-write `.worktrees/<group>/orchestrator.json` (schema v3.1,
   `skills/megatask/references/schemas.md`) recording the milestone/array, the DAG edges per issue
   (`blocked_by`/`blocks`/`level`), the initial `status` (`ready` when `blocked_by` is empty, else
   `blocked`), priorities, the computed topological order, and
   `configuration.parallel_tracks` (derived in Phase 2). `<group>` is `milestone-{N}` (milestone
   mode) or `issues-{shortid}` (array mode).

6. **R1 — Batch confirmation gate (the one human checkpoint)** — present:
   - the resolved issue set (number, title, priority, `blocked_by`),
   - the DAG as an ordered/levelled list (which issues start immediately vs. wait on blockers),
   - the derived `parallel_tracks` and the **total PR count** this run will open,
   - any `external_dependency` warnings and `skipped_has_pr` issues.

   Then call `AskUserQuestion`:
   *"Megatask will execute N issues across M dependency levels, opening N PRs unattended (each
   per-issue worktask auto-approves its plan and finalization). Approve to begin, or adjust scope."*

   - **On approval** → append `{"actor":"megatask","action":"batch_approved","subject":"<group>","result":"ok"}` to `.context/logs/audit.jsonl`; continue to Phase 2.
   - **On rejection** → append `batch_rejected`; STOP. Surface feedback; do not create worktrees.
   - **`--dry-run`** → print the plan and STOP here regardless (no gate, no execution).

## Phase 2: Execute (proceeds after R1 approval)

**Track Derivation** (compute once, record in `orchestrator.json → configuration.parallel_tracks`):

```
parallel_tracks = min( count(currently-ready issues), 5 )      # ready = blocked_by is empty/all-merged
parallel_tracks = reduce_by_disk_capacity(parallel_tracks)     # each worktree duplicates the working tree
# single explicit issue ( /megatask --issues 12 )  ⇒  1
```

Never a flag, never a fixed default. Re-derived as the ready-set grows when blockers merge.

**Execution loop** (driven cooperatively with `hooks/megatask-monitor.sh`):

1. **Select ready issues** — an issue is *ready* when every entry in its `blocked_by[]` has
   `status: "completed"` (its PR merged, or created when the project merges via PR). Order ready
   issues by the topological + priority order from Phase 1.

2. **Assign tracks** — fill up to `parallel_tracks` worktrees. For each assigned issue:
   - Resolve base branch (issue body `base_branch:` → `develop` → `master`).
   - `git worktree add -b feature/{issue#}-{slug} .worktrees/<group>/{issue#} origin/{base}`
   - Write `workspace.json` (`isolation: "worktree"`, version 2.0) and `mkdir -p …/.context`.
   - Set the issue's orchestrator status `in_progress`, assign `track`.

3. **Launch the per-issue worktask** — delegate to `/worktask` for that issue, **with both gates
   pre-bypassed**. Megatask stamps the per-issue `PL0.metadata` directly:
   `{ stage:"PL", agent:"igrsoft:product-manager", model:"opus", issue_number, track,
   workspace_path:".worktrees/<group>/{issue#}", isolation:"worktree",
   plan_gate:"bypass", fn_gate:"bypass", megatask_group:"<group>", milestone:<N|null> }`.
   The per-issue worktask then runs its normal stage loop unattended (it honors the stamped gates;
   it does NOT need to know about milestones — see `commands/worktask.md`). The presence of
   `workspace.json` makes the per-issue worktask auto-skip its own GitHub-issue publish (the parent
   milestone/issue is the canonical record).

4. **Monitor** — `hooks/megatask-monitor.sh` (SubagentStop/Stop) watches per-issue completion:
   on completion it marks the issue `completed` in `orchestrator.json`, **unblocks dependents**
   (removes the merged issue from each dependent's `blocked_by[]`; promotes any now-empty dependent
   to `ready`), frees the track, and emits a progress audit row + notification. The orchestrator
   re-reads `orchestrator.json` each loop turn, re-derives `parallel_tracks`, and assigns freed
   tracks to newly-ready issues. See `skills/megatask/SKILL.md § Monitoring Loop`.

5. **Completion / errors** — on issue success: PR is created with `Closes #{issue}`, track freed.
   On issue failure: mark `failed`, free the track, preserve the worktree for debugging, and
   surface to the user (a failed blocker keeps its dependents permanently `blocked` — report them).

6. **Terminate** when every issue is `completed`, `failed`, or `skipped` and no track is active.
   Print the final summary (per-issue status + PR links), then `git worktree prune` stale entries.

## Dependency / Blocker / Priority Model

| Concept | Source | Effect |
|---------|--------|--------|
| **Priority** | `P0`–`P3` labels on the issue | Orders ready issues within a topological tier (P0 first) |
| **Dependency** | `Depends on: #N` in issue body | Issue is `blocked_by` #N — cannot start until #N is `completed` |
| **Blocker** | `Blocks: #M` in issue body | Reverse edge: this issue blocks #M (normalized to #M `Depends on` this) |
| **External dep** | `Depends on: #X` where #X ∉ resolved set | Surfaced as a warning; does NOT gate (out of batch scope) |

The DAG is the **single source of truth** for ordering. Priority only breaks ties among issues that
are *already* unblocked. Full normalization rules, cycle detection, and the levelled-execution
schedule live in `skills/megatask/references/dependency-graph.md`.

## Relationship to /worktask and /pm-milestone

```
/pm-milestone  →  creates issues with Depends on / Blocks / P0–P3   (ticket generation)
        │
        ▼
/megatask N    →  reads the DAG, orchestrates one /worktask per issue (batch execution)
        │
        ▼
/worktask      →  executes ONE issue's staged pipeline (PL→…→ST), milestone-agnostic
```

- `/worktask` no longer accepts `--milestone:N` — that surface moved here. A single task is still
  `/worktask "<task>"`.
- `/megatask` owns everything multi-issue: issue-set resolution, the DAG, track derivation, the
  monitoring hook, and per-issue gate-bypass. `/worktask` stays a single-issue stage runner.

