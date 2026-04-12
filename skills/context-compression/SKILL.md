---
name: context-compression
description: Techniques for compressing context between agent handoffs while preserving critical information. Apply for efficient stage transitions and context window management.
effort: medium
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

### Example Handoff: PL→AR

```markdown
## Stage PL Complete

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
| **PL→AR** | 500 | Requirements, constraints, user needs |
| **AR→TL** | 300 | Architecture decisions, patterns, risks |
| **TL→DV** | 400 | Implementation approach, file assignments, deadlines |
| **DV→QA** | 300 | What changed, test focus areas, edge cases |
| **QA→DC** | 200 | Test results summary, documentation needs |
| **DC→FN** | 200 | Doc changes, release items, changelog |
| **FN→ST** | 150 | Executive summary, approval checklist |

### Extended Context Budget (1M Window)

When running on Opus 4.6 with Max/Team/Enterprise plans, the context window is 1M tokens. Handoff budgets scale proportionally:

| Handoff | Standard Budget | Extended Budget (1M) |
|---------|----------------|---------------------|
| **PL→AR** | 500 | 2,000 |
| **AR→TL** | 300 | 1,200 |
| **TL→DV** | 400 | 1,600 |
| **DV→QA** | 300 | 1,200 |
| **QA→DC** | 200 | 800 |
| **DC→FN** | 200 | 800 |
| **FN→ST** | 150 | 600 |

> Use extended budgets only when complexity warrants it — standard budgets are still preferred for cost efficiency. Compression remains a best practice regardless of window size.

## Exploration Cache Budget

| Content Type | Token Budget | Technique |
|-------------|-------------|-----------|
| File inventory | 100-200 | Path + one-line description table |
| Key interfaces | 200-500 | Code snippets for enums/protocols only |
| Patterns | 100-200 | One-liner per pattern with file:line ref |
| External context | 100-300 | Summarized design/Figma/user decisions |
| **Total** | **500-1200** | |

### Anti-Patterns for exploration.md

| Anti-Pattern | Problem | Fix |
|-------------|---------|-----|
| Full file contents | 500-2000 tokens/file | Include only interfaces/enums (< 30 lines) |
| Implementation details | Low reuse across stages | Use file:line references |
| Build commands | Already in CLAUDE.md | Don't duplicate |
| Architecture decisions | Belongs in analyzing.md | Only include patterns/facts |

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
| Post-compaction | Deferred tool schemas preserved — no need to re-fetch after compaction |
| Auto-compact thrash | v2.1.89 detects when context refills immediately after compaction 3 times and stops with actionable error instead of burning API calls |
| Focus mode | Focus view (Ctrl+O) generates self-contained summaries; v2.1.101 improves completeness |
| Compaction duplicates | Compaction no longer produces duplicate transcript entries (fixed v2.1.97) |

### PostCompact Hook

The `PostCompact` hook fires after automatic context compaction completes. Use it for workflow context recovery:

```json
{
  "hooks": {
    "PostCompact": [
      {
        "hooks": [
          { "type": "command", "command": "./tools/post-compact-recovery.sh" }
        ]
      }
    ]
  }
}
```

Use cases: re-inject critical task state, log compression metrics, recover workflow context in long multi-stage sessions.

### Context Size Estimation

Rough token counts:
- 1 word ≈ 1.3 tokens
- 1 line of code ≈ 10 tokens
- 1 paragraph ≈ 50-100 tokens
- 1 file ≈ 500-2000 tokens

See references/ for detailed before/after compression examples, anti-patterns, and quick reference card.
