---
name: executive-summary
description: Generate executive-level summary of projects or initiatives for stakeholder communication
argument-hint: <project or initiative>
model: sonnet
allowed-tools: Read, Glob, Grep, Write
---

# Executive Summary Command

Generate executive-level summary of projects, initiatives, or completed work for stakeholder communication.

## Usage

```
/executive-summary
/executive-summary "Project or initiative"
/executive-summary --format [brief|detailed|presentation]
```

## Options

- `--format <type>` - Summary format (default: brief)
- `--audience [c-suite|board|investors|team]` - Target audience
- `--include [metrics|timeline|risks|financials]` - Include specific sections
- `--export` - Export to presentation slides

## Examples

```
/executive-summary
/executive-summary "Q1 Product Release"
/executive-summary --format presentation --audience board
```

## Output Format

### Brief Format (Default)
```markdown
# Executive Summary: [Project/Release]

## TL;DR (one sentence: what delivered, key outcome)

## Key Outcomes (table: Metric | Target | Actual | Status)

## Highlights
### Delivered (checklist)
### Business Impact (bullet metrics)
### Next Quarter Focus (bullet list)

## Action Required (checklist)
```

### Detailed Format
```markdown
# Executive Summary: [Project/Release]

## Executive Overview (Mission, Outcome, Recommendation)

## Strategic Alignment (table: Goal | Contribution | Impact)

## Delivery Summary
### Features Delivered (table: Feature | Status | Business Value)
### Quality Metrics (table: Metric | Target | Actual | Trend)

## Financial Summary (table: Category | Budget | Actual | Variance + ROI update)

## Risk Status (table: Risk | Status | Mitigation)

## Customer Impact (quotes + metrics table)

## Q2/Next Period Outlook (initiatives, resources, risks)

## Decisions Requested (table: Decision | Deadline | Owner)

## Appendix (links)
```

### Presentation Format
Three slides: Key Wins, Business Impact, Next Focus + Ask.

## Audience Customization

| Audience | Focus | Detail Level | Tone |
|----------|-------|--------------|------|
| C-Suite | Strategy, ROI | High-level | Business |
| Board | Governance, Risk | Summary | Formal |
| Investors | Growth, Metrics | Data-driven | Confident |
| Team | Achievement, Next | Detailed | Celebratory |

## Integration

This command works with:
- `/release-notes` - Technical details source
- `/roi-analysis` - Financial metrics
- `/business-case` - Strategic context

## Related

- [stakeholder](../agents/stakeholder.md) - Business stakeholder
- [project-manager](../agents/project-manager.md) - Project status
- [business-case](./business-case.md) - Business justification
