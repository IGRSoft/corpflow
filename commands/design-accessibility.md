---
name: design-accessibility
description: Conduct an accessibility audit for screens, components, or the entire application
argument-hint: '<screen, component, or app path>'
allowed-tools: Read, Glob, Grep
related:
  - agents/designer.md
  - commands/design-review.md
---

# Accessibility Audit Command

Accessibility audit of a screen, component, or the entire application against WCAG plus platform guidelines.

## Options

| Option | Values | Effect |
|--------|--------|--------|
| `--level` | `A`, `AA`, `AAA` | WCAG conformance level (default: AA) |
| `--platform` | `apple`, `android`, `web`, `all` | Target platform (default: all) |
| `--scope` | `quick`, `standard`, `comprehensive` | Audit scope (default: standard) |

```
/design-accessibility [target] [options]
/design-accessibility LoginScreen
/design-accessibility "Navigation component" --level AAA
/design-accessibility --scope comprehensive --platform apple
```

## Procedure

Audit the target against the WCAG success criteria at `--level`, the platform guidelines, and
assistive-technology support, then emit every § Output Format section. Every § Audit Categories row,
plus every § Platform-Specific Checks row `--platform` selects, carries a verdict — pass, an issue,
or `not applicable: <reason>` — and every issue names the WCAG 2.2 success criterion it fails, its
severity, and the remediation. An unscored row means the audit is unfinished.

## Audit Categories

| Category | Checks |
|----------|--------|
| Perceivable | Text alternatives for images; captions and transcripts; color contrast ratios; resize and reflow support |
| Operable | Keyboard accessibility; touch target sizes (platform minimum — see Common Issues Reference); focus management; navigation consistency |
| Understandable | Readable content; predictable behavior; input assistance; error identification |
| Robust | Assistive technology compatibility; valid markup/implementation; status messages |

## Platform-Specific Checks

Run only the platforms `--platform` selects; `all` runs every row.

### Apple

VoiceOver support; Dynamic Type; Reduce Motion; Bold Text; Increase Contrast; Switch Control compatibility.

### Android

- TalkBack support — announcements, custom actions, live regions
- `contentDescription` on every non-decorative image and icon-only control
- Touch targets at least 48x48dp
- Focus order and traversal (`accessibilityTraversalBefore` / `After`)
- Compose `semantics {}` on custom composables — merged vs. cleared semantics
- Font-scale and display-size respect: `sp` for text, no fixed-`dp` type

### Web

Screen reader compatibility; keyboard navigation; ARIA implementation; focus indicators.

## Output Format

One markdown report; the three blocks below are one continuous document.

```markdown
# Accessibility Audit: [Target]

## Executive Summary
- **Conformance Target**: WCAG 2.2 [Level]
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
## Critical Issues (P0)

### Issue: [Description]
- **WCAG Criterion**: [X.X.X - Name]
- **Location**: [Where in UI]
- **Impact**: [Who is affected and how]
- **Remediation**: [How to fix]
- **Effort**: [Low/Medium/High]

<!-- repeat per priority: High (P1), Medium (P2), Low (P3) — same issue shape, minus Effort -->
```

### Template — findings and next steps

```markdown
## Platform-Specific Findings

<!-- one subsection per platform in scope; emit nothing for platforms --platform excluded -->
### [Platform in scope]
- [Finding]

## Recommendations

<!-- numbered list under each horizon; Immediate Actions name an owner -->
### Immediate Actions
### Short-term Improvements
### Long-term Enhancements

## Testing Methodology
- Tools used / assistive technologies tested: [List] · Manual testing performed: [Yes/No]

## Next Steps
- [ ] Address critical issues
- [ ] Schedule follow-up audit
- [ ] Update accessibility documentation
```

## Common Issues Reference

- **Color contrast**: text 4.5:1 (normal), 3:1 (large); UI components 3:1.
- **Focus management**: visible focus indicator, logical focus order, focus trap in modals.
- **Text scaling** — Dynamic Type (Apple), font scale / display size (Android), browser zoom and
  `rem`-based type (web). Everywhere: support the full user-selectable size range; layout reflows
  without clipping; no truncation of critical content.

### Touch Targets

| Platform | Minimum | Recommended |
|----------|---------|-------------|
| Apple | 44x44pt | 44x44pt plus 8pt spacing |
| Android | 48x48dp | 48x48dp plus 8dp spacing |
| Web | 24x24 CSS px (WCAG 2.2 AA) | 44x44 CSS px (AAA) |

Target: $ARGUMENTS
