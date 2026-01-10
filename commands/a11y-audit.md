# Accessibility Audit Command

Conduct an accessibility audit for screens, components, or the entire application.

## Usage

```
/a11y-audit [target] [options]
```

## Options

- `--level [A|AA|AAA]` - WCAG conformance level (default: AA)
- `--platform [iOS|macOS|web|all]` - Target platform (default: all)
- `--scope [quick|standard|comprehensive]` - Audit scope (default: standard)

## Examples

```
/a11y-audit LoginScreen
/a11y-audit "Navigation component" --level AAA
/a11y-audit --scope comprehensive --platform iOS
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
- Touch target sizes (44x44pt min)
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

### iOS/macOS
- VoiceOver support
- Dynamic Type support
- Reduce Motion respect
- Bold Text support
- Increase Contrast support
- Switch Control compatibility

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

## Critical Issues (P0)

### Issue: [Description]
- **WCAG Criterion**: [X.X.X - Name]
- **Location**: [Where in UI]
- **Impact**: [Who is affected and how]
- **Remediation**: [How to fix]
- **Effort**: [Low/Medium/High]

## High Priority Issues (P1)

### Issue: [Description]
- **WCAG Criterion**: [X.X.X - Name]
- **Location**: [Where in UI]
- **Impact**: [Who is affected]
- **Remediation**: [How to fix]

## Medium Priority Issues (P2)

[Similar format]

## Low Priority Issues (P3)

[Similar format]

## Platform-Specific Findings

### iOS
- [Finding]
- [Finding]

### macOS
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
- Minimum: 44x44pt
- Recommended: 48x48pt with spacing

### Focus Management
- Visible focus indicator
- Logical focus order
- Focus trap in modals

### Dynamic Type
- Support all text sizes
- Layout adapts gracefully
- No truncation of critical content

## Workflow Integration

Use this command:
- During P stage for accessibility requirements
- During D stage for implementation checks
- During Q stage for compliance verification
- Standalone for periodic audits

## Related

- [designer](../agents/designer.md) - Designer agent
- [design-review](design-review.md) - General design review
- [qa-report](qa-report.md) - QA reporting

Target: $ARGUMENTS
