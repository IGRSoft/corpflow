---
name: design-review
description: Conduct a comprehensive design review for screens, components, or features
argument-hint: '<screen, component, or feature> [--focus ui|ux|a11y|system] [--depth quick|standard|comprehensive] [--platform apple|android|web|all]'
allowed-tools: Read, Glob, Grep, Task(corpflow:designer)
related:
  - agents/designer.md
  - commands/design-specs.md
  - commands/design-accessibility.md
---

# Design Review Command

Comprehensive design review of a screen, component, or feature, run through the designer agent.

## Options

| Option | Values | Effect |
|--------|--------|--------|
| `--focus` | `ui`, `ux`, `a11y`, `system` | Review focus area (default: all) |
| `--depth` | `quick`, `standard`, `comprehensive` | Review depth (default: standard) |
| `--platform` | `apple`, `android`, `web`, `all` | Target platform (default: all) |

```
/design-review <screen, component, or feature> [--focus ui|ux|a11y|system] [--depth quick|standard|comprehensive] [--platform apple|android|web|all]
/design-review LoginScreen
/design-review "Settings feature" --focus ux --depth comprehensive
/design-review Button component --focus system
/design-review Checkout --focus a11y --platform web
```

## Procedure

1. **Gather context** — when `.context/designs/mockup-*.pen` exists, delegate the read: `Task(corpflow:designer)` with "read the mockups for `<target>` and return a ≤400-token structural and visual summary — frames, states, tokens used, deviations from the design system. Write nothing." No mockup present → skip the delegation and read the source or spec directly. Then identify the target's design patterns, design-system usage, and platform considerations.
2. **Review and report** — run `agents/designer.md` at the selected focus and depth against the criteria below, then emit every § Output Format section. Each § Review Criteria row selected by `--focus` carries a verdict line — pass, a finding, or `not applicable: <reason>` — and each finding names the screen or component, the criterion it fails, and a before/after. A row with no verdict means the review is unfinished, not that it passed.

## Review Criteria

| Focus | Checks |
|-------|--------|
| `ui` | Visual hierarchy and layout; typography and color usage; spacing and alignment consistency; icon and asset quality; dark mode support |
| `ux` | User flow clarity; interaction patterns; error handling and feedback; loading states; navigation consistency |
| `a11y` | WCAG 2.2 AA, color contrast, touch target sizes, screen reader support, keyboard navigation — full checklist in `commands/design-accessibility.md` |
| `system` | Component library adherence; token usage (colors, spacing, typography); pattern consistency; reusability assessment |

## Output Format

```markdown
# Design Review: [Target]

## Executive Summary
- Overall assessment: [Good/Needs Work/Critical Issues]
- Key strengths: [List]
- Priority improvements: [List]

## Findings

### Critical (P0)
- [Issue]: [Impact] → [Recommendation]

<!-- repeat per priority, same shape: High (P1), Medium (P2), Low (P3) -->

## Recommendations
1. [Actionable item with owner]
2. [Actionable item with owner]

## Next Steps
- [Immediate actions]
- [Follow-up reviews needed]
```

Target: $ARGUMENTS
