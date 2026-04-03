# Compression Examples & Anti-Patterns

## Before/After: Requirements Handoff

**Before (850 tokens)**:
```markdown
# Feature Requirements

## Background
Over the past several months, we have received numerous user requests
for a dark mode feature. Analysis of our user feedback indicates that
approximately 40% of users have explicitly requested this feature...

## User Stories
### Story 1: Enable Dark Mode
As a user who prefers dark interfaces, I want to be able to enable
dark mode in the application settings so that I can reduce eye strain
when using the app at night...

[continues for 3 more paragraphs per story]
```

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

Details: .context/planning.md
```

## Before/After: Architecture Handoff

**Before (1,200 tokens)**:
```markdown
# Architecture Decision

## Options Considered

### Option 1: CSS Variables Approach
We could use CSS variables to define all colors...
[200 words explaining approach]

### Option 2: Theme Protocol
We could define a ThemeProtocol...
[200 words explaining approach]

### Option 3: Color Palette Abstraction
We could create a ColorPalette class...
[200 words explaining approach]

## Analysis
Comparing these options across several dimensions...
[300 words of analysis]

## Decision
After careful consideration, we have decided to go with Option 3...
[150 words of rationale]
```

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

ADR: .context/analyzing.md#adr-theme-system
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
Code:     path/file.swift:functionName()
Decision: "[What] because [why in <10 words]"
Artifact: .context/[stage].md#section
ADR:      ADR-NNN: [title] - [status]
Pattern:  "[Pattern Name]" - see analyzing.md
```

### Token Estimation

```
Content Type          | Est. Tokens
----------------------|------------
One-line reference    | 10-20
Bullet point          | 15-30
Short paragraph       | 50-100
Full function         | 100-500
Full file             | 500-2000
Complete ADR          | 300-500
Handoff summary       | 50-100 (target)
```
