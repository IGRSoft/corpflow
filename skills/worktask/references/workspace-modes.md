# Workspace Modes — detection & isolation rules

Read when running in milestone/worktree mode, inside a Conductor workspace clone, or on any cwd↔workspace_path mismatch (from `skills/worktask/SKILL.md § Workspace Mode` stub). When using `--milestone:N`, each ticket executes in an isolated workspace.

## Workspace Detection

```typescript
const task = TaskGet({ taskId: currentTaskId });
const workspacePath = task.metadata?.workspace_path;
const isolation = task.metadata?.isolation;  // 'worktree' or undefined

if (isolation === 'worktree') {
  // WORKTREE MODE: workspace_path IS the worktree directory
  // All git operations happen inside the worktree
  // .context/ lives inside the worktree alongside source files
  const contextPath = `${workspacePath}/.context`;
} else if (workspacePath) {
  // LEGACY WORKSPACE MODE: directory-based artifact isolation only
  const contextPath = `${workspacePath}/.context`;
} else {
  // STANDARD MODE: project root
  const contextPath = '.context';
}
```

## Path Resolution

| Mode | Base Path | Git Operations | Source Isolation |
|------|-----------|----------------|------------------|
| Standard | `.context/` | Main working directory | None |
| Workspace (legacy) | `.workspaces/milestone-{N}/{issue#}/.context/` | Shared working directory | Artifacts only |
| Worktree | `.worktrees/milestone-{N}/{issue#}/.context/` | Dedicated worktree | Full (git + artifacts) |

## Conductor Workspace Topology

When CC spawns a worktask session inside a Conductor-managed workspace clone
(e.g. `/Users/<user>/conductor/workspaces/<plugin>/<workspace-id>/`), the
canonical plugin source directory (e.g. `/Users/<user>/Projects/igrsoft/company-worktask/`)
is a SIBLING repo on a different branch and MUST NOT be edited.

Rule: all `Edit`/`Write` calls MUST target paths under `git rev-parse --show-toplevel`
of the current session, NOT paths under the canonical plugin source.

Orchestrator enforcement:
1. Before every `Task()` delegation, resolve `WORKSPACE_ROOT = $(git rev-parse --show-toplevel)`.
2. Inject `WORKSPACE_ROOT=<path>` as the FIRST LINE of the stage prompt banner (section [7]).
3. Never allow absolute paths from outside `WORKSPACE_ROOT` in stage prompts — rewrite them as `$WORKSPACE_ROOT/<relative>`.

Failure mode: edits in the sibling repo land on the wrong branch, are not visible to `git diff` in the workspace, require manual `cp` surgery, and corrupt the source repo's working tree.

## Task ID Namespacing

| Track | Task IDs |
|-------|----------|
| Track 1 | `t1-1`, `t1-2`, ... |
| Track N | `t{N}-1`, `t{N}-2`, ... |

See `skills/worktask-milestone/SKILL.md` for full workspace documentation.
