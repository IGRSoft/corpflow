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
- `--platform <apple|android|web|systems|backend|ai|all>` - Target platform context (default: all)
- `--include-ethics` - Include ethical risk assessment (recommended for user-facing features)

## Examples

```
/pm-risk
/pm-risk "SSO Implementation Project" --include-ethics
/pm-risk --report --threshold high --category technical
/pm-risk --update --platform apple
```

## Output Format

Emit in this order: summary counts, risk matrix, per-risk detail (high then medium), register, response summary, monitoring plan, action items.

### Summary and matrix

~~~markdown
# Risk Assessment: {Project}

## Risk Summary

| Category | High | Medium | Low | Total |
|----------|------|--------|-----|-------|
| Technical | 2 | 3 | 1 | 6 |
| ...one row per category: Schedule, Resource, External, Ethical... |
| **Total** | **4** | **8** | **2** | **14** |

## Risk Matrix

```
          │ Low Impact │ Med Impact │ High Impact │
High Prob │    R-08    │    R-03    │    R-01     │
Med Prob  │    R-14    │ R-04, R-05 │ R-02, R-06  │
Low Prob  │    R-12    │    R-09    │    R-07     │
```
~~~

### Per-risk detail

```markdown
## High Priority Risks 🔴

### R-01: OAuth Provider API Breaking Changes
| Attribute | Value |
|-----------|-------|
| Category | External |
| Probability | High (70%) |
| Impact | High |
| Risk Score | 9/10 |
| Owner | Tech Lead |

**Description**: OAuth providers (Okta, Azure AD) may ship breaking API changes mid-implementation.

**Triggers**: deprecation notice · API version upgrade required · production auth failures

**Impact Analysis**: 2-4 week delay · potential security vulnerabilities · customer trust

**Mitigation Strategies**: **Avoid** — abstract the provider interface · **Reduce** — track changelogs · **Transfer** — use maintained SDKs · **Accept** — budget contingency time

**Contingency Plan**: temporary fallback auth · escalate to provider support · tell stakeholders

**Status**: Actively monitored
```

#### Per-risk detail — medium risks

Repeat the shape per high risk. Medium risks go under `## Medium Priority Risks ⚠️` minus the Owner row, Triggers, and Contingency Plan — attribute table, Description, and a short **Mitigation** list only.

### Register, monitoring, actions

```markdown
## Risk Register

| ID | Risk | Category | Prob | Impact | Score | Owner | Status |
|----|------|----------|------|--------|-------|-------|--------|
| R-01 | OAuth API changes | External | H | H | 9 | Tech Lead | Monitor |
| R-02 | Dev unavailability | Resource | M | H | 7 | PM | Mitigate |
| ...one row per risk, sorted by score; Status ∈ Monitor|Mitigate|Accept...

## Risk Response Summary

| Response | Count | Risks |
|----------|-------|-------|
| Reduce | 6 | R-02, R-03, R-04, R-05, R-06, R-08 |
| ...one row per response type: Avoid, Reduce, Transfer, Accept...

## Monitoring Plan

| Risk | Trigger | Monitor Frequency | Escalation |
|------|---------|-------------------|------------|
| R-01 | API deprecation notice | Weekly | Immediate to Tech Lead |

## Action Items

| Priority | Action | Owner | Due Date |
|----------|--------|-------|----------|
| High | Set up OAuth provider test tenants | DevOps | {date} |
```

## Risk Scoring

| Score | Level | Action Required |
|-------|-------|-----------------|
| 8-10 | Critical | Immediate mitigation |
| 5-7 | High | Active management |
| 3-4 | Medium | Monitor regularly |
| 1-2 | Low | Accept and track |

## Ethical Risk Category

`--include-ethics` or `--category ethical` adds an `## Ethical Risks 🔵` section (IDs `E-01`…) covering:

| Risk Type | Signals |
|-----------|---------|
| **User Harm** | Privacy violation, data exposure |
| **Manipulation** | Dark patterns, deceptive UX |
| **Autonomy** | Dependency creation, choice limitation |
| **Fairness** | Algorithmic bias, unequal treatment |
| **Transparency** | Hidden data collection, misleading info |

Each ethical risk uses the per-risk shape plus a `Constitutional Principle` attribute row, a **Constitutional Analysis** block (principle violated, the principle quoted, whether a hard constraint applies), and an **Ethics Review** recommendation.

### Hard constraint risks

Never acceptable regardless of mitigation. The canonical list is `commands/ethics-review.md § Hard Constraint Violations` (CSAM, weapons of mass destruction, critical-infrastructure attacks, undermining AI oversight, and the rest). If one is identified: **IMMEDIATE STOP** — escalate to stakeholder and user.

## Integration

This command works with:
- `/pm-sprint` - Include risk buffer
- `/docs-release-notes` - Document known issues
- `/business-report` - Risk section
- `/ethics-review` - Deep ethical analysis; `--lens harm` for detailed harm evaluation
