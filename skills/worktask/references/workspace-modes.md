# Workspace Modes — detection & isolation rules

Read when running in megatask/worktree mode, inside a Conductor workspace clone, or on any cwd↔workspace_path mismatch (from `skills/worktask/SKILL.md § Workspace Mode` stub). In a megatask run (`/megatask N`), each ticket executes in an isolated workspace.

## Workspace Detection

```typescript
const task = TaskGet({ taskId: currentTaskId });
const workspacePath = task.metadata?.workspace_path;
const isolation = task.metadata?.isolation;  // always 'worktree' for file-writing stages

if (isolation === 'worktree') {
  // WORKTREE MODE: workspace_path IS the worktree directory
  // All git operations happen inside the worktree
  // .context/ lives inside the worktree alongside source files
  const contextPath = `${workspacePath}/.context`;
} else {
  // STANDARD MODE: main checkout — orchestrator and non-isolated stages
  const contextPath = '.context';
}
```

## Path Resolution

| Mode | Base Path | Git Operations | Source Isolation |
|------|-----------|----------------|------------------|
| Standard | `.context/` (main checkout) | Main working directory | None (orchestrator/non-isolated stages) |
| Worktree | `.worktrees/milestone-{N}/{issue#}/.context/` | Dedicated worktree | Full (git + artifacts) |

## Conductor Workspace Topology

When CC spawns a worktask session inside a Conductor-managed workspace clone
(e.g. `/Users/<user>/conductor/workspaces/<plugin>/<workspace-id>/`), the
canonical plugin source directory (e.g. `/Users/<user>/Projects/corpflow/`)
is a SIBLING repo on a different branch and MUST NOT be edited.

Rule: all `Edit`/`Write` calls MUST target paths under `git rev-parse --show-toplevel`
of the current session, NOT paths under the canonical plugin source.

### Sibling-worktree hazard

The rule above defends against a sibling **clone** and is silent about a sibling **worktree** —
and that gap is not academic. When the harness pins the session to a stale linked worktree of a
*different* clone, `git rev-parse --show-toplevel` answers with that worktree. The agent then
obeys the rule perfectly, writes every edit under the resolved root, and lands the entire stage in
a tree nobody is watching: `git diff` in the real workspace shows nothing, and the stage reports
success.

#### Why every existing check passes on the wrong tree

| Check | Why it passes |
|---|---|
| D0 workspace-root self-check | `--show-toplevel` returns the stale tree, so the recorded root and the prompt paths agree |
| D0.0 worktree isolation | a stale worktree **is** a linked worktree — genuinely isolated |
| the rule above | edits do target the resolved toplevel |

The missing predicate is *assignment*: the resolved root must equal the root the stage was
**dispatched against** (`task.metadata.workspace_path`). That is what
`skills/worktask/scripts/dv-tree-preflight.sh` asserts and nothing else does.
**Isolation ≠ assignment.**

### Orchestrator enforcement

1. Before every `Task()` delegation, resolve `WORKSPACE_ROOT = $(git rev-parse --show-toplevel)`.
2. Inject `WORKSPACE_ROOT=<path>` as the FIRST LINE of the stage prompt banner (section [7]).
3. Never allow absolute paths from outside `WORKSPACE_ROOT` in stage prompts — rewrite them as `$WORKSPACE_ROOT/<relative>`.

Failure mode: edits in the sibling repo land on the wrong branch, are not visible to `git diff` in the workspace, require manual `cp` surgery, and corrupt the source repo's working tree.

### Branch naming under a host workspace

A host that provisions the workspace also names its branch, and that name carries no
ticket and no type (Conductor uses `<city>-v<n>` — `amman-v1`, `perth-v2`). Such a
branch reaching `gh pr create` unchanged produces a PR whose head says nothing about
the work.

#### Host session authorization

Conductor additionally injects a session rule: *"Do not rename the current branch
unless the user explicitly tells you to do so."* **Invoking `/worktask` satisfies that
condition.** A conventionally-named branch and a ticket-referencing PR are part of what
the pipeline was asked to deliver, so the PL-stage naming step
(`skills/worktask/scripts/branch-name.sh`, run once at the very start of planning — see
`skills/shared/git-conventions.md § Branch Naming`) is authorized work rather than an
unprompted change. Neither the orchestrator nor PL should suspend the pipeline to
re-ask. This runs at PL start now, not immediately before FN's push — see
`agents/project-manager.md § Branch naming is a PL-stage concern` for how FN reads the
resulting name (`facts.branch`) instead of re-deriving or re-renaming it.

#### Scope of the authorization

It covers exactly the rename `branch-name.sh` performs, and nothing further — never
deleting branches, force-pushing, or rewriting history. **Caveat, stated plainly rather
than promised as enforced:** the only discriminator the step has is
`branch_is_conventional` (does the name already match `<type>/[<ticket>-]<slug>`?). A human-chosen
name that happens not to match — e.g. `spike-oauth-poc` — is indistinguishable from a
host-provisioned one and **will** be renamed; there is no mechanism that detects "the
user named this deliberately" versus "the host assigned this by default". If that
matters in your workflow, rename to a conventional form yourself before invoking
`/worktask`, or accept the rename as part of what the pipeline does.

#### Scope of the authorization — R6 widens the caveat

Since R6 the host-workspace arm **widens** this caveat rather than narrowing it: a linked worktree is
renamed too, so a deliberate name is indistinguishable from a host-assigned one in *every*
checkout, not just plain ones. `BRANCH_NAME_WORKTREE_RENAME=0` restores the previous
defer-to-host behaviour inside worktrees.

#### Timing

The rename runs at the very start of planning — before PL0 exists, and therefore before
the plan-approval gate, the pipeline's only human checkpoint. If the operator later
declines the plan, the branch has already been renamed and nothing renames it back
automatically. `--auto=[plan]`, `--emergency`, and `/megatask` remove the approval gate
entirely, so this rename is the only pre-approval action any of them take. R6 widens *which
runs* take it: the rename now fires inside linked worktrees too, so the set is every checkout
with a non-conventional name rather than plain checkouts only. `/megatask` and `--emergency`
are unaffected (they self-disable at the first ladder position); `--auto=[plan]` is the exposed
combination, and `BRANCH_NAME_WORKTREE_RENAME=0` is the mitigation.

#### Rollback

The mutation is local, reversible, and network-free: `git branch -m <original-name>`
restores it manually if a declined plan needs the old name back.

#### Guard ladder — two names, one per decision

Every arm exits 0 and returns two names: `branch=<name>` is the LOCAL branch after the run
(the final stdout line), `target_branch=` is what the **remote** branch — the PR head —
should carry. Blocking the rename never blocks the target.

| Guard | Local branch | `target_branch=` |
|---|---|---|
| Already conventional | no-op — a deliberate name is never churned | empty — `branch=` is the answer |
| Upstream tracked | no-op — a rename orphans the remote ref | derived |
| On the integration branch | refuses | empty — never a PR head |
| Target name exists | no-op | derived |
| **Host workspace (linked worktree)** | **renamed (default) — `BRANCH_NAME_WORKTREE_RENAME=0` keeps the host's name** | **derived** |
| jq unavailable | no-op — batch scope unknowable | derived if `--goal` passed |
| Detached HEAD / no repo / batch routing | skipped | empty |

Running at PL start retires the hazard the upstream guards catch — no push yet to orphan.

#### Host mapping — updated, not preserved

Inside a linked worktree the naming step **renames the local branch**, like any other
checkout, so `branch=` and `target_branch=` agree. The host's branch↔workspace mapping is
updated by that rename — deliberately: a host-assigned placeholder is not a name worth
preserving, and a host may rename the branch again mid-run without telling the pipeline
(observed: Conductor renamed a branch from `cape-town` to a chat-topic slug mid-run, with no
notification and no audit row). Set `BRANCH_NAME_WORKTREE_RENAME=0` to restore the previous
defer-to-host behaviour, in which the local name is kept and only `target_branch=` is derived,
auditing `branch_renamed / skipped` with `reason: host_workspace_worktree`.

#### Host mapping — detection is unchanged, only what it gates

The detection is unchanged — only what it gates. A linked worktree is the shape every
worktree-based host provisions, detected as `git rev-parse --git-dir != --git-common-dir`,
which is the only signal a host workspace reliably leaves (Conductor writes no
`workspace.json` in `$PWD`, so none of `fn_batch_scope`'s five signals fire).

The rename is disclosed on stdout at the moment it happens, naming both the re-sync
consequence and the opt-out, and repeated in the Step A.5 plan-gate summary.

#### Host mapping — where the target lands

The orchestrator stamps that target into `facts.branch` (`commands/worktask.md § Step 3c —
which of the two names gets stamped`) and FN's existing
`git push -u origin HEAD:refs/heads/<facts.branch>` gives the PR a conventional head
(`agents/project-manager.md § Final FN steps`).

On the **default** worktree path the two names now agree, so there is no divergence left to
reconcile. Divergence remains designed on the **opt-out** path and on the `upstream_tracked`,
`target_exists` and `jq_unavailable` arms — that is where this mechanism still applies.

#### Host mapping — divergence is now observed

Divergence is now *observed* rather than merely tolerated: `fn-preflight.sh branch-divergence`
classes it `expected` (any of the arms above, or an R4 refinement) or `third_party` (something
outside the pipeline renamed the branch after the naming step). Only `third_party` is surfaced
at the FN gate. The comparison base is the `to` of the last `branch_renamed / ok` row — not
`facts.branch` — which is what keeps an R4 refinement from ever looking like an external rename.

## Task ID Namespacing

| Track | Task IDs |
|-------|----------|
| Track 1 | `t1-1`, `t1-2`, ... |
| Track N | `t{N}-1`, `t{N}-2`, ... |

See `../../megatask/SKILL.md` (§ Workspace Architecture) for full workspace documentation.

## DV Worktree Mechanics

Base-ref, background, and lifecycle rules for the DV stage worktree, extracted from `agents/developer.md § Worktree Mode` (Phase-4 diet). The developer agent keeps the D0.0 isolation gate + cwd-discipline path check inline and points here for the mechanics.

### Worktree Mode (DV)

All DV operations use worktree path prefix — isolation is always active. Use `EnterWorktree`/`ExitWorktree` tools to programmatically enter/leave worktree contexts. `EnterWorktree` accepts a `path` parameter to target a specific worktree directory when multiple exist; it can also **switch between Claude-managed worktrees mid-session** (re-target without `ExitWorktree` first). Build/test with `--package-path {workdir}`, git with `git -C {workdir}`. For large repos, `worktree.sparsePaths` reduces checkout size. See `skills/megatask/SKILL.md`.

##### Do not rely on auto-cleanup

This document previously stated that stale worktrees are auto-cleaned and that each delegation
gets a fresh one with no reuse of prior-session worktrees. A run disproved it: a DV stage was
pinned to a prior session's worktree, of a different clone, and wrote nothing for a full stage
cycle. Treat a fresh worktree as the *intent* and assert it — run `dv-tree-preflight.sh
--assigned` (D0.0a) rather than assuming the lifecycle held.

##### Base-ref resolution

Base-branch resolution is controlled by the `worktree.baseRef` setting: `head` (default — branch from local HEAD) or `fresh` (branch from base ref, drops unpushed work). The plugin assumes `head` semantics; do not set `fresh` without coordinating with workflow-engineer. `worktree.baseRef:"head"` resolves the *current* linked worktree's HEAD (not the main checkout's HEAD) when spawning subagents or `EnterWorktree` from inside a worktree — no diverged bases in nested-worktree flows.

##### Per-task base override

When the merge target is not the worktask default (e.g. shipping into `origin/release/v2` instead of `origin/master`), PL0 sets `task.metadata.base_ref: "origin/release/v2"`. The DV agent honours `task.metadata.base_ref` (when present) over the session-level `worktree.baseRef` for both `git diff` ranges in test selection (D2) and `EnterWorktree` base resolution; the orchestrator passes `--base-ref` to `EnterWorktree` when invoked from a higher-level dispatcher (see `skills/agent-coordination/references/headless-dispatch.md`). When neither is set, the `worktree.baseRef` setting governs.

##### Base-ref resolution order

PL0 also mirrors the detected branch to `state.json .metadata.base_ref` unconditionally, because shell helpers cannot read Task-System metadata. Every reader — DV, `fn-preflight.sh continuity`, `branch-name.sh` (via `branch-lib.sh resolve_base_ref`) — resolves through one order, highest first: `$FN_BASE_REF`, `state.json .metadata.base_ref`, `workspace.json .git.base_branch`, `git symbolic-ref refs/remotes/origin/HEAD`, then **unresolved**. There is no hardcoded literal at the end of that chain; an unresolved base is reported and the caller degrades non-blocking. Canonical statement: `handoff-protocol.md § metadata.base_ref`.

##### Background & shared-checkout rules

Background subagents spawned via `claude agents` cannot escape their assigned worktree scope (the worktree-isolation guard covers them). Background-session dispatch recognises pre-existing git worktrees (e.g., Conductor `.context` workspaces, externally-managed worktree shells) instead of refusing to spawn with a duplicate-creation error — `Edit` is not blocked when `EnterWorktree` would have collided. A background session on a *shared* checkout (no isolated worktree of its own) is told upfront that edits are blocked until it runs `EnterWorktree` — the worktree contract is enforced at the start of the session rather than surfacing as a rejected edit mid-work.

##### Out-of-tree confirmation guard

`EnterWorktree` with a `path` **outside** `.claude/worktrees/` triggers a confirmation prompt. Unattended DV/resume flows should keep targets under `.claude/worktrees/`, pre-authorize via `bypassPermissions`/skip-permissions mode, or rely on the cwd-based pre-existing-worktree recognition above.

##### Background session lifecycle

Background agents launched via `/bg` or `←←` preserve the active permission mode across retire/wake — a permissive `bypassPermissions` parent does not revert to `default` after the daemon hibernates. Sub-agents in isolated worktrees automatically get Read/Edit access to their own worktree. Stalled subagents fail with a clear error after 10 minutes — surface and retry rather than waiting. Subagents resumed via `SendMessage` restore their explicit spawn `cwd` correctly. "Always allow" permission rules save at the repository root and persist across every worktree of that repo — a rule approved in one background/worktree session is not re-prompted in a sibling worktree.
