---
name: agent-coordination
description: Patterns for multi-agent coordination, handoffs, parallel execution, and error escalation. Use when coordinating agent handoffs, debugging multi-stage execution, or managing parallel agent workflows.
effort: medium
---

# Agent Coordination

Patterns for coordinating agents across workflow stages, managing handoffs, and handling errors.

**Stage codes and agents**: See `${CLAUDE_SKILL_DIR}/../shared/stage-codes.md`
**Task System tools**: See `${CLAUDE_SKILL_DIR}/../shared/task-system.md`

## Handoff Protocol

```
1. Current agent completes work
2. Updates task: TaskUpdate({ taskId: "X", status: "completed" })
3. Creates stage artifact (e.g., planning.md)
4. Writes compressed handoff (50-100 tokens)
5. Next agent starts: TaskUpdate({ taskId: "Y", status: "in_progress" })
```

### Orchestrator → PL0 Handoff

Before PL0, the orchestrator creates `.context/exploration.md` with pre-explored
codebase facts. This eliminates PL0's need to re-explore the codebase.

The orchestrator's prompt to PL0 MUST include:
```
Read .context/exploration.md for codebase context.
Do NOT re-read files listed there unless you need additional detail.
```

### Stage Agent File Read Rules

| Stage | Read exploration.md | Read source files | Reason |
|-------|:------------------:|:-----------------:|--------|
| PL | Yes | No | Requirements only, no code changes |
| AR | Yes | Selective | Only files needing architectural analysis |
| TL | Yes | No | Coordination only |
| DV | Yes | Yes (modify targets) | Must read files it will modify |
| QA | Yes | Yes (changed files) | Must review actual changes |
| DC | Yes | No | Documentation from artifacts |

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
| Code implementation | developer | opus |
| Architecture question | software-architector | opus |
| Apple/Swift architecture | apple-developer:apple-architector | opus |
| Technical decision | technical-lead | opus |
| Test design | qa-engineer | haiku/sonnet |

> **Cross-plugin AR collaboration**: For Apple platform projects, `software-architector` consults `apple-developer:apple-architector` during AR stage for Swift app architecture (pattern selection, DI, navigation, concurrency). See `cross-plugin-handoff` skill for the full protocol.

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

> Named subagents appear in `@`-mention typeahead suggestions (v2.1.89+), making it easier to reference and communicate with running agents via `SendMessage`.

> `/agents` displays a tabbed layout (Running/Library tabs) with a `* N running` indicator next to agent types with live instances (v2.1.97/2.1.98).

### Monitor Tool for Background Events (v2.1.98+)

The `Monitor` tool streams events (stdout lines) from background scripts started via Bash with `run_in_background`. Use for watching build output during DV, streaming test results during QA, or log tailing during IR. Unlike polling with `Read`, Monitor provides event-driven notifications without sleep loops.

### MCP Large Result Handling

MCP servers can annotate tool results with `_meta["anthropic/maxResultSizeChars"]` to allow results up to 500K characters without truncation (v2.1.91+). Useful for large outputs like database schemas or build logs from XcodeBuildMCP.

### MCP Tool Inheritance (v2.1.101+)

Subagents inherit MCP tools from dynamically-injected MCP servers in the parent session. Cross-plugin MCP tools (XcodeBuildMCP, Pencil, etc.) are available to stage agents without explicit `tools:` frontmatter entries for each MCP tool.

### Subagent Worktree Access (v2.1.101+)

Sub-agents in isolated worktrees automatically receive Read/Edit access to their own worktree directory. No explicit tool grant needed.

### Background Subagent Partial Progress (v2.1.98+)

Background subagents that fail now report partial progress instead of returning nothing. Orchestrators can inspect partial results for recovery.

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
[Figma capture if URL provided] → Present plan → Approval gate → DV only
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

## Multi-Reviewer Coordination

### Review Dimension Allocation

| Dimension | Focus | Include When |
|-----------|-------|-------------|
| **Security** | Vulnerabilities, auth, input validation | Code handling user input or auth |
| **Performance** | Query efficiency, memory, caching | Data access or hot path changes |
| **Architecture** | SOLID, coupling, patterns | Structural changes or new modules |
| **Testing** | Coverage, quality, edge cases | New functionality added |
| **Accessibility** | WCAG, ARIA, keyboard nav | UI/frontend changes |

### Recommended Review Combinations

| Scenario | Dimensions |
|----------|-----------|
| API endpoint changes | Security, Performance, Architecture |
| UI component changes | Architecture, Testing, Accessibility |
| Data model changes | Security, Performance, Architecture |
| New feature (full) | Security, Performance, Architecture, Testing |

### Finding Consolidation

When multiple reviewers report findings:
1. **Deduplicate**: Merge findings at same file:line
2. **Resolve conflicts**: Use higher severity when reviewers disagree
3. **Organize by severity**: Group as Critical > High > Medium > Low
4. **Cross-reference**: Note findings appearing in multiple dimensions

### Severity Calibration

| Severity | Criteria | Action |
|----------|----------|--------|
| Critical | Exploitable, high impact, easy to find | Block release |
| High | Exploitable or significant impact | Fix before merge |
| Medium | Potential risk, moderate impact | Track, fix soon |
| Low | Minor risk, defense in depth | Advisory |

## Task Decomposition for Parallel Work

### File Ownership Boundaries

When decomposing work for parallel agents:
1. Assign exclusive file ownership per agent — no overlap
2. Define interface contracts at ownership boundaries
3. Create shared types/interfaces before parallel execution
4. Never modify files owned by another agent without team-lead approval

### Hypothesis-Driven Debugging

For complex bugs with multiple potential causes:
1. Generate N hypotheses covering different failure categories
2. Assign each hypothesis to an investigator agent
3. Each investigator gathers confirming/falsifying evidence
4. Arbitrate across findings, rank by confidence and evidence strength

See references/ for hook-based monitoring (including PermissionDenied, StopFailure, CwdChanged, FileChanged, TaskCreated, WorktreeCreate hooks, PreToolUse defer/blocking, conditional `if` field for hook filtering, and PostToolUse format-on-save safety), agent teams comparison, MCP elicitation patterns, and team communication protocols (message types, anti-patterns, deadlock resolution).

## Related

- `workflow.md` - Workflow system
- `claude-constitution.md` - Constitutional principles
- `security-review-process.md` - Security checklists
- `release-engineering.md` - Versioning
- `incident-response.md` - Incident triage
