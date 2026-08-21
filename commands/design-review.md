---
name: design-review
description: Conduct a comprehensive design review for screens, components, or features
argument-hint: '<screen, component, or feature>'
model: sonnet
allowed-tools: Read, Glob, Grep
related:
  - agents/designer.md
  - commands/design-specs.md
  - commands/design-accessibility.md
---

# Design Review Command

Comprehensive design review of a screen, component, or feature, run through the designer agent.

## Usage

```
/design-review [target] [options]
```

## Options

| Option | Values | Effect |
|--------|--------|--------|
| `--focus` | `ui`, `ux`, `a11y`, `system` | Review focus area (default: all) |
| `--depth` | `quick`, `standard`, `comprehensive` | Review depth (default: standard) |
| `--platform` | `apple`, `android`, `web`, `all` | Target platform (default: all) |

## Examples

```
/design-review LoginScreen
/design-review "Settings feature" --focus ux --depth comprehensive
/design-review Button component --focus system
/design-review Checkout --focus a11y --platform web
```

## Procedure

1. **Gather context** — read the generated Pencil mockups in `.context/designs/mockup-*.pen` with the Pencil MCP tools (`get_screenshot`, `batch_get`, `snapshot_layout`) for visual and structural review; identify the target and the design patterns, design-system usage, and platform considerations it relies on.
2. **Review** — run `agents/designer.md` at the selected focus and depth against the criteria below.
3. **Report** — per Output Format, with before/after suggestions where applicable.

## Review Criteria

| Focus | Checks |
|-------|--------|
| `ui` | Visual hierarchy and layout; typography and color usage; spacing and alignment consistency; icon and asset quality; dark mode support |
| `ux` | User flow clarity; interaction patterns; error handling and feedback; loading states; navigation consistency |
| `a11y` | WCAG 2.1 AA, color contrast, touch target sizes, screen reader support, keyboard navigation — full checklist in `commands/design-accessibility.md` |
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

## Worktask Integration

PL — assess existing UI · DV — implementation review · QA — visual QA · standalone — periodic design audits.

Target: $ARGUMENTS
