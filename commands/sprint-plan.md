---
name: sprint-plan
description: Plan sprint with capacity analysis, task breakdown, and resource allocation
argument-hint: <sprint name or number>
model: sonnet
---

# Sprint Plan Command

Plan sprint with capacity analysis, task breakdown, and resource allocation.

## Usage

```
/sprint-plan
/sprint-plan --capacity <points>
/sprint-plan --from-backlog <file>
/sprint-plan --duration [1|2|3|4] weeks
```

## Options

- `--capacity <points>` - Team capacity in story points
- `--from-backlog <file>` - Import items from backlog file
- `--duration <weeks>` - Sprint duration (default: 2)
- `--include-debt` - Include tech debt allocation
- `--export` - Export sprint plan

## Examples

```
/sprint-plan
/sprint-plan --capacity 40 --duration 2
/sprint-plan --from-backlog backlog.md --include-debt
```

## Output Format

```markdown
# Sprint Plan: Sprint [ID]

## Sprint Overview

| Attribute | Min | Max |
|-----------|-----|-----|
| Sprint | [Sprint ID] | |
| Duration | Jan 13 - Jan 24 (2 weeks) | |
| Team Capacity | 36 SP | 40 SP |
| Committed | 30 SP | 38 SP |
| Buffer | 2 points (5%) | 2 points (5%) |

---

## Goals

### Sprint Goals
1. Complete SSO integration for enterprise customers
2. Fix critical performance issues in dashboard
3. Ship dark mode MVP

### Success Criteria
- [ ] SSO working with Okta and Azure AD
- [ ] Dashboard load time < 2s
- [ ] Dark mode toggle functional

---

## Capacity Planning

### Team Capacity

| Team Member | Available Days | Capacity Min | Capacity Max | Notes |
|-------------|----------------|-------------|-------------|-------|
| Alice | 10 | 8 | 10 | Full capacity |
| Bob | 8 | 6 | 8 | PTO Jan 20-21 |
| Carol | 10 | 8 | 10 | Full capacity |
| Dave | 6 | 5 | 6 | Conference Jan 15-16 |
| Eve | 6 | 5 | 6 | Part-time this sprint |
| **Total** | **40** | **32** | **40** | |

### Allocation

| Category | Pts Min | Pts Max | % | Notes |
|----------|---------|---------|---|-------|
| Features | 22 | 28 | 70% | Sprint goals |
| Tech Debt | 5 | 6 | 15% | Prioritized items |
| Bugs | 3 | 4 | 10% | Critical only |
| Buffer | 2 | 2 | 5% | Unexpected work |

---

## Sprint Backlog

### Features (22-28 pts)

| ID | Story | SP Min | SP Max | Assignee | Priority |
|----|-------|--------|--------|----------|----------|
| FEAT-101 | SSO: Okta integration | 5 | 8 | Alice | P0 |
| FEAT-102 | SSO: Azure AD integration | 3 | 5 | Alice | P0 |
| FEAT-103 | Dark mode: Core implementation | 5 | 8 | Carol | P1 |
| FEAT-104 | Dark mode: Settings toggle | 2 | 3 | Carol | P1 |
| FEAT-105 | Dashboard performance: Query optimization | 3 | 4 | Dave | P1 |

### Tech Debt (5-6 pts)

| ID | Item | SP Min | SP Max | Assignee | Priority |
|----|------|--------|--------|----------|----------|
| TD-015 | Refactor auth module | 2 | 3 | Bob | P2 |
| TD-018 | Add missing indexes | 1 | 2 | Dave | P1 |
| TD-021 | Update deprecated deps | 1 | 1 | Eve | P2 |

### Bugs (3-4 pts)

| ID | Bug | SP Min | SP Max | Assignee | Priority |
|----|-----|--------|--------|----------|----------|
| BUG-234 | Login timeout on slow networks | 1 | 2 | Bob | P1 |
| BUG-238 | Chart rendering issue in Safari | 1 | 2 | Eve | P2 |

---

## Daily Breakdown

### Week 1 (Jan 13-17)

| Day | Focus | Key Activities |
|-----|-------|----------------|
| Mon | Sprint start | Planning, SSO kickoff |
| Tue | Development | SSO Okta, Dark mode setup |
| Wed | Development | SSO Okta, Dark mode core |
| Thu | Development | SSO Okta complete, DB indexes |
| Fri | Review | SSO Okta review, dark mode progress |

### Week 2 (Jan 20-24)

| Day | Focus | Key Activities |
|-----|-------|----------------|
| Mon | Development | SSO Azure AD, Performance fixes |
| Tue | Development | SSO Azure AD, Bug fixes |
| Wed | Integration | SSO testing, Dark mode settings |
| Thu | Testing | Full integration testing |
| Fri | Sprint end | Demo, retro, release prep |

---

## Dependencies

```
FEAT-101 (SSO Okta)
    └── FEAT-102 (SSO Azure AD) - shares auth infrastructure

TD-018 (DB indexes)
    └── FEAT-105 (Query optimization) - needs indexes first

FEAT-103 (Dark mode core)
    └── FEAT-104 (Settings toggle) - UI depends on core
```

---

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| SSO provider API issues | Medium | High | Have test accounts ready |
| Scope creep on dark mode | Medium | Medium | Strict MVP scope |
| Team member availability | Low | Medium | Cross-training on SSO |

---

## Definition of Done

- [ ] Code complete and reviewed
- [ ] Unit tests passing (>80% coverage)
- [ ] Integration tests passing
- [ ] Documentation updated
- [ ] QA approved
- [ ] No critical/high bugs

---

## Ceremonies

| Ceremony | When | Duration |
|----------|------|----------|
| Sprint Planning | Jan 13, 9am | 2 hours |
| Daily Standup | Daily, 9:30am | 15 min |
| Backlog Refinement | Jan 16, 2pm | 1 hour |
| Sprint Review | Jan 24, 2pm | 1 hour |
| Retrospective | Jan 24, 3pm | 1 hour |

---

## Notes

- Alice leading SSO implementation
- Carol and Eve pairing on dark mode
- Dave focusing on performance this sprint
- Bob handling bugs and tech debt
```

## Capacity Guidelines

| Team Size | 2-week Capacity Min | 2-week Capacity Max | Buffer |
|-----------|---------------------|---------------------|--------|
| 3 devs | 18 pts | 30 pts | 3 pts |
| 5 devs | 30 pts | 50 pts | 5 pts |
| 7 devs | 42 pts | 70 pts | 7 pts |

## Integration

This command works with:
- `/pm-roadmap` - Break roadmap into sprints
- `/pm-prioritize` - Prioritize sprint items
- `/estimate` - Estimate story points

## Related

- [project-manager](../agents/project-manager.md) - Project management expertise
- [risk-assess](./risk-assess.md) - Risk assessment
- [release-notes](./release-notes.md) - Release documentation
