# Agent Teams Mode (Experimental)

With `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, a megatask run can execute issues as parallel
teammates instead of sequential Task-based orchestration. The session **is** the team — one implicit
per-session team, teammates spawned via `Agent(name: …)`, nothing to create or tear down. (`<group>`
below is `milestone-{N}` in milestone mode, `issues-{shortid}` in array mode.)

## When to Use Agent Teams

| Batch shape | Mode |
|---|---|
| Issues truly independent, clear acceptance criteria in the body, 3–5 per milestone, token budget allows N context windows | agent teams |
| Issues depend on each other, need shared context, must land sequentially, or the token budget is constrained | Task-based orchestrator (default) |

The trade-off: the orchestrator runs sequential stages over parallel tracks in one context window
(cheaper, artifact-mediated via `.context/` + `workspace.json`); teams give each issue an independent
context and direct inter-teammate messaging at N× the tokens. Full comparison:
`../../agent-coordination/references/hook-monitoring.md § Agent Teams vs Subagents`.

## Agent Teams Milestone Pattern

```
Lead Session (workflow-engineer):
  1. Fetch milestone issues; spawn one teammate per issue (max 5) via `Agent(name: …)`
  2. Give each teammate its issue context, workspace path and branch name (template below)
  3. Teammates execute independently (PL→DV→DR→QA→FN); each creates its own PR
  4. Lead monitors the shared task list, synthesizes results, and stops idle teammates
     via the `TeammateIdle`/`TaskCompleted` stop signal
```

## Teammate Spawn Prompt Template

```
You are working on Issue #{issue_number}: {issue_title}

Worktree: .worktrees/milestone-{N}/{issue_number}
Branch: <type>/{issue_number}-{slug} (already checked out in worktree)
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

The **recommended configuration** when the token budget allows it: each teammate gets its own branch
in its own directory with its own `.context/` — no branch-switching conflicts — and the worktree is
removed when its issue completes.

**EnterWorktree out-of-tree confirmation**: megatask worktrees live at
`${repo_root}/.worktrees/<group>/<issue>` — **outside** `.claude/worktrees/` — so an `EnterWorktree`
`path` into a lane worktree triggers a confirmation prompt. Keep unattended lanes under
auto/skip-permissions mode (which pre-authorizes the prompt), or rely on cwd-based
pre-existing-worktree recognition (see `agents/developer.md:262`).

## Hook Events for Team Monitoring

| Hook Event | Lead Action |
|------------|-------------|
| `TeammateIdle` | Assign next pending issue or clean up team |
| `TaskCompleted` | Update orchestrator.json, check milestone progress |

Payload fields and the `{"continue": false, "stopReason": "..."}` stop response:
`../../agent-coordination/references/hook-monitoring.md § Agent Teams Lifecycle Hooks`.

### Teammate lifecycle notes

> - Background tasks a teammate launches survive it finishing its turn.
> - A teammate that dies on an API error reports **`failed`** to the lead — no silently-vanished
>   lanes. Recovery: re-spawn on `failed`; on stalled, `SendMessage` first (a message wakes a stuck
>   teammate to retry immediately), re-spawn only if the nudge does not wake it.
> - `SendMessage` asks the caller to retarget when a re-spawned teammate reuses a dead one's name;
>   a stopping teammate sends no duplicate idle notifications.
> - A re-spawned in-process teammate never takes tools or a system prompt from a same-named agent
>   file in a folder you have not trusted, so re-spawn-on-`failed` cannot pick up an untrusted
>   checkout's definition.
> - tmux/pane teammates inherit the leader's `--effort` (`teammateMode: "iterm2"` available), and
>   completion notifications carry `worktreePath`/`worktreeBranch` to locate each lane's worktree.

#### Teammate lifecycle — results and visibility

> - A teammate's **final answer arrives in the idle notification itself**, not a content-free
>   "available" notice. Read the lane's result off the notification; a follow-up `SendMessage`
>   asking what it concluded is a wasted round-trip per lane.
> - Live teammates now appear in `ListAgents`/`claude agents --json`, so a lead resuming mid-batch
>   can use the same pre-check the stage loop uses
>   (`../../worktask/references/resume.md § Step 0 notes — own-name & teammate visibility`)
>   instead of relying on `TeammateIdle` plus re-spawn-on-`failed` alone.
> - The "Default teammate model" setting is gone: teammates run the leader's model unless the
>   spawn names one. Pin a lane's tier at `Agent(name: …, model: …)`, never in config.

### Worktree and mailbox reliability

> - Project-scoped plugins load inside worktrees of the same repository — lane teammates see the
>   full skill set; the resume picker stays fast with many worktrees.
> - A **running** backgrounded lane holds its worktree's lock, so cleanup and `git worktree remove`
>   leave it alone — lane teardown needs no "is anyone still in there?" guard. The **periodic
>   sweep** of locked `.git/worktrees/` registrations is the backstop for a *killed* teammate's
>   stale lock. A malformed mailbox message does not crash-loop a team.
> - A background session and its subagents can edit files inside a worktree the session created
>   itself with `git worktree add` — previously blocked by the isolation check, which stalled the
>   lane. Parent-checkout isolation below is unaffected.
> - Concurrent sessions do not revert each other's `~/.claude.json`, so workspace trust and
>   MCP/project state hold under fan-out — which keeps agent-frontmatter hooks firing in every lane
>   (`../../agent-coordination/references/hook-monitoring.md § Workspace trust is a precondition for
>   agent-frontmatter hooks`).
> - Deleting a `claude agents` session whose worktree has unpushed commits names the branch and
>   commit count, and deleting again discards the worktree — lane cleanup pushes or salvages those
>   commits before the second delete.

#### Worktree isolation guarantees

> - `claude agents` teammates finishing code work in a worktree auto commit/push/open a **draft
>   PR** — step 6 above, by design in lanes, since megatask stamps `fn_gate: "bypass"`.
> - **Parent-checkout isolation** (runtime-enforced, CC 2.1.222): worktree-isolated sessions and
>   their subagents cannot run destructive git against the main checkout (file edits and `Bash`
>   alike) — a runtime guarantee, not a convention the agent must observe.
