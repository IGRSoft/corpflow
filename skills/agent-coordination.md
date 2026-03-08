---
name: agent-coordination
description: Patterns for multi-agent coordination, handoffs, parallel execution, and error escalation.
---

# Agent Coordination

Patterns for coordinating agents across workflow stages, managing handoffs, and handling errors.

**Stage codes and agents**: See `shared/stage-codes.md`
**Task System tools**: See `shared/task-system.md`

## Handoff Protocol

```
1. Current agent completes work
2. Updates task: TaskUpdate({ taskId: "X", status: "completed" })
3. Creates stage artifact (e.g., planning.md)
4. Writes compressed handoff (50-100 tokens)
5. Next agent starts: TaskUpdate({ taskId: "Y", status: "in_progress" })
```

### Handoff Checklist

- [ ] Stage objectives completed
- [ ] Artifact created in `.context/`
- [ ] Task status updated
- [ ] Handoff summary prepared
- [ ] Open questions documented

## Error Handling

### Error Classification

| Type | Retry? | Escalate To |
|------|--------|-------------|
| Transient (API, network) | Yes (3x) | None |
| Logic (bug, wrong approach) | Yes (2x) | Same agent |
| Dependency (missing input) | No | Previous stage |
| Requirements (unclear) | No | PL stage |
| Architecture (design flaw) | No | AR stage |

### Escalation Chains

```
10-stage: ST→FN→RE→DC→QA→SR→DV→TL→AR→PL→USER
8-stage:  ST→FN→DC→QA→DV→TL→AR→PL→USER
Emergency: FN→RE→QA→DV→IR→USER
Ethics: Any→ethics-reviewer→stakeholder→USER
```

### Error Documentation

Create `.context/error.md`:
```markdown
## [STAGE] Error - [TIMESTAMP]
**Classification**: [type]
**Retry Count**: [X/max]
### Problem
[Description]
### Resolution Path
- [ ] [Action]
```

## Parallel Execution

### Safe Combinations

| Pattern | Stages | Benefit |
|---------|--------|---------|
| Docs + QA | DC + QA | 30-40% time savings |
| Early Docs | DC during DV | Docs ready sooner |

### Worktree-Enabled Parallelism

With `--worktree` mode, additional parallelism becomes safe because each issue has its own working directory:

| Pattern | Without Worktree | With Worktree |
|---------|------------------|---------------|
| Parallel issues in milestone | Artifact-only isolation (branch conflicts) | Full source isolation per issue |
| QA + DC parallel | Safe (mostly read-only) | Safe (each has own copy) |
| Multiple DV stages across issues | **NOT SAFE** (shared source tree) | **SAFE** (separate worktrees) |
| Agent teams + milestone issues | Risky (branch switching conflicts) | **Recommended** |

> When two agents need to modify source files simultaneously (e.g., parallel DV stages for different milestone issues), worktree mode prevents conflicts by giving each a separate working directory and branch.

### Never Parallelize

- AR before PL (needs requirements)
- DV before TL (needs coordination)
- QA before DV (can't test unwritten code)

## Agent Selection

### Sub-Task Delegation

| Sub-Task | Delegate To | Model |
|----------|-------------|-------|
| Status check | Self | haiku |
| Code implementation | developer | sonnet |
| Architecture question | software-architector | opus |
| Technical decision | technical-lead | opus |
| Test design | qa-engineer | haiku/sonnet |

### Model Selection

```
Mechanical/rule-based → haiku
Multi-step reasoning → sonnet
Tradeoff analysis → opus
Architectural implications → opus
```

**Rule**: Prefer reading artifacts over agent invocation when possible.

## Coordination Patterns

### Sequential Pipeline (Default)
```
PL→AR→TL→DV→QA→DC→FN→ST
```

### Parallel Documentation
```
       ┌→ DC ─┐
DV →──┤       ├→ FN
       └→ QA ─┘
```

### Quick Workflow
```
PL → DV → QA
```

### Micro Execution
```
DV only
```

## Handoff Message Format

```markdown
## [FROM]→[TO] Handoff

**Summary**: [One sentence]

**Deliverables**:
- [Artifact]: [purpose]

**Open Items**:
- [Question for next stage]
```

## Escalation Message Format

```markdown
## Escalation: [FROM]→[TO]

**Type**: [dependency|architecture|requirements]
**Severity**: [blocking|degraded]

**Problem**: [Description]
**Attempted**: [What was tried]
**Needed**: [Specific ask]
```

## Stage-Specific Handoffs

### DV → SR (Security Review)
```markdown
**Security-Sensitive Areas**:
- [Area]: [why relevant]
**Recommended Focus**: Auth, data handling, APIs
```

### SR → QA
```markdown
**Security Status**: [Approved|Blocked|Conditional]
**Critical/High Findings**: [count]
**Security Tests Recommended**: [list]
```

### DC → RE (Release Engineering)
```markdown
**Commit Summary**: [feat/fix list]
**Recommended Version Bump**: [MAJOR|MINOR|PATCH]
```

### IR → DV (Emergency)
```markdown
**Incident ID**: INC-[N]
**Severity**: P[0-3]
**Required Fix**: [specific change]
**Constraints**: Minimal change, no refactoring
```

## Constitutional Coordination

Ethics-reviewer can be invoked at any stage:
- Optional: `--ethics-review` flag
- Mandatory: High-risk feature detected
- Escalation: Agent flags concern
- Hard constraint: Immediate stop

### Honesty in Handoffs

| Property | Requirement |
|----------|-------------|
| Truthful | Accurate status claims |
| Calibrated | Appropriate uncertainty |
| Transparent | No hidden issues |

## Hook-Based Stage Monitoring

Claude Code hook events enable automated monitoring of agent lifecycle within workflows.

### Subagent Lifecycle Hooks

| Hook Event | Fires When | Matcher | Payload Fields (2.1.69+) |
|------------|------------|---------|--------------------------|
| `SubagentStart` | Stage agent spawned | Agent type name (e.g., `igrsoft:developer`) | `agent_id`, `agent_type` |
| `SubagentStop` | Stage agent completes | Agent type name | `agent_id`, `agent_type` |

> **Reliability (2.1.71+)**: Parent agents can now reliably recover subagent results after context compaction. Long-running workflows with multiple subagent handoffs no longer risk losing intermediate results.

#### Project-Level Configuration

Add to project `settings.json` for workflow-wide monitoring:

```json
{
  "hooks": {
    "SubagentStart": [
      {
        "matcher": "igrsoft:.*",
        "hooks": [
          { "type": "command", "command": "./tools/log-stage-start.sh" }
        ]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [
          { "type": "command", "command": "./tools/log-stage-complete.sh" }
        ]
      }
    ]
  }
}
```

Hooks also support HTTP endpoints (v2.1.63+) for external monitoring:

```json
{
  "hooks": {
    "SubagentStop": [
      {
        "hooks": [
          { "type": "http", "url": "https://dashboard.example.com/webhook/stage-complete" }
        ]
      }
    ]
  }
}
```

### Agent Teams Lifecycle Hooks

When agent teams are enabled (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`), additional hook events are available:

| Hook Event | Fires When | Payload Fields (2.1.69+) | Use Case |
|------------|------------|--------------------------|----------|
| `TeammateIdle` | Teammate finishes work and becomes idle | `agent_id`, `agent_type` | Assign next task, reassign work |
| `TaskCompleted` | A task in the shared task list is completed | `agent_id`, `agent_type` | Trigger dependent stages, update orchestrator |

These hooks enable event-driven orchestration in milestone mode, where the lead session can react to teammate progress automatically.

#### Stopping Teammates Programmatically (2.1.69+)

`TeammateIdle` and `TaskCompleted` hook handlers can return a stop signal to terminate a teammate:

```json
{ "continue": false, "stopReason": "Issue completed — PR created" }
```

Use cases: stop teammate when its issue is complete, when milestone budget is exhausted, or when a blocking error requires lead intervention.

## Agent Teams vs Subagents

### Comparison for igrsoft Workflows

| Aspect | Subagents (Task tool) | Agent Teams (Teammate) |
|--------|----------------------|------------------------|
| Context | Own window, results return to caller | Fully independent sessions |
| Communication | Report back to parent only | Direct inter-teammate messaging |
| Coordination | Task dependencies (blockedBy) | Shared task list + messaging |
| Tool restrictions | `tools` frontmatter per agent | Inherits lead's permissions |
| Token cost | Lower (results summarized) | Higher (N context windows) |
| Nesting | Cannot spawn sub-subagents | Cannot spawn sub-teams |
| Source isolation | None by default; `isolation: worktree` in frontmatter | None by default; worktree mode recommended for milestone |

### When to Use Each

| Workflow Pattern | Subagents | Agent Teams |
|-----------------|-----------|-------------|
| Standard 8/10-stage | Default | Not recommended |
| Cross-plugin handoff (DV→apple-developer) | Default | Not applicable |
| Milestone sequential issues | Default (orchestrator) | Not recommended |
| Milestone parallel independent issues | Task-based tracks | Optional (experimental) |
| Cross-cutting research / competing hypotheses | Possible | Preferred |
| Code review from multiple perspectives | Possible | Preferred |

### Limitations

- Teammates cannot spawn their own teams or sub-agents (runtime-enforced since v2.1.69)
- One team per session; clean up before starting another
- No session resumption for in-process teammates
- Higher token cost (~Nx for N teammates)

## Related

- `workflow.md` - Workflow system
- `claude-constitution.md` - Constitutional principles
- `security-review-process.md` - Security checklists
- `release-engineering.md` - Versioning
- `incident-response.md` - Incident triage
