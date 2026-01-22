---
name: context-compression
description: Techniques for compressing context between agent handoffs while preserving critical information. Apply for efficient stage transitions and context window management.
---

# Context Compression

Systematic approaches for managing context across agent handoffs, optimizing token usage while preserving decision-critical information.

## Core Principles

### 1. Reference, Don't Duplicate

**Rule**: Point to artifacts instead of including their content.

```
Before (1,200 tokens):
"The authentication implementation includes the following code:
[entire 50-line function pasted here]
which handles JWT validation..."

After (45 tokens):
Auth implementation: `src/auth/jwt.swift:validateToken()`
Key behavior: Validates JWT, returns decoded payload or throws AuthError
```

### 2. Summarize Decisions, Not Deliberation

**Rule**: Capture the WHY and WHAT, not the full discussion.

```
Before (800 tokens):
"After considering several authentication approaches including
session-based auth, API keys, OAuth, and JWT, we analyzed the
tradeoffs of each. Session-based requires server state which
conflicts with our microservice architecture. API keys lack
rotation capabilities. OAuth adds complexity for our use case.
Therefore, we selected JWT because..."

After (120 tokens):
## Auth Decision: JWT
**Selected**: JWT tokens
**Rejected**: Sessions (stateful), API keys (no rotation), OAuth (overkill)
**Rationale**: Stateless, rotatable, fits microservice architecture
**ADR**: .context/analyzing.md#adr-001
```

### 3. Use Structured Formats

**Rule**: Consistent templates compress better than prose.

```
Before (400 tokens): Free-form paragraph about requirements
After (150 tokens): Bulleted acceptance criteria checklist
```

## Handoff Template

Standard format for stage transitions (target: 50-100 tokens):

```markdown
## Stage [X] Complete

### Decisions Made
- [Key decision 1 with rationale in <10 words]
- [Key decision 2]

### Artifacts Created
- `.context/[artifact].md` - [one-line purpose]

### Open Questions for Next Stage
- [Question requiring input]

### Constraints Identified
- [Technical or business constraint]

### Recommended Focus
[One sentence: what the next stage should prioritize]
```

### Example Handoff: P→A

```markdown
## Stage P Complete

### Decisions Made
- Feature scope: Dark mode for settings screen only (MVP)
- Priority: P1 - user-requested, affects 40% of users

### Artifacts Created
- `.context/planning.md` - Requirements and acceptance criteria

### Open Questions for A Stage
- Should dark mode respect system preference or be independent toggle?

### Constraints Identified
- Must support iOS 15+ (no newer APIs)
- Cannot change existing color constants (breaking change)

### Recommended Focus
Design color abstraction layer that supports both themes without breaking existing UI.
```

## Compression Techniques by Content Type

### For Code Context

| Content Type | Before | After | Reduction |
|--------------|--------|-------|-----------|
| Full file | Paste entire file | `path/to/file.swift` | 95% |
| Function | Paste function body | `ClassName.methodName()` signature only | 80% |
| Changes | Full diff | "Changed 15 lines in 3 functions" | 70% |
| Structure | Describe all classes | Class diagram reference | 85% |

**Code Reference Format**:
```
File: src/auth/AuthManager.swift
Functions modified: validateToken(), refreshToken()
Lines changed: 45 additions, 12 deletions
Key change: Added token expiry validation
Tests: AuthManagerTests.swift (3 new cases)
```

### For Planning Context

| Content Type | Before | After | Reduction |
|--------------|--------|-------|-----------|
| User stories | Full Gherkin format | "As [role], I need [goal]" one-liner | 60% |
| Requirements | Paragraphs | Numbered checklist | 50% |
| Acceptance criteria | Prose | Checkbox list | 40% |
| Risks | Full analysis | "Risk: [name] - Mitigation: [action]" | 70% |

**Planning Reference Format**:
```
## Requirements Summary
- REQ-1: User can toggle dark mode in settings
- REQ-2: Theme persists across app restarts
- REQ-3: Respects system appearance preference (configurable)

Acceptance: 5 criteria in planning.md#acceptance
Risks: 2 identified (compatibility, migration) - see planning.md#risks
```

### For Architecture Context

| Content Type | Before | After | Reduction |
|--------------|--------|-------|-----------|
| ADR | Full document | "ADR-001: [title] - Status: [accepted]" | 80% |
| Diagram | ASCII/Mermaid inline | "See analyzing.md#system-diagram" | 90% |
| Patterns | Full explanation | "Pattern: Repository + Factory" | 85% |
| Dependencies | Full analysis | "New deps: [lib1], [lib2]" | 75% |

**Architecture Reference Format**:
```
## Architecture Summary
Pattern: MVVM with Coordinator
Key components: ThemeManager (new), ColorPalette (modified)
Dependencies: None added
ADRs: ADR-001 (theme abstraction) - ACCEPTED

Details: .context/analyzing.md
```

## Context Budget by Handoff

Maximum tokens to pass between stages:

| Handoff | Max Tokens | Focus Areas |
|---------|------------|-------------|
| **P→A** | 500 | Requirements, constraints, user needs |
| **A→T** | 300 | Architecture decisions, patterns, risks |
| **T→D** | 400 | Implementation approach, file assignments, deadlines |
| **D→Q** | 300 | What changed, test focus areas, edge cases |
| **Q→W** | 200 | Test results summary, documentation needs |
| **W→F** | 200 | Doc changes, release items, changelog |
| **F→S** | 150 | Executive summary, approval checklist |

### Budget Enforcement

When context exceeds budget:

1. **Identify lowest-priority content**
   - Historical context (why we're here)
   - Alternative approaches considered
   - Detailed rationale for obvious decisions

2. **Apply aggressive compression**
   - Replace inline content with artifact references
   - Remove "obvious" decisions (keep non-obvious ones)
   - Summarize lists longer than 5 items

3. **Preserve critical context**
   - Current stage requirements
   - Open questions
   - Error context (if any)
   - User-stated preferences

## Compression Triggers

### Automatic Compression Points

| Trigger | Action |
|---------|--------|
| Stage handoff | Compress previous stage to budget |
| Context > 50% window | Summarize completed stages |
| Error retry | Trim non-essential context |
| User request | Manual compression |

### Context Size Estimation

Rough token counts:
- 1 word ≈ 1.3 tokens
- 1 line of code ≈ 10 tokens
- 1 paragraph ≈ 50-100 tokens
- 1 file ≈ 500-2000 tokens

## Compression Examples

### Before/After: Requirements Handoff

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
## P3: Planning Complete

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

### Before/After: Architecture Handoff

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
## A3: Architecture Complete

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
