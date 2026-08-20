# Compression Examples & Anti-Patterns

Worked pairs, formats, and anti-patterns backing `../SKILL.md § Core Principles`, `§ Handoff Template`, and `§ Compression Techniques by Content Type`.

## Before/After: Requirements Handoff

**Before (850 tokens)**: background paragraphs on user demand, then each requirement as a 3-paragraph prose user story ("As a user who prefers dark interfaces, I want… so that…").

**After (180 tokens)**:

```markdown
## PL0: Planning Complete

### Requirements
- REQ-1: Dark mode toggle in Settings
- REQ-2: Theme persistence across sessions
- REQ-3: System preference respect (optional)

### Context
- 40% user demand, P1 priority
- iOS 15+ support required
- MVP scope: Settings screen only

### For Architecture
Q: Independent toggle vs system-linked preference?
Constraint: Cannot modify existing ColorConstants

Details: .context/<plan_file> (e.g. planning-0.md)
```

## Before/After: Architecture Handoff

**Before (1,200 tokens)**: three options (CSS variables, theme protocol, palette abstraction) at ~200 words each, 300 words of cross-dimension analysis, 150 words of rationale for the winner.

**After (200 tokens)**:

```markdown
## AR3: Architecture Complete

### Decision: ColorPalette Abstraction
Selected: ColorPalette class with theme variants
Rejected: CSS vars (iOS incompatible), Protocol (over-engineered)

### Implementation Notes
- New: `ThemeManager`, `ColorPalette`, `Theme` enum
- Modified: `AppDelegate` (theme init), `SettingsVC` (toggle)
- Pattern: Singleton manager + value type palettes

### For Development
Files to create: 3 | Files to modify: 2
Entry point: ThemeManager.swift
Test focus: Theme switching, persistence

ADR: .context/architecture-N.md#adr-theme-system
```

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|--------------|---------|-----|
| **Full file dumps** | Wastes 500-2000 tokens per file | Reference by path |
| **Complete ADRs inline** | 300-500 tokens each | Reference + one-line summary |
| **Explaining obvious decisions** | Unnecessary tokens | Only document non-obvious choices |
| **Historical context every handoff** | Compounds over stages | Include only for first handoff, then reference |
| **Prose over lists** | 2-3x more tokens | Use structured formats |
| **Including rejected alternatives** | Low value, high cost | Mention names only |

## Quick Reference Card

### Compression Checklist

Before handoff:
- [ ] Replace inline code with file:line references
- [ ] Summarize decisions to one line + rationale phrase
- [ ] Convert prose to bullet points
- [ ] Reference artifacts instead of duplicating
- [ ] Remove historical context (reference if needed)
- [ ] Check against budget for this handoff

### Reference Formats

```
Code:         src/auth/AuthManager.swift — validateToken(), refreshToken() modified; +45/−12;
              key change: token expiry validation; tests: AuthManagerTests.swift (3 new cases)
Planning:     REQ-1..REQ-N one-liners; acceptance: <plan_file>#acceptance; risks: N — #risks
Architecture: Pattern: MVVM with Coordinator; components: ThemeManager (new), ColorPalette
              (modified); deps: none added; ADR-001 ACCEPTED
Decision:     "[What] because [why in <10 words]"
Artifact:     .context/[stage].md#section
ADR:          ADR-NNN: [title] - [status]
```

### Token Estimation

One-line reference 10-20 · bullet point 15-30 · short paragraph 50-100 · full function 100-500 · full file 500-2000 · complete ADR 300-500 · handoff summary 50-100 (the target).
