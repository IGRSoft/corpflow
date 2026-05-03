---
name: incident-response
description: Incident classification, hotfix workflow, rollback procedures, and post-mortem templates for IR stage. Use when handling production incidents or emergency hotfixes.
effort: high
---

# Incident Response

Guidelines for incident triage, hotfix coordination, and post-mortem facilitation.

## Incident Classification

### Severity Levels

| Priority | Impact | Response Time | Examples |
|----------|--------|---------------|----------|
| **P0 - Critical** | Complete outage, data loss | Immediate, all hands | Site down, data breach, security incident |
| **P1 - High** | Major feature broken | < 1 hour | Login broken, payments failing, core workflow blocked |
| **P2 - Medium** | Feature degraded | < 4 hours | Slow performance, secondary feature broken |
| **P3 - Low** | Minor issue | Next business day | UI glitch, edge case bug, cosmetic issue |

### Classification Criteria

```markdown
## Is this a P0?
- [ ] Complete service unavailable?
- [ ] Data loss occurring or imminent?
- [ ] Security breach detected?
- [ ] Regulatory compliance at risk?

## Is this a P1?
- [ ] Major feature completely broken?
- [ ] >10% of users affected?
- [ ] Revenue-impacting?
- [ ] SLA breach imminent?

## Is this a P2?
- [ ] Feature degraded but usable?
- [ ] Workaround available?
- [ ] <10% of users affected?
- [ ] Non-critical functionality?

## Otherwise → P3
```

## Emergency Workflow

### Flow Diagram

```
emergency: [description]
     │
     ▼
┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐
│   IR    │ → │   DV    │ → │   DR    │ → │   QA    │ → │   RE    │ → │   FN    │
│ Triage  │    │ Hotfix  │    │ Review  │    │  Test   │    │ Release │    │ Deploy  │
└─────────┘    └─────────┘    └─────────┘    └─────────┘    └─────────┘    └─────────┘
```

### Stage Responsibilities

| Stage | Owner | Actions |
|-------|-------|---------|
| IR | incident-responder | Classify, assess, decide approach |
| DV | developer | Implement minimal fix |
| QA | qa-engineer | Regression test critical paths |
| RE | release-engineer | Prepare hotfix release |
| FN | project-manager | Execute emergency deployment |

> **DV Hotfix Tip (v2.1.98+)**: Use the Monitor tool to stream build output during hotfix implementation. Combine `run_in_background` Bash with Monitor for real-time error detection instead of polling. Tee the build stream into `.context/logs/hotfix-<YYYYMMDD-HHMMSS>.log` so the evidence survives into `complete.md` / `release-prep.md`. See `${CLAUDE_SKILL_DIR}/../agent-coordination/SKILL.md §Monitor Tool` and `${CLAUDE_SKILL_DIR}/../logging-conventions/SKILL.md`.

### IR → DV Handoff Contract

`incident-report.md` MUST contain these four sections before IR can transition
to DV. The orchestrator validates per `shared/stage-contracts.md § IR`. If any
section is empty, DV is not dispatched and IR is re-queued with a
`missing_input` error entry.

#### Required Sections

| Section | Content | Purpose |
|---------|---------|---------|
| **Required Fix** | Concrete code-level change or data correction needed. Not a description of the problem — the *solution*. | Prevents DV from re-diagnosing |
| **Constraints** | What DV MUST NOT do (no schema changes, no new dependencies, keep wire format stable, etc.) | Protects production invariants |
| **Blast Radius** | Files/modules DV may touch. Explicit allow-list. | Prevents scope creep during emergency |
| **Verification Command** | Exact command QA will run (`curl …`, `xcodebuild test -only-testing:X`, manual steps) | Aligns QA criteria upfront |

#### DV Delegation Prompt

When IR completes and DV is dispatched, the orchestrator's prompt MUST include
the phrase:

> Focus strictly on the Required Fix in `.context/incident-N.md`. Do NOT
> modify files outside the listed Blast Radius. Do NOT refactor, clean up,
> reformat, or improve adjacent code. Emergencies are not the time for scope
> expansion. If the Required Fix cannot be implemented within the Blast
> Radius, STOP and escalate back to IR via `error_escalated_to: "IR"` — do
> NOT expand scope unilaterally.

This language is mandatory, not a suggestion — the prompt template in
`commands/emergency.md` enforces it.

## Decision Framework

### Hotfix vs Rollback vs Mitigation

```
                    Is the issue causing active harm?
                              │
              ┌───────────────┴───────────────┐
              │ YES                           │ NO
              ▼                               ▼
    Is rollback safe and fast?         Can we wait for
              │                        normal release?
    ┌─────────┴─────────┐                    │
    │ YES               │ NO           ┌─────┴─────┐
    ▼                   ▼              │ YES       │ NO
 ROLLBACK        Is hotfix viable      ▼           ▼
                 in < 1 hour?       Normal     HOTFIX
                      │             workflow
            ┌─────────┴─────────┐
            │ YES               │ NO
            ▼                   ▼
         HOTFIX             MITIGATE
                         (feature flag,
                          traffic shift)
```

### Rollback Safety Checklist

Rollback is SAFE when:
```markdown
- [ ] Issue introduced by recent deployment
- [ ] No database schema changes
- [ ] No data migrations applied
- [ ] Previous version is known stable
- [ ] Rollback won't cause data loss
- [ ] External dependencies unchanged
```

Rollback is UNSAFE when:
```markdown
- [ ] Database schema changed (forward-only migrations)
- [ ] Data transformation already applied
- [ ] External API contracts changed
- [ ] Third-party integrations updated
- [ ] Rollback would cause worse issues
```

## Incident Runbook Structure

Production runbooks follow this structure:

```
1. Overview & Impact
2. Detection & Alerts
3. Initial Triage (First 5 Minutes)
4. Mitigation Steps
5. Root Cause Investigation
6. Resolution Procedures
7. Verification & Rollback
8. Communication Templates
9. Escalation Matrix
```

### Triage Checklist (First 5 Minutes)

```markdown
- [ ] Which customers/users are affected?
- [ ] What percentage of traffic is impacted?
- [ ] Are there financial or compliance implications?
- [ ] What's the blast radius across services?
- [ ] When did the issue start? (correlate with deployments)
- [ ] Are alerts firing? Which ones?
```

## Blameless Post-Mortem Template

```markdown
# Postmortem: [Incident Title]

**Date**: YYYY-MM-DD
**Authors**: [names]
**Severity**: P[0-3]
**Duration**: [minutes/hours]

## Executive Summary
[1-2 sentences: what happened, impact, resolution]

## Impact
- Users affected: [count/percentage]
- Revenue impact: [if applicable]
- Support tickets: [count]

## Timeline (UTC)
| Time | Event |
|------|-------|
| HH:MM | [Event] |

## Root Cause
[Technical explanation of what caused the incident]

## Contributing Factors
- [System factor, not individual]
- [Process gap]

## What Went Well
- [Effective response actions]

## What Could Be Improved
- [Process improvements]

## Action Items
| Priority | Action | Owner | Due |
|----------|--------|-------|-----|
| P1 | [Prevent recurrence] | [name] | [date] |
| P2 | [Improve detection] | [name] | [date] |
```

### Post-Mortem Triggers

- P0 or P1 incident
- Customer-facing outage > 15 minutes
- Data loss or security incident
- Near-miss that could have been severe
- Novel failure mode

### Blameless Culture Principles

| Blame-Focused | Blameless |
|---------------|-----------|
| "Who caused this?" | "What conditions allowed this?" |
| "Someone made a mistake" | "The system allowed this mistake" |
| Punish individuals | Improve systems |

## On-Call Handoff

### Shift Transition Checklist

```markdown
- [ ] Active incidents documented
- [ ] Ongoing investigations summarized
- [ ] Recent deployments/changes listed
- [ ] Known issues with workarounds noted
- [ ] Upcoming maintenance/releases flagged
- [ ] Alerting setup verified for incoming engineer
```

See references/ for communication templates and common incident runbooks.

## Integration Points

- **incident-responder agent**: Uses these patterns for IR stage
- **debugger (debugging-toolkit)**: Root cause analysis
- **five-whys skill**: Post-mortem analysis
- **security-reviewer**: Security incident escalation
