# Agent Teams Mode (Experimental)

When `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is enabled, megatask runs can use agent teams for true parallel issue execution instead of sequential Task-based orchestration. (`milestone-{N}` in the paths below is the `<group>` token — `milestone-{N}` in milestone mode, `issues-{shortid}` in array mode.)

> The session **is** the team (CC ≥ 2.1.178): there is one implicit per-session team, so teammates are spawned via `Agent(name: …)` — there is no separate team to create or tear down.

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
  2. Spawn one teammate per issue (max 5) via `Agent(name: …)` within the session's implicit team — no explicit team-creation step (the session is the team)
  3. Each teammate: issue context, workspace path, branch name
  4. Teammates execute independently: PL→DV→DR→QA→FN
  5. Lead monitors via shared task list
  6. Each teammate creates its own PR
  7. Lead synthesizes results; stop idle teammates via the `TeammateIdle`/`TaskCompleted` stop signal — no explicit team-teardown call
```

## Teammate Spawn Prompt Template

```
You are working on Issue #{issue_number}: {issue_title}

Worktree: .worktrees/milestone-{N}/{issue_number}
Branch: feature/{issue_number}-{slug} (already checked out in worktree)
Base: {base_branch}

IMPORTANT: All file operations must happen inside the worktree directory.
The worktree has its own copy of the source tree with the correct branch.
Use `git -C .worktrees/milestone-{N}/{issue_number}` for all git commands.

Execute the worktask for this issue:
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

Each teammate operates in its own worktree. This provides the strongest isolation:

- Each teammate has its own git branch checked out in a separate directory
- No branch-switching conflicts between teammates
- Each teammate's `.context/` lives inside its worktree
- Worktrees are cleaned up when each teammate completes its issue

This is the **recommended configuration** for milestone parallel execution when token budget allows it.

**EnterWorktree out-of-tree confirmation (2.1.206)**: megatask worktrees live at `${repo_root}/.worktrees/<group>/<issue>` — **outside** `.claude/worktrees/` — so on CC ≥ 2.1.206 an `EnterWorktree` `path` into a lane worktree triggers a confirmation prompt. Keep unattended lanes under auto/skip-permissions mode (which pre-authorizes the prompt), or rely on cwd-based pre-existing-worktree recognition (see `agents/developer.md:258`) (2.1.206).

## Hook Events for Team Monitoring

| Hook Event | Lead Action | Payload |
|------------|-------------|---------|
| `TeammateIdle` | Assign next pending issue or clean up team | `agent_id`, `agent_type` |
| `TaskCompleted` | Update orchestrator.json, check milestone progress | `agent_id`, `agent_type` |

Handlers can return `{"continue": false, "stopReason": "..."}` to stop a teammate when its issue is complete or when milestone budget is exhausted.

### Teammate lifecycle notes

> Background tasks launched by a teammate (e.g. long test runs) survive the teammate finishing its turn (CC ≥ 2.1.183) — a lane teammate can kick off long-running work without it dying at the turn boundary.

> **Teammate failure & wake semantics (CC ≥ 2.1.198/2.1.199)**: a teammate that dies on an API error now reports **`failed`** to the lead (no more silently-vanished lanes), messaging a stuck teammate **wakes it to retry immediately**, and `SendMessage` detects a re-spawned teammate reusing a dead teammate's name and asks the caller to retarget. Lead recovery loop: on `failed` → re-spawn the lane; on stalled → `SendMessage` nudge first, re-spawn only if the nudge doesn't wake it. tmux/pane teammates inherit the leader's `--effort` (CC ≥ 2.1.186; `teammateMode: "iterm2"` is an available backend).

### Worktree reliability notes

> **Worktree reliability (CC 2.1.187→2.1.202)**: project-scoped plugins now load correctly inside git worktrees of the same repository (CC ≥ 2.1.200) — lane teammates see the full plugin skill set in their worktrees; locked `.git/worktrees/` registrations from killed teammates are cleaned automatically (CC ≥ 2.1.187); and the resume picker no longer takes minutes in repositories with many worktrees (CC ≥ 2.1.202). Teammates that finish code work in a worktree via `claude agents` auto commit/push/open a **draft PR** (CC ≥ 2.1.198) — aligned with step 6 above and by-design in lanes, since megatask stamps per-issue `fn_gate: "bypass"`.

Background completion notifications include `worktreePath` and `worktreeBranch` fields, enabling the orchestrator to locate the correct worktree for each teammate.

### Agent-teams reliability (2.1.203/2.1.207)

> **Mailbox crash-loop fix (2.1.207)**: a malformed teammate mailbox message no longer crash-loops an agent team — previously it errored every second until the mailbox file was manually deleted. **Parent-checkout isolation (2.1.203)**: worktree-isolated subagents no longer run shell commands in the parent checkout, so a lane teammate's `Bash` stays inside its own worktree.
