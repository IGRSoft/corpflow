---
name: agent-coordination
description: Patterns for efficient multi-agent coordination, handoffs, parallel execution, and error escalation. Apply for workflow orchestration and stage transitions.
---

# Agent Coordination

Systematic patterns for coordinating multiple agents across the workflow system (8-stage, 10-stage, and emergency flows), managing handoffs, and handling errors efficiently.

## Workflow Variants

| Variant | Stages | Use Case |
|---------|--------|----------|
| 8-stage | PL→AR→TL→DV→QA→DC→FN→ST | Standard (backward compatible) |
| 10-stage | PL→AR→TL→DV→SR→QA→DC→RE→FN→ST | Full workflow with security & release |
| Emergency | IR→DV→QA→RE→FN | Hotfix/incident response |

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

| Status | Meaning |
|--------|---------|
| **pending** | Task blocked by dependencies |
| **in_progress** | Agent executing stage |
| **completed** | Stage finished successfully |

## Error Handling & Escalation

### Error Classification

| Error Type | Description | Retry? | Escalate To |
|------------|-------------|--------|-------------|
| **Transient** | API timeout, network issue | Yes (3x) | None (auto-retry) |
| **Logic** | Incorrect approach, bug | Yes (2x) | Same agent (fix first) |
| **Dependency** | Missing input, blocked | No | Previous stage |
| **Resource** | Context overflow, budget | Yes (1x) | Compress first |
| **Requirements** | Unclear requirements | No | PL stage |
| **Architecture** | Design flaw discovered | No | AR stage |

### Escalation Chain

```
10-Stage Flow (primary path):
ST → FN → RE → DC → QA → SR → DV → TL → AR → PL → USER

8-Stage Flow (backward compatible):
ST → FN → DC → QA → DV → TL → AR → PL → USER

Emergency Flow:
FN → RE → QA → DV → IR → USER

Direct Escalation (based on error type):
- Requirements unclear → PL (product-manager)
- Architecture issue → AR (software-architector)
- Technical decision → technical-lead (implementation choices)
- Code quality concern → technical-lead (standards, deep review)
- Tech debt decision → technical-lead (prioritization)
- Security vulnerability → SR (security-reviewer)
- Resource allocation → TL (team-lead)
- Implementation bug → DV (developer, retry)
- Test environment → TL (team-lead)
- Documentation gap → DC (technical-writer, retry)
- Release blocker → RE (release-engineer)
- Incident response → IR (incident-responder)
```

### Adaptive Retry Strategy

**Note**: `X` represents any stage (P, A, T, D, Q, W, F, S).

```
┌─────────────────────────────────────────────────────────────┐
│                     ERROR DETECTED                           │
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
1. Initialize both stages via Task System (set `in_progress`)
2. Execute concurrently
3. Wait for both tasks to reach `completed` before proceeding

### Merge Handling
If both stages modify same artifact:
- Designate primary owner
- Secondary appends to designated section
- Review for conflicts before FN stage
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
| Technical decision | technical-lead | opus | Implementation choices |
| Code quality deep dive | technical-lead | opus | Beyond checklist review |
| Tech debt assessment | technical-lead | opus | Prioritization analysis |
| Test design | qa-engineer | haiku/sonnet | Depends on complexity |
| Documentation snippet | technical-writer | haiku | Template-based |

### Cross-Stage Consultation (Without Stage Change)

Sometimes an agent needs input from another domain without a full stage transition:

| Need | Consult | Method | Cost |
|------|---------|--------|------|
| Requirement clarification | product-manager | Read `planning.md` | Free |
| Architecture question | software-architector | Read `analyzing.md` | Free |
| Technology evaluation | technical-lead | Agent invocation | Medium |
| Code quality guidance | technical-lead | Agent invocation | Medium |
| Tech debt prioritization | technical-lead | Agent invocation | Medium |
| Implementation detail | developer | Read source files | Free |
| Test coverage info | qa-engineer | Brief inline query | Low |
| Doc standard check | technical-writer | Read existing docs | Free |

**Rule**: Prefer reading artifacts over agent invocation when possible.

### Technical Lead vs Team Lead

| Need | Consult | Rationale |
|------|---------|-----------|
| Deep technical decisions | technical-lead | Implementation expertise |
| Code quality standards | technical-lead | Quality enforcement |
| Technology evaluation | technical-lead | Evaluation framework |
| Tech debt management | technical-lead | Prioritization, remediation |
| Resource allocation | team-lead | People management |
| Sprint coordination | team-lead | Process expertise |
| Team blockers | team-lead | Coordination role |
| Agile ceremonies | team-lead | Process facilitation |

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
PL1 → PL3 → AR1 → AR3 → TL1 → TL3 → DV1 → DV3 → QA1 → QA3 → DC1 → DC3 → FN1 → FN3 → ST1 → ST3
```

**Shorthand notation**: `{STAGE}{CODE}` where CODE: 0=preparing, 1=executing, 2=error, 3=done

Standard 8-stage execution with handoffs.

### Pattern 2: Fast Track (Skip Approval)

```
PL1 → PL3 → AR1 → AR3 → TL1 → TL3 → DV1 → DV3 → QA1 → QA3 → DC1 → DC3 → FN1 → FN3 → ST1 → ST3
           ↑
           (auto-continue, no PL3 approval gate)
```

Use with `fworkflow:` trigger for trusted workflows.

### Pattern 3: Quick Workflow

```
PL1 → PL3 → DV1 → DV3 → QA1 → QA3
```

Use with `quick:` for simple changes (bug fixes, small features).

### Pattern 4: Micro Execution

```
DV1 → DV3
```

Use with `micro:` for trivial changes (typos, formatting).

### Pattern 5: Parallel Documentation

```
            ┌→ DC1 → DC3 ─┐
DV3 → TL1 ──┤             ├→ FN1
            └→ QA1 → QA3 ─┘
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
| PL | product-manager | sonnet | Requirements |
| AR | software-architector | opus | Design |
| TL | team-lead | sonnet | Coordination |
| DV | developer | opus | Implementation |
| **SR** | **security-reviewer** | **opus** | **Security audit** |
| QA | qa-engineer | haiku | Testing |
| DC | technical-writer | haiku | Documentation |
| **RE** | **release-engineer** | **haiku** | **Versioning, changelog** |
| FN | project-manager | sonnet | Release |
| ST | stakeholder | sonnet | Approval |
| **IR** | **incident-responder** | **sonnet** | **Incident triage** |

### Escalation Quick Guide

| Stuck On | Escalate To | Expected Help |
|----------|-------------|---------------|
| Unclear requirements | PL | Clarification |
| Design flaw | AR | Architecture fix |
| Resource conflict | TL | Reallocation |
| Technical decision | technical-lead | Implementation guidance |
| Code quality issue | technical-lead | Standards, deep review |
| Tech debt decision | technical-lead | Prioritization |
| **Security vulnerability** | **SR** | **OWASP review, fix guidance** |
| Implementation block | DV retry | Different approach |
| Test environment | TL | Environment fix |
| Doc conflict | DC retry | Resolve internally |
| **Version/changelog issue** | **RE** | **SemVer guidance** |
| Release blocker | FN | Unblock or defer |
| Business conflict | ST | Decision |
| **Production incident** | **IR** | **Triage, coordination** |

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
Standard Escalation (Technical - 10-stage):
ST → FN → RE → DC → QA → SR → DV → TL → AR → PL → USER

Standard Escalation (Technical - 8-stage):
ST → FN → DC → QA → DV → TL → AR → PL → USER

Emergency Escalation:
FN → RE → QA → DV → IR → USER

Constitutional Escalation (Ethics):
Any Stage → ethics-reviewer → stakeholder → USER

Security Escalation:
Any Stage → security-reviewer → stakeholder → USER

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

## New Stage Handoff Patterns

### DV → SR Handoff (Security Review)

```markdown
## DV→SR Handoff

**Summary**: Implementation complete, ready for security review

**Key Deliverables**:
- `development.md`: Implementation summary
- Source files: [list of modified files]

**Security-Sensitive Areas**:
- [Area 1]: [why security-relevant]
- [Area 2]: [why security-relevant]

**Recommended Focus**:
- Authentication/authorization changes
- Data handling patterns
- External API integrations
```

### SR → QA Handoff (Security to Testing)

```markdown
## SR→QA Handoff

**Summary**: Security review complete, [N] findings documented

**Key Deliverables**:
- `security-review.md`: Full security assessment

**Security Status**: [Approved | Blocked | Conditional]

**Critical Findings**: [count]
**High Findings**: [count]

**Security Tests Recommended**:
- [Test 1]: [purpose]
- [Test 2]: [purpose]
```

### DC → RE Handoff (Documentation to Release Engineering)

```markdown
## DC→RE Handoff

**Summary**: Documentation complete, ready for release preparation

**Key Deliverables**:
- `documentation.md`: Documentation summary
- Updated README, API docs, etc.

**Commit Summary**:
- [feat: feature 1]
- [fix: bug 1]

**Recommended Version Bump**: [MAJOR | MINOR | PATCH]
**Breaking Changes**: [yes/no, details]
```

### RE → FN Handoff (Release to Finalization)

```markdown
## RE→FN Handoff

**Summary**: Release artifacts prepared

**Key Deliverables**:
- `release-prep.md`: Release summary
- CHANGELOG updated
- Version: [x.y.z]

**Deployment Checklist**: [complete | items remaining]
**Rollback Plan**: [documented | needed]

**Platform-Specific**:
- iOS: [status]
- Android: [status]
- Web: [status]
```

### IR → DV Handoff (Incident to Hotfix Development)

```markdown
## IR→DV Handoff (Emergency)

**Incident ID**: INC-[number]
**Severity**: P[0-3]

**Summary**: Incident triaged, hotfix required

**Root Cause Hypothesis**: [description]

**Required Fix**:
- [Specific change needed]

**Constraints**:
- [ ] Minimal change only
- [ ] No refactoring
- [ ] Must be backward compatible

**Rollback Available**: [yes/no]
```

## Related Skills

- `workflow.md` - Workflow system documentation
- `cost-optimization.md` - Cost tracking and optimization
- `claude-constitution.md` - Constitutional principles and ethics framework
- `security-review-process.md` - OWASP checklists for SR stage
- `release-engineering.md` - Versioning and changelog for RE stage
- `incident-response.md` - Incident triage for IR stage
