---
name: design-review
description: Conduct a comprehensive design review for screens, components, or features
argument-hint: '<screen, component, or feature>'
model: sonnet
---

# Design Review Command

Conduct a comprehensive design review for screens, components, or features using the designer agent.

## Usage

```
/design-review [target] [options]
```

## Options

- `--focus [ui|ux|a11y|system]` - Review focus area (default: all)
- `--depth [quick|standard|comprehensive]` - Review depth (default: standard)
- `--platform <apple|android|web|all>` - Target platform (default: all)

## Examples

```
/design-review LoginScreen
/design-review "Settings feature" --focus ux --depth comprehensive
/design-review Button component --focus system
```

## What This Command Does

1. **Gathers Design Context**
   - Reviews generated Pencil mockups in `.context/designs/mockup-*.pen`
   - Uses Pencil MCP tools (`get_screenshot`, `batch_get`, `snapshot_layout`) for visual and structural review
   - Identifies target screens, components, or features
   - Reviews existing design patterns and system usage
   - Checks platform-specific considerations

2. **Executes Review**
   - Uses designer agent with appropriate focus
   - Evaluates against design criteria
   - Identifies issues and improvement opportunities

3. **Generates Report**
   - Prioritized findings (Critical/High/Medium/Low)
   - Actionable recommendations
   - Before/after suggestions where applicable

## Review Criteria

### UI Focus
- Visual hierarchy and layout
- Typography and color usage
- Spacing and alignment consistency
- Icon and asset quality
- Dark mode support

### UX Focus
- User flow clarity
- Interaction patterns
- Error handling and feedback
- Loading states
- Navigation consistency

### Accessibility Focus (a11y)
- WCAG 2.1 AA compliance
- Color contrast ratios
- Touch target sizes
- Screen reader support
- Keyboard navigation

### Design System Focus
- Component library adherence
- Token usage (colors, spacing, typography)
- Pattern consistency
- Reusability assessment

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

### High Priority (P1)
- [Issue]: [Impact] → [Recommendation]

### Medium Priority (P2)
- [Issue]: [Impact] → [Recommendation]

### Low Priority (P3)
- [Issue]: [Impact] → [Recommendation]

## Recommendations
1. [Actionable item with owner]
2. [Actionable item with owner]

## Next Steps
- [Immediate actions]
- [Follow-up reviews needed]
```

## Workflow Integration

This command can be used:
- During PL stage for existing UI assessment
- During DV stage for implementation review
- During QA stage for visual QA
- Standalone for periodic design audits

## Related

- [designer](../agents/designer.md) - Designer agent
- [design-specs](design-specs.md) - Generate design specifications
- [a11y-audit](a11y-audit.md) - Accessibility-focused audit

Target: $ARGUMENTS
