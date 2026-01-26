---
name: agent-coordination
description: Patterns for efficient multi-agent coordination, handoffs, parallel execution, and error escalation. Apply for workflow orchestration and stage transitions.
---

# Agent Coordination

Systematic patterns for coordinating multiple agents across the 8-stage workflow system, managing handoffs, and handling errors efficiently.

## Handoff Protocol

### Standard Handoff Sequence

```
1. Current agent completes work
         ↓
2. Updates task status: TaskUpdate({ taskId: "X", status: "completed" })
         ↓
3. Creates stage artifact (e.g., planning.md, analyzing.md)
         ↓
4. Writes compressed handoff summary (50-100 tokens)
         ↓
5. Next agent begins: TaskUpdate({ taskId: "Y", status: "in_progress" })
```

### Handoff Checklist

Before transitioning:
- [ ] All stage objectives completed
- [ ] Artifact created in `.context/`
- [ ] Task status updated to `completed`
- [ ] Handoff summary prepared (compressed)
- [ ] Open questions documented for next stage

### Task Status Values

| Status | Meaning | Example |
|--------|---------|---------|
| **pending** | Not yet started | Task blocked by dependencies |
| **in_progress** | Actively working | Agent executing stage |
| **completed** | Done | Stage finished successfully |

## Error Handling & Escalation

### Error Classification

| Error Type | Description | Retry? | Escalate To |
|------------|-------------|--------|-------------|
| **Transient** | API timeout, network issue | Yes (3x) | None (auto-retry) |
| **Logic** | Incorrect approach, bug | Yes (2x) | Same agent (fix first) |
| **Dependency** | Missing input, blocked | No | Previous stage |
| **Resource** | Context overflow, budget | Yes (1x) | Compress first |
| **Requirements** | Unclear requirements | No | P stage |
| **Architecture** | Design flaw discovered | No | A stage |

### Escalation Chain

```
Primary Path (stage-specific escalation):
S → F → Q → D → T → A → P → USER

Direct Escalation (based on error type):
- Requirements unclear → P (product-manager)
- Architecture issue → A (software-architector)
- Resource allocation → T (team-lead)
- Implementation bug → D (developer, retry)
- Test environment → T (team-lead)
- Documentation gap → W (technical-writer, retry)
```

### Adaptive Retry Strategy

```
┌─────────────────────────────────────────────────────────────┐
│                    ERROR DETECTED (X2)                       │
└──────────────────────────┬──────────────────────────────────┘
                           ↓
              ┌────────────────────────┐
              │   Classify Error Type  │
              └───────────┬────────────┘
                          ↓
    ┌─────────────────────┼─────────────────────┐
    ↓                     ↓                     ↓
┌───────┐           ┌───────────┐         ┌──────────┐
│Transient│         │Logic Error│         │Dependency│
└────┬────┘         └─────┬─────┘         └────┬─────┘
     ↓                    ↓                    ↓
┌─────────┐         ┌───────────┐         ┌──────────────┐
│Immediate│         │Fix, then  │         │Escalate      │
│retry    │         │retry      │         │immediately   │
│(max 3)  │         │(max 2)    │         │(no retry)    │
└─────────┘         └───────────┘         └──────────────┘
```

### Error Documentation

Create/update `.context/error.md`:

```markdown
# Error Log

## [STAGE] Error - [TIMESTAMP]

**Classification**: [transient|logic|dependency|resource]
**Retry Strategy**: [immediate|fix-then-retry|escalate|compress]
**Retry Count**: [X/max]

### Problem Description
[Clear, concise description]

### Root Cause Analysis
1. Why? [Surface cause]
2. Why? [Deeper cause]
3. Why? [Root cause - stop when actionable]

### Resolution Path
- [ ] [Specific action 1]
- [ ] [Specific action 2]

### Context to Preserve
[Key context needed for retry/escalation]
```

## Parallel Execution Patterns

### Safe Parallel Combinations

| Pattern | Stages | Condition | Benefit |
|---------|--------|-----------|---------|
| **Docs + QA** | W + Q | W doesn't need test results | 30-40% time savings |
| **Early Docs** | W starts during D | Core API stable | Documentation ready sooner |
| **Parallel Research** | Multiple Explore agents | Independent searches | Faster context gathering |

### Never Parallelize

| Combination | Reason |
|-------------|--------|
| A before P complete | Architecture needs requirements |
| D before T complete | Development needs coordination |
| D before A complete | Implementation needs design |
| S before F complete | Approval needs release package |
| Q before D complete | Can't test unwritten code |

### Parallel Execution Protocol

```markdown
## Parallel Stage Execution

### Prerequisites
- [ ] Both stages have independent inputs
- [ ] No shared artifact writes
- [ ] Separate task entries with proper dependencies

### Execution
1. Initialize both stages (X0 for each)
2. Track in task-state.json: `"active_stages": ["W", "Q"]`
3. Execute concurrently
4. Wait for both X3 before proceeding

### Merge Handling
If both stages modify same artifact:
- Designate primary owner
- Secondary appends to designated section
- Review for conflicts before F stage
```

### task-state.json Parallel Tracking

```json
{
  "parallel_execution": {
    "enabled": true,
    "active_stages": ["W", "Q"],
    "safe_combinations": [["W", "Q"]],
    "started_at": "2025-01-22T10:00:00Z",
    "primary_for_conflicts": "W"
  }
}
```

## Agent Selection

### Within-Stage Agent Selection

When a stage needs sub-task delegation:

| Sub-Task Type | Delegate To | Model | Rationale |
|---------------|-------------|-------|-----------|
| Status check | Self (inline) | haiku | Simple validation |
| Formatting | Self (inline) | haiku | Mechanical operation |
| Code implementation | developer | sonnet | Balanced complexity |
| Architecture question | software-architector | opus | Complex tradeoffs |
| Test design | qa-engineer | haiku/sonnet | Depends on complexity |
| Documentation snippet | technical-writer | haiku | Template-based |

### Cross-Stage Consultation (Without Stage Change)

Sometimes an agent needs input from another domain without a full stage transition:

| Need | Consult | Method | Cost |
|------|---------|--------|------|
| Requirement clarification | product-manager | Read `planning.md` | Free |
| Architecture question | software-architector | Read `analyzing.md` | Free |
| Implementation detail | developer | Read source files | Free |
| Test coverage info | qa-engineer | Brief inline query | Low |
| Doc standard check | technical-writer | Read existing docs | Free |

**Rule**: Prefer reading artifacts over agent invocation when possible.

### Model Selection by Complexity

```
Task Complexity Assessment:
┌─────────────────────────────────────────┐
│  Is it mechanical/rule-based?           │
│  YES → haiku                            │
│  NO ↓                                   │
├─────────────────────────────────────────┤
│  Does it require multi-step reasoning?  │
│  NO → haiku                             │
│  YES ↓                                  │
├─────────────────────────────────────────┤
│  Does it involve tradeoff analysis?     │
│  NO → sonnet                            │
│  YES ↓                                  │
├─────────────────────────────────────────┤
│  Are there architectural implications?  │
│  NO → sonnet                            │
│  YES → opus                             │
└─────────────────────────────────────────┘
```

## Coordination Patterns

### Pattern 1: Sequential Pipeline (Default)

```
P1 → P3 → A1 → A3 → T1 → T3 → D1 → D3 → Q1 → Q3 → W1 → W3 → F1 → F3 → S1 → S3
```

Standard 8-stage execution with handoffs.

### Pattern 2: Fast Track (Skip Approval)

```
P1 → P3 → A1 → A3 → T1 → T3 → D1 → D3 → Q1 → Q3 → W1 → W3 → F1 → F3 → S1 → S3
         ↑
         (auto-continue, no P3 approval gate)
```

Use with `fworkflow:` trigger for trusted workflows.

### Pattern 3: Quick Workflow

```
P1 → P3 → D1 → D3 → Q1 → Q3
```

Use with `quick:` for simple changes (bug fixes, small features).

### Pattern 4: Micro Execution

```
D1 → D3
```

Use with `micro:` for trivial changes (typos, formatting).

### Pattern 5: Parallel Documentation

```
          ┌→ W1 → W3 ─┐
D3 → T1 ──┤           ├→ F1
          └→ Q1 → Q3 ─┘
```

Documentation and QA run in parallel after development.

## Communication Protocols

### Handoff Message Format

```markdown
## [FROM_STAGE]→[TO_STAGE] Handoff

**Summary**: [One sentence: what was accomplished]

**Key Deliverables**:
- [Artifact 1]: [purpose]
- [Artifact 2]: [purpose]

**Open Items**:
- [Question/issue for next stage]

**Recommended Approach**:
[One sentence: suggested direction for next stage]
```

### Escalation Message Format

```markdown
## Escalation: [FROM_STAGE]→[TO_STAGE]

**Issue Type**: [dependency|architecture|requirements|resource]
**Severity**: [blocking|degraded|informational]

**Problem**: [Clear description of blocker]

**Attempted**:
- [What was tried]
- [What failed]

**Needed**:
- [Specific ask from escalation target]

**Impact if Unresolved**:
[Consequence of not resolving]
```

### Consultation Request Format

```markdown
## Consultation Request: [CURRENT_STAGE] needs [TARGET_EXPERTISE]

**Context**: [Brief situation in current stage]
**Question**: [Specific question needing input]
**Constraints**: [Relevant limitations]
**Urgency**: [blocking|preferred|nice-to-have]
```

## Quick Reference

### Stage-Agent Mapping

| Stage | Primary Agent | Model | Key Responsibility |
|-------|---------------|-------|-------------------|
| P | product-manager | sonnet | Requirements |
| A | software-architector | opus | Design |
| T | team-lead | sonnet | Coordination |
| D | developer | opus | Implementation |
| Q | qa-engineer | haiku | Testing |
| W | technical-writer | haiku | Documentation |
| F | project-manager | sonnet | Release |
| S | stakeholder | sonnet | Approval |

### Escalation Quick Guide

| Stuck On | Escalate To | Expected Help |
|----------|-------------|---------------|
| Unclear requirements | P | Clarification |
| Design flaw | A | Architecture fix |
| Resource conflict | T | Reallocation |
| Implementation block | D retry | Different approach |
| Test environment | T | Environment fix |
| Doc conflict | W retry | Resolve internally |
| Release blocker | F | Unblock or defer |
| Business conflict | S | Decision |

### Parallel Safety Check

```
Can [Stage A] and [Stage B] run in parallel?

□ Do they have independent inputs?
□ Do they write to different artifacts?
□ Is neither dependent on the other's output?
□ Is the combination in safe_combinations list?

All checked? → Safe to parallelize
Any unchecked? → Run sequentially
```

## Constitutional Coordination

### Ethics-Reviewer Integration

The `ethics-reviewer` agent can be invoked at any stage:

| Invocation Type | Trigger | Action |
|-----------------|---------|--------|
| **Optional Review** | `--ethics-review` flag | Add ethics checkpoint |
| **Mandatory Review** | High-risk feature detected | Block until review complete |
| **Escalation** | Agent flags ethical concern | Route to ethics-reviewer |
| **Hard Constraint** | Absolute violation detected | Immediate stop |

### Constitutional Escalation Chain

Ethics concerns follow a separate escalation path:

```
Standard Escalation (Technical):
S → F → Q → D → T → A → P → USER

Constitutional Escalation (Ethics):
Any Stage → ethics-reviewer → stakeholder → USER

Hard Constraint Violation:
Any Stage → IMMEDIATE STOP → USER
```

### Honesty Requirements in Handoffs

All handoff messages must adhere to honesty properties:

| Property | Handoff Requirement |
|----------|---------------------|
| **Truthful** | Accurate status and completion claims |
| **Calibrated** | Appropriate uncertainty in estimates |
| **Transparent** | No hidden issues or concerns |
| **Forthright** | Proactively share relevant risks |
| **Non-deceptive** | No misleading summaries |

### Ethics-Aware Agent Selection

When delegating tasks, consider constitutional implications:

| Task Type | Additional Consideration |
|-----------|-------------------------|
| User data handling | May need ethics-reviewer consultation |
| Content generation | Check for manipulation potential |
| Decision algorithms | Assess fairness and bias |
| Safety-critical code | Mandatory review before completion |

### Constitutional Handoff Format

When ethics concerns are identified, include in handoff:

```markdown
## [FROM_STAGE]→[TO_STAGE] Handoff

**Summary**: [Accomplishment]

**Constitutional Notes**:
- [Ethics concern or consideration]
- [Mitigation applied or recommended]

**Ethics Status**: [Clear | Concern Noted | Review Required]
```

## Related Skills

- `workflow.md` - Workflow system documentation
- `cost-optimization.md` - Cost tracking and optimization
- `claude-constitution.md` - Constitutional principles and ethics framework
