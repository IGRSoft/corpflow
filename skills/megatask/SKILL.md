---
name: megatask
description: Meta-orchestration of many worktasks across a GitHub milestone or explicit issue array — dependency/blocker DAG, priority ordering, isolated per-issue worktrees. Use for /megatask, multi-issue batches, or any dependency-ordered fan-out of worktasks.
effort: high
version: 0.4.0
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
  - ../shared/state-ledger.md
scripts:
  - scripts/build-orchestrator.sh
  - scripts/init-worktree.sh
  - scripts/resolve-pbxproj-membership.sh
---

# Megatask

Meta-orchestration layer that executes a **batch** of single-issue worktasks. Megatask owns the
issue set (a GitHub milestone or an explicit `--issues` array), builds a **dependency/blocker DAG**,
executes issues in **topological + priority order**, and isolates each issue in its own git worktree.
It launches one `/worktask` per issue; it never runs stages itself.

> **Separation of concerns.** `/worktask` runs ONE issue's staged pipeline (PL→…→ST) and is
> milestone-agnostic. `/megatask` sequences many worktasks. All milestone/array/DAG/track logic
> lives here — not in `worktask.md`.

## Canonical Scripts

Two executable INIT scripts in `scripts/` drive the two heavy init operations, and one resolver
handles the single merge-conflict class that needs no interpretation. Invoke them instead of
reading the reference files when doing real work — the references remain the authoritative spec
but are no longer needed in the happy path.

### `scripts/build-orchestrator.sh` — DAG builder

Reads pre-fetched issue JSON, extracts dependency edges, runs Kahn cycle detection, assigns
levels, computes `parallel_tracks`, and emits `orchestrator.json v3.1`.

#### Invocation — build-orchestrator

```bash
# One-line contract (no network required — pass pre-fetched JSON):
bash scripts/build-orchestrator.sh \
  --file issues.json \
  --out  .worktrees/milestone-1/orchestrator.json \
  --group milestone-1 --milestone-num 1 --milestone-title "Sprint 1" \
  --base-branch develop

# Self-test (no network, no side effects):
bash scripts/build-orchestrator.sh --self-test
```

Input schema: `[{ "issue": <int>, "title": "<str>", "labels": ["P0",...], "body": "<str>" }]`
Output: `orchestrator.json v3.1` — see `references/schemas.md` for the full field contract.

The reference file `references/dependency-graph.md` is the algorithm spec; this script is its
executable implementation. On cycle detection the script exits 1 and names the participating
issues on stderr — never silently invents an order.

### `scripts/init-worktree.sh` — per-issue worktree initialiser

For one issue: resolves base branch (delegates to `milestone-helpers.sh`), creates the git
worktree at `.worktrees/<group>/<issue#>`, makes `.context/`, and stamps `workspace.json v2.0`.

#### Invocation — init-worktree

```bash
# One-line contract:
bash scripts/init-worktree.sh \
  --issue 42 --title "Add login flow" --group milestone-1 \
  --track 1 --blocked-by 41 --blocks 60 --labels "P1,feature" \
  [--file issue-42.json]   # pre-fetched JSON for base-branch + labels

# Dry-run (prints planned actions, no mutations):
bash scripts/init-worktree.sh --issue 42 --title "..." --group milestone-1 --dry-run

# Self-test (spins up a temp git repo, no network beyond local git):
bash scripts/init-worktree.sh --self-test
```

#### Behavior — init-worktree

`--file` accepts pre-fetched `gh issue view … --json body,labels` output for offline/testable
use. Without `--file`, base-branch resolution calls git ls-remote (thin, optional). Idempotent:
re-running on an existing worktree path is a no-op (safe on retry).

Before creating the worktree it excludes the batch's scratch metadata (`/workspace.json`,
`/.worktrees/`) via the git common dir's `info/exclude`, so `git status` in a fresh worktree is
empty and an unscoped `git add -A` cannot stage it. The exclusion is checkout-wide and never
masks a tracked file — `references/git-integration.md § Creation`.

The reference file `references/git-integration.md` is the lifecycle spec; this script is its
executable implementation. Branch naming and base-branch resolution are fully delegated to
`../shared/milestone-helpers/scripts/milestone-helpers.sh` — no slug or branch logic is
duplicated here.

#### Runtime twin

> **Runtime twin.** `hooks/megatask-monitor.sh` (the SubagentStop/Stop hook) handles the
> *completion* side of the lifecycle — reconciling workspace.json outcomes back into
> orchestrator.json. These INIT scripts handle the *creation* side only. The two sides agree on
> the same `workspace.json v2.0` schema and `orchestrator.json v3.1` schema defined in
> `references/schemas.md`.

### `scripts/resolve-pbxproj-membership.sh` — membershipExceptions conflict resolver

Resolves a conflict in an Xcode project file's synchronized-build-file
`membershipExceptions = ( … );` list by **sorted, deduplicated union** of both sides. Keeping only
one side unregisters test files: the build stays green and those tests silently never run again.

#### Invocation — resolve-pbxproj-membership

```bash
bash scripts/resolve-pbxproj-membership.sh --file App.xcodeproj/project.pbxproj
bash scripts/resolve-pbxproj-membership.sh --file <path> --dry-run   # prints result, writes nothing
bash scripts/resolve-pbxproj-membership.sh --self-test
```

#### Behavior — resolve-pbxproj-membership

This is the one exception to § Conflict Resolution's hand-resolve rule, and only because it
**refuses everything it does not recognise**. A conflict elsewhere in the file, a comment or blank
line inside a side, nested or unterminated markers, a diff3 `|||||||` base section (an entry may
have been deliberately deleted — a union would resurrect it), or a hunk spanning the list's `);`
all refuse the **whole file**: exit 1 with a `refusing: <reason>` message, the file byte-identical.
Byte-identity is structural, not asserted — the parse writes a `mktemp` buffer and `mv -f`s only on
accept, so there is no in-place edit path. Exit codes: 0 union written / no conflict / dry-run /
self-test passed; 1 refusal or usage error; 2 `awk` missing.

Rule 2 of § Conflict Resolution still applies: build and test before pushing.

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

### Unattended open questions

For the same reason megatask also stamps `decision_gate: "auto"` (default `"user"`) on every
per-issue `PL0`: that issue's `open_questions[]` route through the Fable-model decision pass
(`commands/worktask.md § Step A.4`) instead of parking the batch on a human. Escalate-class
questions are never auto-decided here either — they **PARK that single issue** while the batch
continues with the remaining unblocked issues.

#### Parking an escalate-class question

Parking rides the existing failure path: the
per-issue worktask settles `execution.status: "failed"` + `execution.reason: "parked_escalation"`
with an `escalation_parked` audit row (`commands/worktask.md § Step A.4 Escalation guard`), so the
monitor frees the track and keeps dependents `blocked`; the batch summary lists each parked issue
with its unanswered questions.

> For headless `-p` runs, set `MCP_CONNECTION_NONBLOCKING=true` to skip the MCP connection wait;
> with `--mcp-config`, server connections are bounded at 5s rather than blocking on the slowest.

## Track Derivation

`parallel_tracks` is computed at init and re-derived as blockers merge:

```
parallel_tracks = min( count(currently-ready issues), 5 )
parallel_tracks = reduce_by_disk_capacity(parallel_tracks)   # each worktree duplicates the tree
parallel_tracks = reduce_by_concurrency_cap(parallel_tracks) # CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS (20)
# single explicit issue ( /megatask --issues 12 ) ⇒ 1
```

Recorded in `orchestrator.json → configuration.parallel_tracks`. Never a flag/default.

### Subagent spawn budget

> **Subagent spawn budget**: each issue dispatches ~9–11 stage subagents (9-stage default, 11-stage `--secure`) from the single megatask orchestrator session, plus nested delegation (DV routing to platform agents and Tier-2 specialists, QA spawning `test-generator`). CC 2.1.224 removed the per-session total-spawn cap, so batch size is **no longer bounded by a running count** — there is no ~18/~22-issue ceiling to plan around and no env var to raise. What still refuses a dispatch is **concurrency** (`agent-coordination § Two independent ceilings`) and, below it, disk for the per-issue worktrees and your rate budget. Size batches against peak concurrency, not a total.

### Nesting-depth budget

> **`/megatask` spends one depth level before any stage runs.** Phase 2 Step 3 delegates a per-issue `/worktask` orchestrator as its own sub-agent, so the chain is one level deeper than a standalone worktask at every point:

| Level | Standalone `/worktask` | Under `/megatask` |
|-------|------------------------|-------------------|
| 0 | session | session |
| 1 | stage agent (`corpflow:developer`) | per-issue `/worktask` orchestrator |
| 2 | platform router (`apple-developer:apple-developer`) | stage agent (`corpflow:developer`) |
| 3 | Tier-2 specialist (`apple-developer:test-generator`) | platform router |
| 4 | — | Tier-2 specialist ⚠️ **past the default ceiling** |

#### Depth remediations

> The default depth cap is **3** (`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`). A batch whose DV stages route through a platform router to a Tier-2 specialist loses that last delegation — the specialist is never spawned, and the platform agent completes the work itself. Two remediations:
>
> 1. **Raise the cap** (preferred — preserves routing): export `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=4` (or higher for `--secure` batches that also nest under SR) before starting the batch.
> 2. **Flatten Tier-2** (no config required): have DV dispatch the platform specialist directly (`apple-developer:ios-developer`) instead of the router, reclaiming one level at the cost of the router's platform-detection step.
>
> The R1 gate reports the batch's projected max depth so the choice is made before any worktree exists.

#### One formula, two callers

> The level table above is canonical; `skills/worktask/SKILL.md § Validation check 11` applies it per-stage for standalone worktasks, differing only in `orchestrator_offset` (1 here, 0 standalone). Editing one column of the table without the other is how the two drift — the same chain must project **3** standalone and **4** under `/megatask`. What neither projection can see is an unanticipated hop; that is caught afterwards by `agent-coordination § Depth-refusal self-report`.

### Concurrency budget

> Distinct from both the total-spawn and depth caps: **20 subagents may run concurrently** by default (`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`). Because subagents are background-by-default, a megatask run's live population is roughly `parallel_tracks × (1 orchestrator + 1 stage agent + its nested children)` — at `parallel_tracks = 5` with routine Tier-2 delegation that approaches the cap. `parallel_tracks` derivation bounds itself against this ceiling; raise the env var only when the disk and rate budgets also allow it.

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

## Per-Track Task IDs

Every track uses the same plain `<STAGE>0` ledger keys. The namespace is the **worktree**, not
the key: each track has its own `.context/state.json` under its own worktree, so two tracks both
writing `PL0` never share a ledger and cannot collide. Track-offset ids would additionally break
every hardcoded `PL0`/`AR0`/`FN0` reader and the `PL is always PL0 only` rule in
`../shared/state-ledger.md`.

```
Track 1: PL0, AR0, DV0, DR0, QA0
Track 2: PL0, AR0, DV0, DR0, QA0   ← own worktree, own ledger
```

### Seeding a track's PL

```bash
# megatask bypasses both default-checkpoint gates; decision_gate=auto means open
# questions go to a Fable decision pass and an escalation parks the issue.
state-patch.sh --task-create "PL0" --metadata "$(jq -n \
  --argjson issue "$ISSUE_NUMBER" --argjson track "$TRACK" \
  --arg group "$GROUP" --arg ms "$MILESTONE_OR_EMPTY" \
  '{stage:"PL", agent:"corpflow:product-manager",
    description:"Planning - Issue #\($issue)",
    issue_number:$issue, track:$track,
    workspace_path:".worktrees/\($group)/\($issue)",
    isolation:"worktree",
    megatask_group:$group, milestone:(if $ms == "" then null else $ms end),
    fn_gate:"bypass", plan_gate:"bypass",
    decision_gate:"auto"}')"
```

## Base Branch Resolution

Per-issue fallback chain (stored in `workspace.json` as `base_branch_source`):
1. **Issue body**: parse `base_branch: <branch>`
2. **Develop fallback**: if `develop` exists on remote
3. **Master default**: fall back to `master`

## Branch Naming

`<type>/{issue#}-{slug}` — type derived from the issue title (`feature` by default, `bugfix`
for a defect, …); slug = lowercase title, spaces→hyphens, no special chars, max 50 chars,
truncated on a word boundary. Canonical definition: `../shared/milestone-helpers/SKILL.md`.

## Shared-Seam Registry

A **seam** is a code surface more than one issue in the batch touches by name: a shared protocol,
a dependency-injection extension point, a coordinator, or a shared test assertion. Parallel
tickets cannot see each other's work in progress, so two of them will independently invent the
same abstraction under different names unless one place tells them it already exists. A
dependency graph built from issue-body cross-references cannot see this class at all — the
tickets are genuinely independent; only their *seams* collide.

### Registry location

**Exactly one registry per batch**, in an issue body under a `## Shared Seams` H2. An issue body
already exists, is already fetched at dispatch, and needs no lifecycle. Which issue hosts it is a
rule, not a judgement call — two hosts would reproduce the very failure this prevents, with two
tickets each reading a different registry and each concluding no seam exists:

| Batch shape | Registry host |
|---|---|
| Exactly one level-0 issue (no `blocked_by`) — the **foundation issue** | that issue's body |
| More than one level-0 issue, or none | the **milestone issue** (milestone mode) or the **orchestrator issue** (`--issues` array mode) |

#### What "foundation issue" means

The first row: the batch's *sole* level-0 issue, the one every other issue transitively depends
on. A batch without one has no foundation issue, and its registry is at the batch level.

**Convention, not a gate.** Nothing validates the registry this release. Its force comes from the
per-issue prompt directing every issue to read it before introducing a shared abstraction
(`../../commands/megatask.md § Phase 2 loop · Step 3`).

### Registry schema

One block per seam. `declaration` carries the **verbatim** signature with every parameter label
in order — a name-only entry would not catch two issues agreeing on a concept but reversing an
argument order, which is the failure that motivated this.

````markdown
## Shared Seams

### NotificationDestinationPresence
- kind: protocol | di-extension-point | coordinator | test-contract
- status: planned | landed
- owner: #<issue that introduces it>
- consumers: #<issue>, #<issue>
- location: <path/to/File.swift>
- declaration:
  ```swift
  protocol NotificationDestinationPresence {
      func setPresented(_ presented: Bool, for destination: Destination)
  }
  ```
- change-protocol: adding or reordering a member requires updating this entry in the same PR
  and naming every issue in `consumers:` in that PR's description.
````

#### Why consumers and change-protocol are mandatory

`consumers:` plus `change-protocol:` are what make an additive change safe: adding a member to a
shared protocol silently breaks every test double conforming to it, and the adder is the only
party positioned to know.

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

#### Hook properties

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

## Conflict Resolution

Parallel branches off one base collide on shared files. Two rules are binding for every conflict
a batch produces.

### Rule 1 — hand-resolve DI and coordinator shapes

**Dependency-injection containers and coordinator-shaped files are hand-resolved by a human;
never script-merge them.** Any "keep both sides" automation is forbidden on these shapes: a
registration list, a DI container extension, a coordinator's argument list, or a switch over
destinations. Observed failure: a scripted keep-both-sides join dropped an argument separator
(the other side's block opened with a comment line) and duplicated a closing brace twice. Both
survived review and were caught only by a later build.

A script is allowed only where its conflict class needs no interpretation *and* the script
refuses everything it does not recognise; § Canonical Scripts names any such tool the batch
ships. Absent that, this rule stands.

### Rule 2 — build and test before pushing

**Build and test after every conflict resolution, before pushing.** Not a read-through, not a
syntax check — the real build and the real test run, from the worktree. Rule 1's failure mode is
invisible to everything cheaper.

### Recovery when the branch cannot be re-pushed

Rebase, push under a new name, open a replacement PR, close the superseded one:
`references/git-integration.md § Conflict Recovery`.

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
- `failed` — max retries exceeded, or parked on unanswered escalate-class questions (`workspace.json.execution.reason: "parked_escalation"`)

## GitHub CLI

```bash
gh api /repos/{owner}/{repo}/milestones/{N}
gh api "/repos/{owner}/{repo}/issues?milestone={N}&state=open" --paginate
gh issue view {ISSUE} --json number,title,labels,body,state
```

See `references/` for the DAG algorithm, orchestrator/workspace schemas, git integration, and the
agent-teams pattern.
