---
name: megatask
description: Orchestrate many worktasks across a GitHub milestone or an explicit issue array, ordered by a dependency/blocker DAG and priority, each issue in its own isolated worktree.
argument-hint: '<N> | --issues N,N,N [--secure] [--platform apple|android|web|systems|backend|ai|all] [--dry-run]'
version: 0.2.0
model: opus
allowed-tools: Read, AskUserQuestion, SendMessage, ListAgents, Monitor, TaskStop, Bash(claude:*), Glob, Grep, Bash(mkdir:*), Bash(gh:*), Bash(git:*), Bash(jq:*), Bash(bash skills/worktask/scripts/state-patch.sh:*), Bash(bash skills/megatask/scripts/build-orchestrator.sh:*), Bash(bash skills/megatask/scripts/init-worktree.sh:*), Bash(bash skills/megatask/scripts/resolve-pbxproj-membership.sh:*), Task(corpflow:product-manager), Task(corpflow:workflow-engineer), Task(corpflow:project-manager)
related:
  - skills/megatask/SKILL.md
  - skills/megatask/references/dependency-graph.md
  - skills/megatask/references/schemas.md
  - skills/megatask/references/git-integration.md
  - skills/shared/milestone-helpers/SKILL.md
  - hooks/megatask-monitor.sh
  - commands/worktask.md
  - commands/milestone.md
  - agents/workflow-engineer.md
---

> **EXECUTION MODEL (BINDING)** — megatask is the **meta-orchestrator**: it owns the issue set,
> builds the dependency DAG, and launches one **`/worktask`** per issue in its own worktree. It
> writes no code and holds no stage logic — stages belong to `/worktask`. Every per-issue `PL0` is
> stamped `plan_gate: "bypass"`, `decision_gate: "auto"`, `fn_gate: "bypass"`: a batch cannot stop
> for one issue's approvals or open questions (§ Step 3). Review surface is the **per-issue PR**.
> megatask's own sole human checkpoint is the **R1 batch confirmation** (Phase 1). `--dry-run` stops
> once the DAG is built — no worktrees, no PRs.

# Megatask Command

Issues run in **topological + priority order** — never one whose blockers have not merged. Canonical
mechanics: `skills/megatask/SKILL.md`.

> **CRITICAL CONSTRAINTS**
> - Orchestrator + per-issue state lives in `.context/state.json` `tasks{}`, written only via `state-patch.sh`. Do NOT use Claude Code's built-in plan mode.
> - On a dependency **cycle**, or when the ledger cannot be read or written: STOP and report. Never guess an order, never fall back to alternative planning.

## Usage

`/megatask <N> | --issues N,N,N [--secure] [--platform <p>] [--dry-run]` — `N` (bare positional
integer) selects a milestone, `--issues` an explicit set; at least one MUST be present, and together
`--issues` filters within milestone `N`.

## Options

| Option | Effect |
|--------|--------|
| `N` (positional) | Milestone number — execute its open issues |
| `--issues N,N,N` | Explicit issue array; may span milestones or have none |
| `--secure` | Forwarded per issue (11-stage pipeline) |
| `--platform <apple\|android\|web\|systems\|backend\|ai\|all>` | Forwarded per issue |
| `--dry-run` | Resolve, build the DAG, print the plan — no worktrees, no PRs |

Cross-issue concurrency (`parallel_tracks`) is **orchestrator-derived, never a flag** (§ Track
Derivation); intra-issue async (an issue's DV0 splitting into DV0/DV1/…) belongs to its **TL stage**.

## Examples

```bash
/megatask 7                       # milestone 7 by DAG + priority
/megatask 7 --secure              # …with the 11-stage secure pipeline per issue
/megatask 7 --issues 12,15        # subset within milestone 7
/megatask --issues 101,102,103    # explicit, cross-milestone set
/megatask 7 --platform apple      # force Apple routing in every issue
/megatask 7 --dry-run             # preview the DAG/order, touch no git state
```

## Phase 1: Resolve & Plan (execute immediately)

> **BINDING — Pre-work Prohibition**: Phase 1 creates NO worktrees and modifies NO project files.
> Only `mkdir -p .worktrees/<group>` and reads/`gh` queries are permitted until R1 clears.

### Phase 1 · Steps 1–2 — Parse arguments & resolve the issue set

1. **Parse** the positional `N`, `--issues`, and forwarded flags. Neither present ⇒ STOP (usage error).
2. **Resolve the issue set**:
   ```bash
   gh api "/repos/{owner}/{repo}/milestones/${N}" --jq '.title'          # milestone mode: validate
   gh api "/repos/{owner}/{repo}/issues?milestone=${N}&state=open" --paginate \
     --jq '.[] | {number, title, labels: [.labels[].name], body}'
   gh issue view "${ISSUE}" --json number,title,labels,body,state        # array mode: per issue
   ```
   Drop `closed` issues and any with a linked PR (`hasExistingPR` —
   `skills/shared/milestone-helpers/SKILL.md`); record them as `skipped_has_pr`.

### Phase 1 · Steps 3–4 — Build the DAG & compute order

3. **Build the DAG** — parse each body for `Depends on: #N` / `Blocks: #M` (what `/milestone`
   writes) plus the `P0`–`P3` label into `blocked_by[]`/`blocks[]`; normalize `A Blocks B` ⇔
   `B Depends on A` to one edge. Edges leaving the resolved set become `external_dependency`
   warnings — surfaced, never gating.
4. **Order** — topological sort, **priority tiebreak** (P0 first; FIFO by issue number within a
   tier). Any cycle ⇒ STOP and report its issues. Rules + levelled schedule:
   `skills/megatask/references/dependency-graph.md`.

### Phase 1 · Step 5 — Seed orchestrator.json

5. Atomic-write `.worktrees/<group>/orchestrator.json` (schema v3.1,
   `skills/megatask/references/schemas.md`): per-issue edges (`blocked_by`/`blocks`/`level`),
   initial `status` (`ready` when `blocked_by` is empty, else `blocked`), priorities, the order, and
   `configuration.parallel_tracks` (Phase 2). `<group>` = `milestone-{N}` or `issues-{shortid}`.

### Phase 1 · Step 6 — R1 batch confirmation gate

6. **R1 — the one human checkpoint** — present the issue set (number, title, priority,
   `blocked_by`), the levelled DAG (what starts now vs. waits), `parallel_tracks` and **total PR
   count**, the projections below, and any `external_dependency` / `skipped_has_pr` notes. Then
   `AskUserQuestion`:

   *"Megatask will execute N issues across M dependency levels, opening N PRs unattended (each
   per-issue worktask auto-approves its plan and finalization). Approve to begin, or adjust scope."*

#### R1 spawn-budget projections

All three are warn-and-continue, never a hard gate. See `skills/megatask/SKILL.md § Track Derivation`.

| Projection | Formula | Cap (default) |
|---|---|---|
| Total spawns | `issue_count × ~9–11 stages` + nested-delegation spawns | no cap (removed in CC 2.1.224) |
| Max chain depth | megatask spends one level on the per-issue orchestrator, so DV → platform-router → Tier-2 lands at **4** | `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` (3) |
| Peak concurrent | `parallel_tracks × (orchestrator + stage agent + nested children)` | `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` (20) |

Over-cap depth ⇒ name both remediations: raise the env var, or flatten Tier-2 dispatch
(`skills/megatask/SKILL.md § Depth remediations`).

#### R1 outcomes

- **Approval** → append `{"actor":"megatask","action":"batch_approved","subject":"<group>","result":"ok"}` to `.context/logs/audit.jsonl`; continue to Phase 2.
- **Rejection** → append `batch_rejected`; STOP, surface feedback, create no worktrees.
- **`--dry-run`** → print the plan and STOP here regardless (no gate, no execution).

> A **free-text** R1 answer arrives neutrally worded, not framed as "continue". "Wait, explain the
> depth warning first" is a question, not approval: answer it and re-present the gate.

## Phase 2: Execute (proceeds after R1 approval)

**Track Derivation** — compute once into `configuration.parallel_tracks`; re-derive as blockers
merge and the ready-set grows. Never a flag, never a fixed default; the concurrency and depth
ceilings it respects are in `skills/megatask/SKILL.md § Track Derivation`.

```
parallel_tracks = min( count(currently-ready issues), 5 )      # ready = blocked_by empty/all-merged
parallel_tracks = reduce_by_disk_capacity(parallel_tracks)     # each worktree duplicates the tree
parallel_tracks = reduce_by_concurrency_cap(parallel_tracks)   # CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS (20)
# single explicit issue ( /megatask --issues 12 )  ⇒  1
```

### Phase 2 loop · Steps 1–2 — Select ready issues & assign tracks

Execution loop, driven cooperatively with `hooks/megatask-monitor.sh`:

1. **Select** — an issue is *ready* when every `blocked_by[]` entry is `status: "completed"` (PR
   merged, or created where the project merges via PR). Take them in the Phase 1 order.
2. **Assign tracks** — fill up to `parallel_tracks` worktrees; per issue:
   `git worktree add -b <type>/{issue#}-{slug} .worktrees/<group>/{issue#} origin/{base}` (base and
   slug per `skills/megatask/SKILL.md § Base Branch Resolution`, `§ Branch Naming`), write
   `workspace.json` (`isolation: "worktree"`, version 2.0) + `mkdir -p …/.context`, set status
   `in_progress` and assign `track`.

### Phase 2 loop · Step 3 — Launch the per-issue worktask

3. Delegate to `/worktask` for that issue, **both gates pre-bypassed**, stamping `PL0.metadata`:
   `{ stage:"PL", agent:"corpflow:product-manager", model:"opus", issue_number, track,
   workspace_path:".worktrees/<group>/{issue#}", isolation:"worktree",
   plan_gate:"bypass", decision_gate:"auto", fn_gate:"bypass", approved:"auto",
   megatask_group:"<group>",
   milestone:<N|null> }`. It then runs its normal stage loop unattended and milestone-agnostic
   (`commands/worktask.md`); the presence of `workspace.json` makes it auto-skip its own
   GitHub-issue publish — the parent milestone/issue is the canonical record.

#### Step 3 — standing directives in the per-issue prompt

Include these verbatim in every per-issue dispatch prompt. They are read once per run, which
documentation in a reference file is not.

- **Read `## Shared Seams` in the batch's registry issue before introducing any shared protocol,
  dependency-injection extension point, coordinator, or shared test assertion.** The registry issue
  is the batch's **foundation issue** — its sole level-0 issue (the only empty `blocked_by[]`) — or,
  when the batch has several level-0 issues or none, the milestone issue / orchestrator issue
  (`--issues` mode). Name that number explicitly; there is exactly one per batch. If the seam is
  registered, conform to the declaration exactly — labels and order included; if not, add an entry
  rather than inventing a parallel abstraction (`skills/megatask/SKILL.md § Shared-Seam Registry`).

##### Step 3 — conflict directives

- **Read `skills/megatask/references/git-integration.md § Conflict Recovery` before resolving a
  merge conflict.** Two rules apply regardless: (1) dependency-injection and coordinator-shaped
  conflicts are hand-resolved, never script-merged; (2) run a real build and the real tests after
  any conflict resolution, before pushing.

#### Step 3 — decision_gate and issue parking

`decision_gate:"auto"` is stamped because a batch is unattended: PL0 open questions route through
the Fable decision pass (`commands/worktask.md § Step A.4`) instead of parking on a human.
Escalate-class questions are still never auto-decided — they PARK that one issue while the batch
proceeds with the other unblocked issues.

##### Step 3 — parking mechanics

Parking rides the monitor's existing failure path, so it needs no new state: the per-issue worktask
writes `workspace.json.execution.status: "failed"` with `execution.reason: "parked_escalation"` and
an `escalation_parked` audit row (`commands/worktask.md § Step A.4 Escalation guard`);
`hooks/megatask-monitor.sh` settles it like any failed issue — track freed, dependents stay
`blocked`. The batch summary lists each parked issue with its unanswered escalate questions (told
apart by `execution.reason`) so the user can re-run it interactively, re-scope, or drop it.

### Phase 2 loop · Steps 4–6 — Monitor, completion, termination

4. **Monitor** — `hooks/megatask-monitor.sh` (SubagentStop/Stop) settles each finished issue and
   unblocks its dependents; each loop turn the orchestrator re-reads `orchestrator.json`, re-derives
   `parallel_tracks`, and assigns freed tracks (`skills/megatask/SKILL.md § Monitoring Loop`).
5. **Completion / errors** — success: PR with `Closes #{issue}`, track freed. Failure: `failed`,
   track freed, worktree preserved for debugging — a failed blocker leaves its dependents
   permanently `blocked`, so report them.
6. **Terminate** when no track is active and every issue is `completed`, `failed`, or `skipped`:
   print per-issue status + PR links, then `git worktree prune`.

## Output Format

`--dry-run` stops after the plan block; a live run appends progress and a batch summary:

~~~markdown
# Megatask: milestone <N> | issues <list> · <M> issues · <T> tracks

## Plan — issue | title | blockers | track | priority | worktree path
## Progress — per issue: stage reached, verdict, PR URL, worktree path
## Blocked — issues waiting, each naming the blocker issue it waits on
## Summary — merged / open / failed counts, plus follow-up issues filed
~~~

A dependency cycle or an unreadable ledger replaces everything after `## Plan` with
`## Halted — <cycle members or ledger error>`: no worktree is created and no issue is started.

## Relationship to /worktask and /milestone

`/milestone` writes issues carrying `Depends on` / `Blocks` / `P0`–`P3` → `/megatask` reads that
DAG and runs one `/worktask` per issue → `/worktask` executes ONE issue's pipeline (PL→…→ST),
milestone-agnostic and no longer accepting `--milestone:N`. Everything multi-issue (issue-set
resolution, DAG, track derivation, the monitoring hook, gate-bypass) is megatask's. Edge semantics
and status values: `skills/megatask/SKILL.md § Dependency & Blocker Resolution`,
`§ Status Transitions`.
