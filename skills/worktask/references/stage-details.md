# Stage Details & Agent Teams Integration

## Default Model Assignments

| Stage | Model | Rationale |
|-------|-------|-----------|
| PL | opus | Planning and generation |
| AR | opus | Complex architecture decisions |
| TL | sonnet | Coordination and delegation |
| DV | opus | Implementation depth |
| DR | sonnet | Code review (read-only) |
| SR | opus | Security analysis complexity |
| QA | sonnet | Test strategy decisions, multimodal design comparison, 19-tool orchestration |
| DC | haiku | Documentation generation |
| RE | haiku | Release operations |
| FN | opus | Final coordination |
| ST | sonnet | Business review |

Override via Task `model` parameter when stage complexity warrants it. See `cost-optimization.md` for cost tiers.

## Agent Responsibilities

| Stage | Agent | Key Tasks |
|-------|-------|-----------|
| PL | product-manager | Requirements, acceptance criteria, test strategy, assess complexity, create subsequent stage tasks with `metadata.agent` |
| AR | software-architector | Technical design, test architecture, validate PL sizing |
| TL | team-lead | Coordinate approach, allocate resources, split DV into parallel streams when warranted |
| DV | developer | Implement solution + unit tests, run formatter, verify build + scoped tests pass (tests covering changed code; full-suite regression deferred to QA) |
| DR | technical-lead | Invoke /code-review-dev, produce developer-review.md |
| SR | security-reviewer | OWASP audit, vulnerability scan |
| QA | qa-engineer | Test plan, execute tests, all tests pass |
| DC | technical-writer | Update docs, README, ARCHITECTURE |
| RE | release-engineer | Version bump, changelog, deployment readiness |
| FN | project-manager | Final builds, deployment |
| ST | stakeholder | Final acceptance |
| IR | incident-responder | Triage, classify severity, coordinate response |

## Constitutional Integration

Use `--ethics-review` for high-risk features:

```
PL → ET → AR → TL → DV → DR → QA → DC → FN → ST
```

**High-risk indicators**: User tracking, algorithmic recommendations, financial transactions, content moderation, AI/ML decisions, children/vulnerable populations.

See `claude-constitution.md` for full principles.

## Agent Teams Integration (Experimental)

When `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is enabled, the worktask system can leverage agent teams for milestone mode parallel execution.

### Enabling

Add to project `settings.json`:

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

### Hook Events for Worktask Monitoring

| Hook Event | Use Case | Payload |
|------------|----------|---------|
| `SubagentStart` | Log stage agent activation | `agent_id`, `agent_type` |
| `SubagentStop` | Detect stage agent completion | `agent_id`, `agent_type` |
| `TeammateIdle` | Assign next task to idle teammate (agent teams only) | `agent_id`, `agent_type` |
| `TaskCompleted` | Trigger dependent stages, update orchestrator (agent teams only) | `agent_id`, `agent_type` |

`TeammateIdle`/`TaskCompleted` handlers can return `{"continue": false, "stopReason": "..."}` to stop a teammate. Hooks also support `"type": "http"` for external monitoring.

> `SessionEnd` hook timeout is configurable via `CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS`. Useful for worktasks requiring cleanup time (e.g., worktree pruning).

See `agent-coordination.md § Hook-Based Stage Monitoring` for configuration patterns.

### Limitations

- Teammates cannot spawn sub-agents or teams (runtime-enforced)
- No session resumption for in-process teammates
- Higher token cost than Task-based orchestration
- Maximum one team per session

### Worktree + Agent Teams

When both `--worktree` and agent teams are enabled, each teammate operates in its own worktree. This provides the strongest isolation — each teammate has its own branch, working directory, and `.context/`. This is the recommended configuration for milestone parallel execution when token budget allows.

> Project configs and auto-memory are automatically shared across all git worktrees of the same repo. No per-worktree configuration duplication needed.

See `../../worktask-milestone/SKILL.md § Agent Teams Mode` for parallel execution patterns.
See `agent-coordination.md § Agent Teams vs Subagents` for comparison.
