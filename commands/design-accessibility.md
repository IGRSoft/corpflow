---
name: design-accessibility
description: Conduct an accessibility audit for screens, components, or the entire application
argument-hint: '<screen, component, or app path>'
model: sonnet
allowed-tools: Read, Glob, Grep
related:
  - agents/designer.md
  - commands/design-review.md
  - commands/test-report.md
---

# Accessibility Audit Command

Conduct an accessibility audit for screens, components, or the entire application.

## Usage

```
/design-accessibility [target] [options]
```

## Options

- `--level [A|AA|AAA]` - WCAG conformance level (default: AA)
- `--platform <apple|android|web|all>` - Target platform (default: all)
- `--scope [quick|standard|comprehensive]` - Audit scope (default: standard)

## Examples

```
/design-accessibility LoginScreen
/design-accessibility "Navigation component" --level AAA
/design-accessibility --scope comprehensive --platform apple
```

## What This Command Does

1. **Analyzes Accessibility**
   - Reviews WCAG success criteria
   - Checks platform-specific guidelines
   - Evaluates assistive technology support

2. **Identifies Issues**
   - Categorizes by severity
   - Maps to WCAG criteria
   - Provides remediation guidance

3. **Generates Report**
   - Compliance status
   - Issue inventory
   - Prioritized fixes

## Audit Categories

### Perceivable
- Text alternatives for images
- Captions and transcripts
- Color contrast ratios
- Resize and reflow support

### Operable
- Keyboard accessibility
- Touch target sizes (platform minimum — see Common Issues Reference)
- Focus management
- Navigation consistency

### Understandable
- Readable content
- Predictable behavior
- Input assistance
- Error identification

### Robust
- Assistive technology compatibility
- Valid markup/implementation
- Status messages

## Platform-Specific Checks

Run only the sections selected by `--platform`; `all` runs every section. This command
covers the three UI platforms — `systems`, `backend`, and `ai` work has no user-facing
surface to audit and is out of scope.

### Apple

- VoiceOver support
- Dynamic Type support
- Reduce Motion respect
- Bold Text support
- Increase Contrast support
- Switch Control compatibility

### Android

- TalkBack support — announcements, custom actions, live regions
- `contentDescription` on every non-decorative image and icon-only control
- Touch targets at least 48x48dp
- Focus order and traversal (`accessibilityTraversalBefore` / `After`)
- Compose `semantics {}` on custom composables — merged vs. cleared semantics
- Font-scale and display-size respect: `sp` for text, no fixed-`dp` type

### Web

- Screen reader compatibility
- Keyboard navigation
- ARIA implementation
- Focus indicators

## Output Format

```markdown
# Accessibility Audit: [Target]

## Executive Summary
- **Conformance Target**: WCAG 2.1 [Level]
- **Current Status**: [Pass/Partial/Fail]
- **Critical Issues**: [Count]
- **Total Issues**: [Count]

## Compliance Overview

| Category | Status | Issues |
|----------|--------|--------|
| Perceivable | [Pass/Fail] | [Count] |
| Operable | [Pass/Fail] | [Count] |
| Understandable | [Pass/Fail] | [Count] |
| Robust | [Pass/Fail] | [Count] |
```

### Template — issue inventory

```markdown
<!-- …continued: issue sections -->
## Critical Issues (P0)

### Issue: [Description]
- **WCAG Criterion**: [X.X.X - Name]
- **Location**: [Where in UI]
- **Impact**: [Who is affected and how]
- **Remediation**: [How to fix]
- **Effort**: [Low/Medium/High]

## High Priority Issues (P1)

<!-- repeat per priority: P1..P3, same issue shape as P0 (P1..P3 omit Effort) -->

## Medium Priority Issues (P2)

[Similar format]

## Low Priority Issues (P3)

[Similar format]
```

### Template — findings and next steps

```markdown
<!-- …continued: findings, recommendations, next steps -->
## Platform-Specific Findings

<!-- one subsection per platform in scope; emit nothing for platforms --platform excluded -->
### [Platform in scope]
- [Finding]
- [Finding]

## Recommendations

### Immediate Actions
1. [Action with owner]
2. [Action with owner]

### Short-term Improvements
1. [Improvement]
2. [Improvement]

### Long-term Enhancements
1. [Enhancement]
2. [Enhancement]

## Testing Methodology
- Tools used: [List]
- Manual testing performed: [Yes/No]
- Assistive technologies tested: [List]

## Next Steps
- [ ] Address critical issues
- [ ] Schedule follow-up audit
- [ ] Update accessibility documentation
```

## Common Issues Reference

### Color Contrast
- Text: 4.5:1 (normal), 3:1 (large)
- UI components: 3:1

### Touch Targets

| Platform | Minimum | Recommended |
|----------|---------|-------------|
| Apple | 44x44pt | 44x44pt plus 8pt spacing |
| Android | 48x48dp | 48x48dp plus 8dp spacing |
| Web | 24x24 CSS px (WCAG 2.2 AA) | 44x44 CSS px (AAA) |

### Focus Management
- Visible focus indicator
- Logical focus order
- Focus trap in modals

### Text Scaling

Dynamic Type on Apple, font scale / display size on Android, browser zoom and `rem`-based
type on web. Same three checks everywhere:

- Support the full user-selectable size range
- Layout adapts gracefully (reflow, no clipping)
- No truncation of critical content

## Worktask Integration

Use this command:
- During PL stage for accessibility requirements
- During DV stage for implementation checks
- During QA stage for compliance verification
- Standalone for periodic audits

Target: $ARGUMENTS
