---
name: incident-response
description: Incident classification, hotfix workflow, rollback procedures, and post-mortem templates for IR stage. (user)
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
┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐
│   IR    │ → │   DV    │ → │   QA    │ → │   RE    │ → │   FN    │
│ Triage  │    │ Hotfix  │    │  Test   │    │ Release │    │ Deploy  │
└─────────┘    └─────────┘    └─────────┘    └─────────┘    └─────────┘
```

### Stage Responsibilities

| Stage | Owner | Actions |
|-------|-------|---------|
| IR | incident-responder | Classify, assess, decide approach |
| DV | developer | Implement minimal fix |
| QA | qa-engineer | Regression test critical paths |
| RE | release-engineer | Prepare hotfix release |
| FN | project-manager | Execute emergency deployment |

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

See references/ for communication templates, post-mortem framework, and common incident runbooks.

## Integration Points

- **incident-responder agent**: Uses these patterns for IR stage
- **debugger (debugging-toolkit)**: Root cause analysis
- **five-whys skill**: Post-mortem analysis
- **security-reviewer**: Security incident escalation
