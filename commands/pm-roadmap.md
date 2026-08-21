---
name: pm-roadmap
description: Create or update product roadmap with timeline, milestones, and dependencies
argument-hint: '[--quarter Q1-Q4] [--format timeline|list]'
model: sonnet
allowed-tools: Read, Glob, Grep, Write
related:
  - agents/product-manager.md
  - commands/pm-prioritize.md
  - commands/pm-requirements.md
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
- `--platform <apple|android|web|systems|backend|ai|all>` - Target platform context (default: all)

## Examples

```
/pm-roadmap
/pm-roadmap --quarter Q1 --view timeline
/pm-roadmap --add "Dark Mode" --quarter Q1
/pm-roadmap --move F-12 --to Q2 --export
```

## Output Format

### Timeline View (default)

Open with `# Product Roadmap {Year}` and a one-paragraph `## Vision`, then one block per quarter, then the dependencies map, risk register, and status legend.

#### Quarter block — repeat per quarter

~~~markdown
## Q1 {Year}: Foundation & Security

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
```

### Features
| Feature | Status | Owner | Target | Dependencies |
|---------|--------|-------|--------|--------------|
| SSO Integration | 🟡 In Progress | Auth Team | Jan 31 | - |
| Security Audit | 🔵 Planned | Security | Feb 15 | SSO |

### Key Results
- [ ] 100% enterprise security compliance
- [ ] 40% dark mode adoption
~~~

#### Quarter block — later quarters

Same shape, with Themes naming that quarter's strategic bet (growth & collaboration, intelligence & scale, polish & expansion). The ASCII milestone timeline is optional beyond the current quarter, and the Dependencies column can be dropped once nothing cross-links.

#### Dependencies, risks, legend

~~~markdown
## Dependencies Map
Indented tree, blocker above dependent:

```
SSO Integration
    └── Security Audit
         └── Enterprise Dashboard
```

## Risk Register
Table Risk | Impact | Probability | Mitigation — roadmap-level risks only
(delivery slips, scope creep, cost). `/pm-risk` produces the scored register.

## Status Legend
🟢 Complete · 🟡 In Progress · 🔵 Planned · 🔴 At Risk · ⚪ Blocked
~~~

### Kanban View

```markdown
# Roadmap Kanban

| Backlog | Q1 | Q2 | Q3 | Q4 | Done |
|---------|-----|-----|-----|-----|------|
| Feature X | SSO | Mobile | AI | i18n | Auth v1 |
| Feature Y | Dark Mode | Search | Dashboard | Marketplace | Onboarding |
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
- `/pm-sprint` - Break roadmap into sprints
