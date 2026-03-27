# Agent Teams Mode (Experimental)

When `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is enabled, milestone workflows can use agent teams for true parallel issue execution instead of sequential Task-based orchestration.

## Architecture Comparison

| Aspect | Task-Based Orchestrator | Agent Teams |
|--------|------------------------|-------------|
| Parallelism | Sequential stages, parallel tracks via orchestrator.json | True parallel: each issue is an independent teammate |
| Communication | Via artifacts in .context/ and workspace.json | Direct inter-teammate messaging |
| Context | Shared context window (compressed handoffs) | Independent context per teammate |
| Token cost | Lower (single context window) | Higher (N context windows) |
| Best for | Complex issues with dependencies | Independent issues with clear scope |

## When to Use Agent Teams

**Use agent teams when**:
- Issues are truly independent (no cross-issue dependencies)
- Issues have clear acceptance criteria in the issue body
- Milestone has 3-5 issues (optimal team size)
- Token budget allows parallel sessions

**Stay with Task-based orchestrator when**:
- Issues depend on each other
- Context sharing between issues matters
- Token budget is constrained
- Issues require sequential implementation

## Agent Teams Milestone Pattern

```
Lead Session (workflow-engineer):
  1. Fetch milestone issues
  2. Create agent team with one teammate per issue (max 5)
  3. Each teammate: issue context, workspace path, branch name
  4. Teammates execute independently: PL→DV→QA→FN
  5. Lead monitors via shared task list
  6. Each teammate creates its own PR
  7. Lead synthesizes results and cleans up team
```

## Teammate Spawn Prompt Template

### Legacy Mode

```
You are working on Issue #{issue_number}: {issue_title}

Workspace: .workspaces/milestone-{N}/{issue_number}
Branch: feature/{issue_number}-{slug}
Base: {base_branch}

Execute the workflow for this issue:
1. Create .context/ directory in your workspace
2. PL: Plan requirements from the issue body
3. DV: Implement the solution
4. QA: Test the implementation
5. FN: Commit, push, and create PR with "Closes #{issue_number}"

Write all artifacts to your workspace .context/ directory.

Issue body:
{issue_body}
```

### Worktree Mode

```
You are working on Issue #{issue_number}: {issue_title}

Worktree: .worktrees/milestone-{N}/{issue_number}
Branch: feature/{issue_number}-{slug} (already checked out in worktree)
Base: {base_branch}

IMPORTANT: All file operations must happen inside the worktree directory.
The worktree has its own copy of the source tree with the correct branch.
Use `git -C .worktrees/milestone-{N}/{issue_number}` for all git commands.

Execute the workflow for this issue:
1. All artifacts go to .worktrees/milestone-{N}/{issue_number}/.context/
2. PL: Plan requirements from the issue body
3. DV: Implement the solution (source files are in the worktree)
4. QA: Test the implementation (run tests from worktree directory)
5. FN: Commit, push, and create PR with "Closes #{issue_number}"
6. Cleanup: git worktree remove .worktrees/milestone-{N}/{issue_number}

Issue body:
{issue_body}
```

## Worktree + Agent Teams

When both `--worktree` and agent teams are enabled, each teammate operates in its own worktree. This provides the strongest isolation:

- Each teammate has its own git branch checked out in a separate directory
- No branch-switching conflicts between teammates
- Each teammate's `.context/` lives inside its worktree
- Worktrees are cleaned up when each teammate completes its issue

This is the **recommended configuration** for milestone parallel execution when token budget allows it.

## Hook Events for Team Monitoring

| Hook Event | Lead Action | Payload |
|------------|-------------|---------|
| `TeammateIdle` | Assign next pending issue or clean up team | `agent_id`, `agent_type` |
| `TaskCompleted` | Update orchestrator.json, check milestone progress | `agent_id`, `agent_type` |

Handlers can return `{"continue": false, "stopReason": "..."}` to stop a teammate when its issue is complete or when milestone budget is exhausted.

Background completion notifications include `worktreePath` and `worktreeBranch` fields, enabling the orchestrator to locate the correct worktree for each teammate.
