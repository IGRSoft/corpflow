---
name: megatask
description: Meta-orchestration of many worktasks across a GitHub milestone or explicit issue array — dependency/blocker DAG, priority ordering, isolated per-issue worktrees. Use for /megatask, multi-issue batches, or any dependency-ordered fan-out of worktasks.
effort: high
version: 0.2.0
related:
  - ../../commands/megatask.md
  - references/dependency-graph.md
  - references/schemas.md
  - references/git-integration.md
  - references/agent-teams.md
  - ../shared/milestone-helpers/SKILL.md
  - ../../hooks/megatask-monitor.sh
  - ../../commands/worktask.md
  - ../shared/stage-codes.md
  - ../shared/task-system.md
---

# Megatask

Meta-orchestration layer that executes a **batch** of single-issue worktasks. Megatask owns the
issue set (a GitHub milestone or an explicit `--issues` array), builds a **dependency/blocker DAG**,
executes issues in **topological + priority order**, and isolates each issue in its own git worktree.
It launches one `/worktask` per issue; it never runs stages itself.

> **Separation of concerns.** `/worktask` runs ONE issue's staged pipeline (PL→…→ST) and is
> milestone-agnostic. `/megatask` sequences many worktasks. All milestone/array/DAG/track logic
> lives here — not in `worktask.md`.

## Inputs

```
/megatask N                  # all open issues in GitHub milestone N
/megatask N --issues 12,15   # subset of milestone N
/megatask --issues 12,15,18  # explicit issue array (milestone optional)
```

`N` (bare integer) ⇒ milestone. `--issues` ⇒ explicit set. At least one required; together,
`--issues` filters within milestone `N`.

> Cross-issue concurrency (`parallel_tracks`) is orchestrator-derived, not a flag (see § Track
> Derivation). Intra-issue async (DV0 splitting into DV0/DV1/…) is owned by each issue's TL stage.

## Dependency & Blocker Resolution (DAG)

Megatask's core addition over plain priority batching: it reads **inter-issue relationships** and
executes a directed acyclic graph rather than a flat priority list.

### Edge sources

| Edge | Parsed from issue body | Meaning |
|------|------------------------|---------|
| `A blocked_by B` | `Depends on: #B` on issue A | A cannot start until B is `completed` |
| `A blocks B` | `Blocks: #B` on issue A | reverse of `B Depends on A` |

Both formats are what `/pm-milestone` emits in the `## Dependencies` section. Megatask **normalizes**
the two directions into a single edge set: `A blocks B` ⇔ `B blocked_by A`. Duplicate edges collapse.
Edges pointing outside the resolved issue set become `external_dependency` warnings (surfaced, but
they do **not** gate execution — they are out of batch scope).

### Ordering

1. **Cycle detection** (Kahn's algorithm). Any cycle ⇒ STOP and report the participating issues. Never guess an order.
2. **Topological sort** — issues with empty `blocked_by` form level 0; removing them exposes level 1; etc.
3. **Priority tiebreak** within a level: `P0` → `P1` → `P2` → `P3` → unlabeled; FIFO by issue number within a tier.

An issue becomes **ready** only when every entry in its `blocked_by[]` is `completed` (PR merged, or
created when the project closes via PR). Megatask **never starts an issue whose blockers are unmerged.**

Full algorithm, worked examples, and the levelled-schedule schema:
`references/dependency-graph.md`.

## Priority Sorting

Within a topological tier, issues are sorted by priority label (highest first):
1. `P0` / `priority:critical`
2. `P1` / `priority:high`
3. `P2` / `priority:medium`
4. `P3` / `priority:low`
5. No priority label

## Workspace Architecture

Each issue executes in its own isolated git worktree. `<group>` is `milestone-{N}` (milestone mode)
or `issues-{shortid}` (array mode).

```
.worktrees/
├── <group>/
│   ├── orchestrator.json             # Root orchestrator state (DAG + tracks + progress)
│   └── {issue#}/                     # Git worktree root (full source copy)
│       ├── .git                      # Worktree git link file
│       ├── .context/                 # Per-issue worktask artifacts (inside the worktree)
│       ├── workspace.json            # Workspace metadata (isolation: "worktree")
│       ├── handoff.md                # Compressed context
│       └── ...                       # Full source tree
```

Each worktree has its own branch checked out independently — no `git checkout` switching. Multiple
issues execute truly in parallel.

> Add `.worktrees/` to `.gitignore` so worktree contents do not appear as untracked files.

#### Sparse Checkout

For large monorepos, configure `worktree.sparsePaths` in project `settings.json` to check out only
relevant directories — reduces per-worktree disk and speeds initialization:

```json
{ "worktree": { "sparsePaths": ["src/", "tests/", "Package.swift"] } }
```

> Megatask startup reads git refs directly and skips a redundant fetch — significantly faster on
> repos with many branches. Sub-agents in isolated worktrees automatically get Read/Edit access to
> their own worktree — no explicit `tools:` grant needed.

### Unattended Execution

Megatask processes issues without intervening per-issue input. It **deliberately bypasses both
human gates** on every per-issue `PL0`: `plan_gate = "bypass"` and `fn_gate = "bypass"` (both default
`"checkpoint"`), because a batch cannot stop for per-issue plan or finalization approval. The single
human checkpoint is megatask's own **R1 batch confirmation** (before any worktree is created).
Per-issue changes are reviewable as per-issue PRs.

> For headless `-p` runs, set `MCP_CONNECTION_NONBLOCKING=true` to skip the MCP connection wait;
> with `--mcp-config`, server connections are bounded at 5s rather than blocking on the slowest.

## Track Derivation

`parallel_tracks` is computed at init and re-derived as blockers merge:

```
parallel_tracks = min( count(currently-ready issues), 5 )
parallel_tracks = reduce_by_disk_capacity(parallel_tracks)   # each worktree duplicates the tree
# single explicit issue ( /megatask --issues 12 ) ⇒ 1
```

Recorded in `orchestrator.json → configuration.parallel_tracks`. Never a flag/default.

## Status Transitions

```
pending → ready → in_progress → completed
                              → failed
        → blocked  (blocked_by not yet all completed)
        → skipped / skipped_has_pr
```

**Starting an issue**: set `in_progress`, assign `track`, create worktree + branch, begin the
per-issue worktask (PL→…→ST) with gates pre-bypassed.

**Completing an issue**: per-issue FN pushes the branch, opens a PR with `Closes #{issue}`, and writes
`execution.status: "completed"` + `execution.pr` into `workspace.json` (the completion contract in
`references/schemas.md`). The monitor hook reads that, marks the issue `completed` in
`orchestrator.json`, **unblocks dependents**, and frees the track. A `failed` issue writes
`execution.status: "failed"` — its dependents stay `blocked`.

## Track-Prefixed Task IDs

```
Track 1: t1-1 (PL0), t1-2 (AR0), t1-3 (DV0), t1-4 (DR0), t1-5 (QA0)
Track 2: t2-1 (PL1), t2-2 (AR1), t2-3 (DV1), t2-4 (DR1), t2-5 (QA1)
```

```typescript
// stageIndex = track - 1: Track 1→PL0, Track 2→PL1, …
const stageIndex = track - 1;
TaskCreate({
  taskId: `t${track}-1`,
  subject: `PL${stageIndex}: Planning - Issue #${issueNumber}`,
  metadata: {
    stage: "PL", agent: "igrsoft:product-manager",
    issue_number: issueNumber, track: track,
    workspace_path: `.worktrees/${group}/${issueNumber}`,
    isolation: "worktree",
    megatask_group: group, milestone: milestoneOrNull,
    fn_gate: "bypass", plan_gate: "bypass"  // megatask bypasses both default-checkpoint gates
  }
});
```

## Base Branch Resolution

Per-issue fallback chain (stored in `workspace.json` as `base_branch_source`):
1. **Issue body**: parse `base_branch: <branch>`
2. **Develop fallback**: if `develop` exists on remote
3. **Master default**: fall back to `master`

## Branch Naming

`feature/{issue#}-{slug}` — slug = lowercase title, spaces→hyphens, no special chars, max 50 chars.
Canonical definition: `../shared/milestone-helpers/SKILL.md`.

## Orchestrator Pattern

### Initialization

1. Create `.worktrees/<group>/` directory.
2. Resolve the issue set (milestone fetch or per-issue `gh issue view`); drop closed / `skipped_has_pr`.
3. Build the DAG (`references/dependency-graph.md`); detect cycles; compute topological + priority order.
4. **Derive** `parallel_tracks` = `min(count(ready issues), 5)`, disk-reduced; single explicit issue ⇒ 1.
5. Write `orchestrator.json` (schema v3.1) with the DAG, order, and tracks.
6. Run the **R1 batch confirmation gate**, then create worktrees and start the first ready issues.

### Monitoring Loop

The loop is **completion-driven** via `hooks/megatask-monitor.sh` (registered SubagentStop/Stop):

1. **On per-issue completion** — the hook marks the issue `completed` in `orchestrator.json`,
   removes it from every dependent's `blocked_by[]`, promotes now-unblocked dependents to `ready`,
   frees the track, and writes a `megatask_progress` audit row (+ optional notification).
2. **Orchestrator turn** — re-read `orchestrator.json`, re-derive `parallel_tracks`, assign freed
   tracks to ready issues (topological + priority order), launch their worktasks.
3. **Errors** — a `failed` issue frees its track but keeps its dependents permanently `blocked`;
   surface the blocked set so the user can intervene (retry, re-scope, or drop the edge).
4. **Stage creation** — verify each per-issue `PL0` created its subsequent stages.

The hook is **non-blocking** (always exits 0) and **self-skips** when no `orchestrator.json` is
present (i.e. plain single-issue worktasks are untouched). See `references/agent-teams.md` for the
optional agent-teams event model (`TeammateIdle` / `TaskCompleted`).

## Execution Flow

### Milestone: `/megatask N`

1. Fetch milestone + issues. 2. Build DAG, sort. 3. R1 gate. 4. Init `parallel_tracks` worktrees.
5. Each worktree runs independently. 6. On completion: PR, unblock dependents, assign next ready.

### Array: `/megatask --issues 12,15,18`

1. `gh issue view` each issue. 2. Build DAG across the set (cross-milestone allowed).
3. R1 gate. 4. Execute identically to milestone mode under group `issues-{shortid}`.

### Subset: `/megatask N --issues 12,15`

Resolve milestone N, then intersect with the explicit set before building the DAG.

### Multi-Issue Parallelism

Track count is orchestrator-derived (max 5), gated by the DAG (only ready issues consume tracks).

| Tracks | 5 independent issues | Time | Savings |
|--------|----------------------|------|---------|
| 1 | 5 × 1h | 5h | — |
| 2 | 3 × 1h | 3h | 40% |
| 5 | 1 × 1h | 1h | 80% |

A deep dependency chain (A→B→C→D→E) runs effectively serially regardless of track count — the DAG,
not the track cap, bounds it.

## Error Handling

| Error Type | Workspace Action | Orchestrator Action |
|------------|------------------|---------------------|
| Transient | Retry (3×) | Monitor |
| Fatal | Mark `failed` | Free track; keep dependents `blocked`; alert user |
| Dependency cycle | — | STOP at init; report participating issues |

**Global errors**: milestone not found, issue not in milestone/set, rate limit, dependency cycle.

## Issue Status Values

- `pending` — resolved, not yet scheduled
- `blocked` — `blocked_by` not all completed
- `ready` — all blockers completed; eligible for a track
- `in_progress` — worktree active
- `completed` — PR created
- `skipped` — manually skipped
- `skipped_has_pr` — already has a linked PR (auto-detected)
- `failed` — max retries exceeded

## GitHub CLI

```bash
gh api /repos/{owner}/{repo}/milestones/{N}
gh api "/repos/{owner}/{repo}/issues?milestone={N}&state=open" --paginate
gh issue view {ISSUE} --json number,title,labels,body,state
```

See `references/` for the DAG algorithm, orchestrator/workspace schemas, git integration, and the
agent-teams pattern.

