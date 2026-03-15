---
name: pm-roadmap
description: Create or update product roadmap with timeline, milestones, and dependencies
argument-hint: '[--quarter Q1-Q4] [--format timeline|list]'
model: sonnet
allowed-tools: Read, Glob, Grep, Write
---

# PM Roadmap Command

Create or update product roadmap with timeline, milestones, and dependencies.

## Usage

```
/pm-roadmap
/pm-roadmap --quarter [Q1|Q2|Q3|Q4]
/pm-roadmap --add "Feature" --quarter Q2
/pm-roadmap --view [timeline|kanban|list]
```

## Options

- `--quarter <Q>` - Focus on specific quarter
- `--add "feature"` - Add item to roadmap
- `--move <id> --to <quarter>` - Move item between quarters
- `--view <type>` - Display format (default: timeline)
- `--export` - Export roadmap
- `--platform <apple|android|web|all>` - Target platform context (default: all)

## Examples

```
/pm-roadmap
/pm-roadmap --quarter Q1 --view timeline
/pm-roadmap --add "Dark Mode" --quarter Q1
```

## Output Format

### Timeline View (Default)
```markdown
# Product Roadmap [Year]

## Vision
Become the leading platform for team collaboration with enterprise-grade security and delightful user experience.

---

## Q1 [Year]: Foundation & Security

### Themes
- Enterprise readiness
- Core UX improvements

### Milestones

```
Jan ──────────────── Feb ──────────────── Mar
│                     │                     │
▼                     ▼                     ▼
[SSO Integration]─────┘                     │
   └──[Security Audit]────────┘             │
         └──[Dark Mode]───────────────────┘
              └──[Performance v1]─────────┘
```

### Features

| Feature | Status | Owner | Target | Dependencies |
|---------|--------|-------|--------|--------------|
| SSO Integration | 🟡 In Progress | Auth Team | Jan 31 | - |
| Security Audit | 🔵 Planned | Security | Feb 15 | SSO |
| Dark Mode | 🔵 Planned | Frontend | Feb 28 | Design system |
| Performance v1 | 🔵 Planned | Platform | Mar 15 | - |

### Key Results
- [ ] 100% enterprise security compliance
- [ ] 40% dark mode adoption
- [ ] 20% performance improvement

---

## Q2 [Year]: Growth & Collaboration

### Themes
- Team collaboration
- User growth features

### Features

| Feature | Status | Owner | Target | Dependencies |
|---------|--------|-------|--------|--------------|
| Real-time Collab | 🔵 Planned | Core Team | Apr 30 | - |
| Advanced Search | 🔵 Planned | Search Team | May 15 | - |
| Mobile App v1 | 🔵 Planned | Mobile | Jun 30 | API v2 |
| API v2 | 🔵 Planned | Platform | May 31 | - |

### Key Results
- [ ] 50% increase in team collaboration metrics
- [ ] 25% increase in user retention
- [ ] Mobile app launched in App Store

---

## Q3 [Year]: Intelligence & Scale

### Themes
- AI-powered features
- Enterprise scale

### Features

| Feature | Status | Owner | Target |
|---------|--------|-------|--------|
| AI Assistant | 🔵 Planned | AI Team | Jul 31 |
| Enterprise Dashboard | 🔵 Planned | Enterprise | Aug 31 |
| Advanced Analytics | 🔵 Planned | Data | Sep 15 |

---

## Q4 [Year]: Polish & Expansion

### Themes
- Platform maturity
- Market expansion

### Features

| Feature | Status | Owner | Target |
|---------|--------|-------|--------|
| Integrations Marketplace | 🔵 Planned | Platform | Oct 31 |
| White-label Support | 🔵 Planned | Enterprise | Nov 30 |
| Localization (10 languages) | 🔵 Planned | i18n | Dec 15 |

---

## Dependencies Map

```
SSO Integration
    └── Security Audit
         └── Enterprise Dashboard

Design System
    └── Dark Mode
         └── Mobile App v1

API v2
    └── Mobile App v1
    └── Integrations Marketplace
```

---

## Risk Register

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| SSO delays | High | Medium | Start security audit in parallel |
| Mobile scope creep | Medium | High | Strict MVP definition |
| AI model costs | Medium | Medium | Usage-based pricing model |

---

## Status Legend

| Icon | Status |
|------|--------|
| 🟢 | Complete |
| 🟡 | In Progress |
| 🔵 | Planned |
| 🔴 | At Risk |
| ⚪ | Blocked |
```

### Kanban View
```markdown
# Roadmap Kanban

| Backlog | Q1 | Q2 | Q3 | Q4 | Done |
|---------|-----|-----|-----|-----|------|
| Feature X | SSO | Mobile | AI | i18n | Auth v1 |
| Feature Y | Dark Mode | Search | Dashboard | Marketplace | Onboarding |
| | Perf v1 | API v2 | Analytics | White-label | |
```

## Roadmap Item States

| State | Meaning |
|-------|---------|
| Backlog | Not yet scheduled |
| Planned | Scheduled for quarter |
| In Progress | Active development |
| At Risk | May miss target |
| Blocked | Waiting on dependency |
| Complete | Delivered |

## Integration

This command works with:
- `/pm-prioritize` - Prioritize before adding to roadmap
- `/pm-requirements` - Detail features on roadmap
- `/sprint-plan` - Break roadmap into sprints

## Related

- [product-manager](../agents/product-manager.md) - Product expertise
- [pm-prioritize](./pm-prioritize.md) - Prioritization
- [pm-requirements](./pm-requirements.md) - Requirements
