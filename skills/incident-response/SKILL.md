---
name: incident-response
description: Incident classification, hotfix worktask, rollback procedures, and post-mortem templates for IR stage. Use when handling production incidents or emergency hotfixes.
effort: high
---

# Incident Response

Guidelines for incident triage, hotfix coordination, and post-mortem facilitation.

## Incident Classification

### Severity Levels

| Priority | Impact | Response Time | Examples |
|----------|--------|---------------|----------|
| **P0 - Critical** | Complete outage, data loss | Immediate, all hands | Site down, data breach, security incident |
| **P1 - High** | Major feature broken | < 1 hour | Login broken, payments failing, core worktask blocked |
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

## Emergency Worktask

`/worktask --emergency [description]` runs: IR triage → DV hotfix → DR review → QA test →
RE release → FN deploy.

### Stage Responsibilities

| Stage | Owner | Actions |
|-------|-------|---------|
| IR | incident-responder | Classify, assess, decide approach |
| DV | developer | Implement minimal fix |
| QA | qa-engineer | Regression test critical paths |
| RE | release-engineer | Prepare hotfix release |
| FN | project-manager | Execute emergency deployment |

> **DV Hotfix Tip**: stream build output with the Monitor tool over `run_in_background` Bash instead of polling, and tee it into `.context/logs/hotfix-<YYYYMMDD-HHMMSS>.log` so the evidence survives into `complete.md` / `release-prep.md`. See `${CLAUDE_SKILL_DIR}/../agent-coordination/SKILL.md §Monitor Tool` and `${CLAUDE_SKILL_DIR}/../logging-conventions/SKILL.md`.

### IR → DV Handoff Contract

`incident-report.md` MUST carry these four sections before IR transitions to DV;
the orchestrator validates per `shared/stage-contracts.md § IR–ET`. Any empty section
means DV is not dispatched and IR is re-queued with a `missing_input` error entry.

#### Required Sections

| Section | Content | Purpose |
|---------|---------|---------|
| **Required Fix** | Concrete code-level change or data correction needed. Not a description of the problem — the *solution*. | Prevents DV from re-diagnosing |
| **Constraints** | What DV MUST NOT do (no schema changes, no new dependencies, keep wire format stable, etc.) | Protects production invariants |
| **Blast Radius** | Files/modules DV may touch. Explicit allow-list. | Prevents scope creep during emergency |
| **Verification Command** | Exact command QA will run (`curl …`, `xcodebuild test -only-testing:X`, manual steps) | Aligns QA criteria upfront |

#### DV Delegation Prompt

The orchestrator's DV dispatch prompt MUST include this phrase — mandatory, not a
suggestion (emergency worktasks run via `/worktask --emergency`; see
`commands/worktask.md` Options):

> Focus strictly on the Required Fix in `.context/incident-N.md`. Do NOT
> modify files outside the listed Blast Radius. Do NOT refactor, clean up,
> reformat, or improve adjacent code. Emergencies are not the time for scope
> expansion. If the Required Fix cannot be implemented within the Blast
> Radius, STOP and escalate back to IR via `error_escalated_to: "IR"` — do
> NOT expand scope unilaterally.

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
                      │             worktask
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

Fill `references/templates.md § Post-Mortem Template` (Parts 1–3, concatenated into one
`post-mortem.md`): header (date, severity, duration, author, status), executive summary,
impact, UTC timeline, root cause via Five Whys, contributing factors, what went well / could
be improved, action items table (priority, owner, due), lessons learned, appendix.

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

Facilitation DO/DON'T list: `references/templates.md § Facilitation Tips`.

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

Communication templates and common incident runbooks: `references/templates.md`.

## Integration Points

`agents/incident-responder.md` runs these patterns at the IR stage; `debugging-toolkit:debugger`
does root-cause analysis, `skills/shared/five-whys.md` the post-mortem analysis, and
`agents/security-reviewer.md` takes security-incident escalations.
