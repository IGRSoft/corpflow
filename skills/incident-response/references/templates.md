# Communication & Post-Mortem Templates

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

Concatenate the three parts below, in order, into one `post-mortem.md`. Triggers and the
blameless-culture table: `SKILL.md § Post-Mortem Triggers`.

### Template Part 1 — Header, Impact & Timeline

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
```

### Template Part 2 — Root Cause & Retrospective

```markdown
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
```

### Template Part 3 — Action Items, Lessons & Appendix

```markdown
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

Systems over individuals, assume best intentions (everyone decided on the information they
had; hindsight distorts), prevention over punishment (fear suppresses honest reporting), and
share lessons broadly. Blame-vs-blameless phrasing: `SKILL.md § Blameless Culture Principles`.

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

| Pattern | Symptoms | Diagnosis | Mitigation |
|---------|----------|-----------|------------|
| Database connection exhaustion | Timeouts on DB operations, "too many connections", service degradation | Connection-pool metrics; queries holding connections; connection leaks | Scale the pool (short-term), fix the leaking code, add connection timeout/recycling |
| Memory leak | Memory climbing over time, OOM kills, performance degradation | Memory-metric trend; memory-heavy processes; heap dumps | Restart affected services (short-term), find the leak source, deploy the fix |
| External API failure | Timeouts to the external service, raised error rates, degraded functionality | Provider status; error mix and retry behaviour | Activate the circuit breaker, enable fallback/cache, notify the provider, monitor for recovery |
