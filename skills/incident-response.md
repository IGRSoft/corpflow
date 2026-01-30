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

## Communication Templates

### Initial Notification

```markdown
## 🚨 Incident Alert: [Brief Description]

**Severity**: P[0-3]
**Status**: Investigating
**Time Detected**: [HH:MM UTC]
**Impact**: [Who/what is affected]

### Summary
[1-2 sentences describing the visible symptoms]

### Current Actions
- [What we're doing right now]

### Next Update
[Time of next update, e.g., "in 30 minutes" or "HH:MM UTC"]
```

### Status Update

```markdown
## 🔄 Incident Update: [Brief Description]

**Severity**: P[0-3]
**Status**: [Investigating | Identified | Monitoring | Resolved]
**Duration**: [Time since start]

### What Changed
[New information since last update]

### Current Understanding
[What we believe is happening]

### Next Steps
[What we're doing next]

### Next Update
[Time]
```

### Resolution Notice

```markdown
## ✅ Incident Resolved: [Brief Description]

**Duration**: [Total time]
**Impact**: [Users affected, features impacted]

### Root Cause
[Brief description of what caused the issue]

### Resolution
[What we did to fix it]

### Verification
[How we confirmed the fix]

### Follow-up
- Post-mortem scheduled: [date]
- Tracking issue: [link]
```

## Post-Mortem Template

```markdown
# Post-Mortem: [Incident Title]

**Date**: [YYYY-MM-DD]
**Severity**: P[0-3]
**Duration**: [HH:MM]
**Author**: [Name]
**Status**: [Draft | Review | Final]

## Executive Summary
[2-3 sentence summary for executives]

## Impact
- **Users affected**: [number/percentage]
- **Services impacted**: [list]
- **Duration**: [time]
- **Business impact**: [revenue, reputation, etc.]

## Timeline
| Time (UTC) | Event |
|------------|-------|
| HH:MM | First customer report received |
| HH:MM | Alert triggered |
| HH:MM | On-call engineer engaged |
| HH:MM | Root cause identified |
| HH:MM | Fix deployed |
| HH:MM | Full service restored |

## Root Cause Analysis

### What Happened
[Detailed description of the incident]

### Five Whys
1. **Why did the incident occur?**
   → [Immediate cause]

2. **Why did [immediate cause] happen?**
   → [Contributing factor 1]

3. **Why did [contributing factor 1] happen?**
   → [Contributing factor 2]

4. **Why did [contributing factor 2] happen?**
   → [Contributing factor 3]

5. **Why did [contributing factor 3] happen?**
   → [Root cause]

### Contributing Factors
- [Factor 1]
- [Factor 2]

## What Went Well
- [Thing that worked]
- [Thing that worked]

## What Could Be Improved
- [Area for improvement]
- [Area for improvement]

## Action Items
| Priority | Action | Owner | Due Date | Status |
|----------|--------|-------|----------|--------|
| P1 | Prevent recurrence: [action] | [name] | [date] | Open |
| P2 | Improve detection: [action] | [name] | [date] | Open |
| P3 | Process improvement: [action] | [name] | [date] | Open |

## Lessons Learned
1. [Key takeaway]
2. [Key takeaway]

## Appendix
- [Links to relevant logs, dashboards, etc.]
```

## Blameless Post-Mortem Principles

### Core Principles

1. **Focus on systems, not individuals**
   - Ask "What failed?" not "Who failed?"
   - Identify process gaps, not blame targets

2. **Assume best intentions**
   - Everyone made decisions with available information
   - Hindsight bias distorts judgment

3. **Learn, don't punish**
   - Goal is prevention, not punishment
   - Fear inhibits honest reporting

4. **Share broadly**
   - Lessons benefit entire organization
   - Transparency builds trust

### Facilitation Tips

```markdown
DO:
- Use neutral language ("The system" vs "You")
- Focus on "How might we prevent...?"
- Acknowledge uncertainty
- Document all contributing factors
- Follow up on action items

DON'T:
- Ask "Why did you...?"
- Focus on individual decisions
- Accept "human error" as root cause
- Skip action item follow-up
- Blame on-call or responders
```

## Runbook: Common Incident Patterns

### Database Connection Exhaustion

```markdown
## Symptoms
- Timeouts on database operations
- "Too many connections" errors
- Service degradation

## Diagnosis
1. Check connection pool metrics
2. Identify queries holding connections
3. Look for connection leaks

## Mitigation
1. Scale connection pool (short-term)
2. Identify and fix leaking code
3. Add connection timeout/recycling
```

### Memory Leak

```markdown
## Symptoms
- Increasing memory usage over time
- OOM kills
- Performance degradation

## Diagnosis
1. Check memory metrics trend
2. Identify memory-heavy processes
3. Analyze heap dumps

## Mitigation
1. Restart affected services (short-term)
2. Identify leak source
3. Deploy fix
```

### External API Failure

```markdown
## Symptoms
- Timeouts to external service
- Increased error rates
- Degraded functionality

## Mitigation
1. Activate circuit breaker
2. Enable fallback/cache
3. Notify external provider
4. Monitor for recovery
```

## Integration Points

- **incident-responder agent**: Uses these patterns for IR stage
- **debugger (debugging-toolkit)**: Root cause analysis
- **five-whys skill**: Post-mortem analysis
- **security-reviewer**: Security incident escalation
