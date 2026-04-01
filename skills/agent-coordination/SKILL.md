---
name: agent-coordination
description: Patterns for multi-agent coordination, handoffs, parallel execution, and error escalation. Use when coordinating agent handoffs, debugging multi-stage execution, or managing parallel agent workflows.
effort: medium
---

# Agent Coordination

Patterns for coordinating agents across workflow stages, managing handoffs, and handling errors.

**Stage codes and agents**: See `${CLAUDE_SKILL_DIR}/shared/stage-codes.md`
**Task System tools**: See `${CLAUDE_SKILL_DIR}/shared/task-system.md`

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

### Parallel Tool Call Safety

Failed `Read`, `WebFetch`, or `Glob` calls don't cancel sibling parallel tool calls. Only `Bash` errors cascade. This makes parallel file reads and searches more reliable within agents.

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

### Per-Invocation Model Override

The Task tool `model` parameter allows per-invocation overrides:

```
Task({ subagent_type: "igrsoft:developer", model: "opus" })
```

> Agent teams inherit the leader's model. Teammates use the parent session's model unless explicitly overridden. Model aliases (`opus`/`sonnet`/`haiku`) work correctly across all providers (Anthropic, Bedrock, Vertex, Foundry).

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

See references/ for hook-based monitoring (including StopFailure, CwdChanged, FileChanged, TaskCreated, WorktreeCreate hooks, and conditional `if` field for hook filtering), agent teams comparison, and MCP elicitation patterns.

## Related

- `workflow.md` - Workflow system
- `claude-constitution.md` - Constitutional principles
- `security-review-process.md` - Security checklists
- `release-engineering.md` - Versioning
- `incident-response.md` - Incident triage
