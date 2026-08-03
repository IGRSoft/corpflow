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
canonical plugin source directory (e.g. `/Users/<user>/Projects/igrsoft/company-worktask/`)
is a SIBLING repo on a different branch and MUST NOT be edited.

Rule: all `Edit`/`Write` calls MUST target paths under `git rev-parse --show-toplevel`
of the current session, NOT paths under the canonical plugin source.

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

#### Timing

The rename runs at the very start of planning — before PL0 exists, and therefore before
the plan-approval gate, the pipeline's only human checkpoint. If the operator later
declines the plan, the branch has already been renamed and nothing renames it back
automatically. `--auto=[plan]`, `--emergency`, and `/megatask` remove the approval gate
entirely, so this rename is the only pre-approval action any of them take.

#### Rollback

The mutation is local, reversible, and network-free: `git branch -m <original-name>`
restores it manually if a declined plan needs the old name back.

The step's own guard ladder stays the safety boundary — every arm exits 0:

| Guard | Behaviour |
|---|---|
| Name already conventional | no-op — a deliberate name is never churned |
| Upstream already tracked | no-op — renaming a pushed branch orphans the remote ref |
| On the integration branch | refuses |
| Target name already exists | no-op |
| Detached HEAD / not a repo | skipped |

Running at PL start, before any commit exists, retires the very hazard the ladder's
upstream-tracked and pushed-branch guards exist to catch — there is no push yet to
orphan.

#### Host mapping caveat

Surface this once; do not act on it. The host may map the workspace to its original
branch name, so a rename can leave that mapping stale. If the host's mapping matters
more than the branch name, the equivalent without a local rename is to push under the
target name (`git push origin <current>:<target>`) — the PR gets the conventional head
and the local branch is untouched. FN's own push already targets `facts.branch`
regardless (`agents/project-manager.md § Final FN steps`), so this caveat only matters
for a host that reads the *local* branch name directly.

## Task ID Namespacing

| Track | Task IDs |
|-------|----------|
| Track 1 | `t1-1`, `t1-2`, ... |
| Track N | `t{N}-1`, `t{N}-2`, ... |

See `../../megatask/SKILL.md` (§ Workspace Architecture) for full workspace documentation.

## DV Worktree Mechanics

Base-ref, background, and lifecycle rules for the DV stage worktree, extracted from `agents/developer.md § Worktree Mode` (Phase-4 diet). The developer agent keeps the D0.0 isolation gate + cwd-discipline path check inline and points here for the mechanics.

### Worktree Mode (DV)

All DV operations use worktree path prefix — isolation is always active. Use `EnterWorktree`/`ExitWorktree` tools to programmatically enter/leave worktree contexts. `EnterWorktree` accepts a `path` parameter to target a specific worktree directory when multiple exist; it can also **switch between Claude-managed worktrees mid-session** (re-target without `ExitWorktree` first). Build/test with `--package-path {workdir}`, git with `git -C {workdir}`. Stale worktrees are auto-cleaned (including those with untracked files); fresh worktree per delegation (no reuse of prior-session worktrees). For large repos, `worktree.sparsePaths` reduces checkout size. See `skills/megatask/SKILL.md`.

##### Base-ref resolution

Base-branch resolution is controlled by the `worktree.baseRef` setting: `head` (default — branch from local HEAD) or `fresh` (branch from base ref, drops unpushed work). The plugin assumes `head` semantics; do not set `fresh` without coordinating with workflow-engineer. `worktree.baseRef:"head"` resolves the *current* linked worktree's HEAD (not the main checkout's HEAD) when spawning subagents or `EnterWorktree` from inside a worktree — no diverged bases in nested-worktree flows.

##### Per-task base override

When the merge target is not the worktask default (e.g. shipping into `origin/release/v2` instead of `origin/master`), PL0 sets `task.metadata.base_ref: "origin/release/v2"`. The DV agent honours `task.metadata.base_ref` (when present) over the session-level `worktree.baseRef` for both `git diff` ranges in test selection (D2) and `EnterWorktree` base resolution; the orchestrator passes `--base-ref` to `EnterWorktree` when invoked from a higher-level dispatcher (see `skills/agent-coordination/references/headless-dispatch.md`). When neither is set, the `worktree.baseRef` setting governs.

##### Base-ref resolution order

PL0 also mirrors the detected branch to `state.json .metadata.base_ref` unconditionally, because shell helpers cannot read Task-System metadata. Every reader — DV, `fn-preflight.sh continuity`, `branch-name.sh` (via `branch-lib.sh resolve_base_ref`) — resolves through one order, highest first: `$FN_BASE_REF`, `state.json .metadata.base_ref`, `state.json .git.base_branch`, `workspace.json .git.base_branch`, `git symbolic-ref refs/remotes/origin/HEAD`, then **unresolved**. There is no hardcoded literal at the end of that chain; an unresolved base is reported and the caller degrades non-blocking. Canonical statement: `handoff-protocol.md § metadata.base_ref`.

##### Background & shared-checkout rules

Background subagents spawned via `claude agents` cannot escape their assigned worktree scope (the worktree-isolation guard covers them). Background-session dispatch recognises pre-existing git worktrees (e.g., Conductor `.context` workspaces, externally-managed worktree shells) instead of refusing to spawn with a duplicate-creation error — `Edit` is not blocked when `EnterWorktree` would have collided. A background session on a *shared* checkout (no isolated worktree of its own) is told upfront that edits are blocked until it runs `EnterWorktree` — the worktree contract is enforced at the start of the session rather than surfacing as a rejected edit mid-work.

##### Out-of-tree confirmation guard

`EnterWorktree` with a `path` **outside** `.claude/worktrees/` triggers a confirmation prompt. Unattended DV/resume flows should keep targets under `.claude/worktrees/`, pre-authorize via `bypassPermissions`/skip-permissions mode, or rely on the cwd-based pre-existing-worktree recognition above.

##### Background session lifecycle

Background agents launched via `/bg` or `←←` preserve the active permission mode across retire/wake — a permissive `bypassPermissions` parent does not revert to `default` after the daemon hibernates. Sub-agents in isolated worktrees automatically get Read/Edit access to their own worktree. Stalled subagents fail with a clear error after 10 minutes — surface and retry rather than waiting. Subagents resumed via `SendMessage` restore their explicit spawn `cwd` correctly. "Always allow" permission rules save at the repository root and persist across every worktree of that repo — a rule approved in one background/worktree session is not re-prompted in a sibling worktree.
