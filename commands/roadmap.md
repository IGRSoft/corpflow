---
name: roadmap
description: Create or update product roadmap with timeline, milestones, and dependencies
argument-hint: '[--quarter Q1|Q2|Q3|Q4] [--view timeline|kanban] [--add "<feature>"] [--move "<feature>" --to <quarter>]'
allowed-tools: Read, Glob, Grep, Write
related:
  - agents/product-manager.md
  - commands/product-requirements.md
  - commands/sprint.md
---

# Roadmap Command

Create or update product roadmap with timeline, milestones, and dependencies. The roadmap lives in
`.context/roadmap.md`, the only file this command writes: a run that finds none there creates it,
`--add` and `--move` update it in place, and any other run reads it and prints the selected view.

## Options

| Option | Values | Purpose |
|--------|--------|---------|
| `--quarter <Q>` | `Q1`, `Q2`, `Q3`, `Q4` | Focus on one quarter |
| `--add "<feature>"` | — | Add an item to the roadmap |
| `--move "<feature>" --to <quarter>` | feature name as in the Features table | Move that item to another quarter |
| `--view <type>` | `timeline`, `kanban` | Display format (default: `timeline`) |

```
/roadmap [--quarter Q1|Q2|Q3|Q4] [--view timeline|kanban] [--add "<feature>"] [--move "<feature>" --to <quarter>]
/roadmap
/roadmap --quarter Q1 --view timeline
/roadmap --add "Dark Mode" --quarter Q1
/roadmap --move "Dark Mode" --to Q2
/roadmap --quarter Q3 --view kanban
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
(delivery slips, scope creep, cost). Score them per
`skills/estimation-methodology/references/estimate-review.md § Risk Scoring`.

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
