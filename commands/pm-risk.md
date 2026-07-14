---
name: pm-risk
description: Identify, assess, and document project risks with mitigation strategies
argument-hint: <project or feature description>
allowed-tools: Read, Glob, Grep
model: sonnet
related:
  - agents/project-manager.md
  - commands/pm-sprint.md
  - agents/stakeholder.md
  - agents/ethics-reviewer.md
  - commands/ethics-review.md
  - skills/claude-constitution/SKILL.md
---

# Risk Assessment Command

Identify, assess, and document project risks with mitigation strategies.

## Usage

```
/pm-risk
/pm-risk "Feature or project description"
/pm-risk --update
/pm-risk --report
```

## Options

- `--update` - Update existing risk register
- `--report` - Generate risk report
- `--category [technical|schedule|resource|external|ethical]` - Filter by category
- `--threshold [low|medium|high]` - Show risks above threshold
- `--platform <apple|android|web|all>` - Target platform context (default: all)
- `--include-ethics` - Include ethical risk assessment (recommended for user-facing features)

## Examples

```
/pm-risk
/pm-risk "SSO Implementation Project"
/pm-risk --report --threshold high
```

## Output Format

~~~markdown
# Risk Assessment: SSO Implementation

## Risk Summary

| Category | High | Medium | Low | Total |
|----------|------|--------|-----|-------|
| Technical | 2 | 3 | 1 | 6 |
| Schedule | 1 | 2 | 0 | 3 |
| Resource | 0 | 2 | 1 | 3 |
| External | 1 | 1 | 0 | 2 |
| **Total** | **4** | **8** | **2** | **14** |

## Risk Matrix

```
         │ Low Impact │ Med Impact │ High Impact │
─────────┼────────────┼────────────┼─────────────┤
High Prob│    R-08    │   R-03     │    R-01     │
─────────┼────────────┼────────────┼─────────────┤
Med Prob │    R-14    │ R-04, R-05 │ R-02, R-06  │
─────────┼────────────┼────────────┼─────────────┤
Low Prob │    R-12    │   R-09     │    R-07     │
─────────┴────────────┴────────────┴─────────────┘
```
~~~

### Template — risk detail (R-01 exemplar)

```markdown
<!-- …continued: per-risk detail -->
## High Priority Risks 🔴

### R-01: OAuth Provider API Breaking Changes
| Attribute | Value |
|-----------|-------|
| Category | External |
| Probability | High (70%) |
| Impact | High |
| Risk Score | 9/10 |
| Owner | Tech Lead |

**Description**: OAuth providers (Okta, Azure AD) may release breaking API changes during implementation.

**Triggers**:
- Provider announces deprecation
- API version upgrade required
- Authentication failures in production

**Impact Analysis**:
- 2-4 week delay if major changes
- Potential security vulnerabilities
- Customer trust impact
```

#### R-01 — mitigation, contingency, and sibling risks

```markdown
<!-- …continued: R-01 responses -->
**Mitigation Strategies**:
1. **Avoid**: Abstract provider interface for easy switching
2. **Reduce**: Subscribe to provider changelogs
3. **Transfer**: Use well-maintained SDK libraries
4. **Accept**: Plan contingency time in schedule

**Contingency Plan**:
- Fallback to basic auth temporarily
- Escalate to provider support
- Communicate delays to stakeholders

**Status**: Actively monitored

---

<!-- repeat per high risk: R-02 (e.g., Key Developer Unavailability, Category Resource, Prob Medium 40%, Impact High, Score 7/10, Owner PM) — same shape as R-01: attribute table, Description, Mitigation Strategies, Contingency Plan, Status -->
```

### Template — medium priority risks

```markdown
<!-- …continued: medium priority risks -->
## Medium Priority Risks ⚠️

### R-03: Integration Testing Delays
| Attribute | Value |
|-----------|-------|
| Category | Technical |
| Probability | High (60%) |
| Impact | Medium |
| Risk Score | 6/10 |

**Description**: Integration testing with enterprise identity providers may take longer than estimated.

**Mitigation**:
- Set up test tenants early
- Create mock providers for development
- Parallel testing with multiple providers

---

<!-- repeat per medium risk: R-04.. (e.g., Scope Creep from Stakeholders, Schedule, Medium 50%, Medium, 5/10) — same condensed shape as R-03: attribute table (no Owner), Description, Mitigation bullets -->
```

### Template — risk register

```markdown
<!-- …continued: risk register -->
## Risk Register

| ID | Risk | Category | Prob | Impact | Score | Owner | Status |
|----|------|----------|------|--------|-------|-------|--------|
| R-01 | OAuth API changes | External | H | H | 9 | Tech Lead | Monitor |
| R-02 | Dev unavailability | Resource | M | H | 7 | PM | Mitigate |
| R-03 | Testing delays | Technical | H | M | 6 | QA Lead | Mitigate |
| R-04 | Scope creep | Schedule | M | M | 5 | PM | Mitigate |
| R-05 | Security vulnerabilities | Technical | M | M | 5 | Security | Monitor |
| R-06 | Performance impact | Technical | M | H | 7 | Dev Lead | Mitigate |
| R-07 | Data migration issues | Technical | L | H | 5 | DBA | Accept |
| R-08 | Documentation gaps | Technical | H | L | 4 | Tech Writer | Accept |

---
```

### Template — response summary and monitoring

```markdown
<!-- …continued: response summary, monitoring plan -->
## Risk Response Summary

| Response | Count | Risks |
|----------|-------|-------|
| Avoid | 1 | R-01 |
| Reduce | 6 | R-02, R-03, R-04, R-05, R-06, R-08 |
| Transfer | 2 | R-01, R-07 |
| Accept | 3 | R-07, R-08, R-14 |

---

## Monitoring Plan

| Risk | Trigger | Monitor Frequency | Escalation |
|------|---------|-------------------|------------|
| R-01 | API deprecation notice | Weekly | Immediate to Tech Lead |
| R-02 | Resource allocation change | Daily | Within 24h to PM |
| R-03 | Test failures > 20% | Daily | Same day to QA Lead |
| R-06 | Response time > 500ms | Continuous | Within 1h to Dev Lead |

---
```

### Template — action items

```markdown
<!-- …continued: action items -->
## Action Items

| Priority | Action | Owner | Due Date |
|----------|--------|-------|----------|
| High | Set up OAuth provider test tenants | DevOps | Jan 10 |
| High | Document SSO architecture decisions | Tech Lead | Jan 12 |
| Medium | Create SSO knowledge transfer doc | Alice | Jan 15 |
| Medium | Define change control process | PM | Jan 13 |
```

## Risk Scoring

| Score | Level | Action Required |
|-------|-------|-----------------|
| 8-10 | Critical | Immediate mitigation |
| 5-7 | High | Active management |
| 3-4 | Medium | Monitor regularly |
| 1-2 | Low | Accept and track |

## Integration

This command works with:
- `/pm-sprint` - Include risk buffer
- `/release-notes` - Document known issues
- `/business-report` - Risk section

## Ethical Risk Category

When using `--include-ethics` or `--category ethical`, the assessment includes:

### Ethical Risk Types

| Risk Type | Description | Examples |
|-----------|-------------|----------|
| **User Harm** | Potential for direct user harm | Privacy violation, data exposure |
| **Manipulation** | Potential for user manipulation | Dark patterns, deceptive UX |
| **Autonomy** | Impact on user autonomy | Dependency creation, choice limitation |
| **Fairness** | Bias or discrimination potential | Algorithmic bias, unequal treatment |
| **Transparency** | Honesty and disclosure issues | Hidden data collection, misleading info |

### Ethical Risk Assessment Output

```markdown
## Ethical Risks 🔵

### E-01: User Privacy Exposure
| Attribute | Value |
|-----------|-------|
| Category | Ethical - Privacy |
| Probability | Medium (40%) |
| Impact | High |
| Risk Score | 7/10 |
| Constitutional Principle | Harm Avoidance |

**Description**: Feature collects location data without explicit user consent.

**Constitutional Analysis**:
- Violates: User autonomy, informed consent
- Principle: "Respect user's right to make informed decisions"
- Hard Constraint: No (but significant concern)

**Mitigation**:
1. Add explicit opt-in consent dialog
2. Provide clear data usage explanation
3. Allow granular permissions control

**Ethics Review**: Recommended before implementation
```

### Hard Constraint Risks

These are NEVER acceptable regardless of mitigation:

| Hard Constraint | Risk Classification |
|-----------------|---------------------|
| CSAM facilitation | Absolute prohibition |
| Weapons of mass destruction | Absolute prohibition |
| Critical infrastructure attacks | Absolute prohibition |
| Undermining AI oversight | Absolute prohibition |

If hard constraint risk is identified: **IMMEDIATE STOP** - escalate to stakeholder and user.

## Integration

This command works with:
- `/pm-sprint` - Include risk buffer
- `/release-notes` - Document known issues
- `/business-report` - Risk section
- `/ethics-review` - Deep ethical analysis
- `/ethics-review --lens harm` - Detailed harm evaluation

