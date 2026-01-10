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
# Executive Summary: Q1 Product Release

## TL;DR
Successfully delivered SSO and Dark Mode features on time and under budget, unlocking $2.4M enterprise pipeline.

---

## Key Outcomes

| Metric | Target | Actual | Status |
|--------|--------|--------|--------|
| On-Time Delivery | Jan 24 | Jan 24 | ✅ |
| Budget | $150K | $142K | ✅ Under |
| Quality | 0 critical bugs | 0 critical | ✅ |
| Customer Satisfaction | 4.5 | 4.7 | ✅ Exceeded |

---

## Highlights

### Delivered
- ✅ Enterprise SSO (Okta, Azure AD)
- ✅ Dark Mode with system preference sync
- ✅ 40% dashboard performance improvement

### Business Impact
- 🎯 5 enterprise deals progressing ($1.2M)
- 📉 Support tickets down 35%
- 📈 User engagement up 12%

### Next Quarter Focus
- Mobile app MVP
- Advanced analytics
- API v2

---

## Action Required
- [ ] Approve Q2 budget allocation
- [ ] Review mobile app scope
```

### Detailed Format
```markdown
# Executive Summary: Q1 2025 Product Release

**Date**: January 24, 2025
**Prepared By**: Product Team
**For**: Executive Leadership

---

## Executive Overview

### Mission
Enable enterprise market expansion through security features while improving core user experience.

### Outcome
All Q1 objectives achieved. SSO implementation unlocks blocked enterprise pipeline. Dark mode addresses top user request. Performance improvements exceed targets.

### Recommendation
Approve Q2 initiatives building on Q1 momentum.

---

## Strategic Alignment

| Company Goal | Q1 Contribution | Impact |
|--------------|-----------------|--------|
| Enterprise Growth | SSO enables deals | $2.4M pipeline unlocked |
| User Satisfaction | Dark mode, performance | NPS +8 points |
| Operational Efficiency | Support reduction | 35% fewer tickets |
| Security Posture | SOC 2 readiness | Audit-ready |

---

## Delivery Summary

### Features Delivered

| Feature | Status | Business Value |
|---------|--------|----------------|
| Enterprise SSO | ✅ Complete | Unlocks enterprise segment |
| Dark Mode | ✅ Complete | Top user request, 40% adoption |
| Performance v1 | ✅ Complete | 40% faster load times |

### Quality Metrics

| Metric | Target | Actual | Trend |
|--------|--------|--------|-------|
| Critical Bugs | 0 | 0 | ✅ |
| Test Coverage | 80% | 82% | ↑ |
| Uptime | 99.9% | 99.95% | ↑ |
| MTTR | < 1 hour | 23 min | ↑ |

---

## Financial Summary

| Category | Budget | Actual | Variance |
|----------|--------|--------|----------|
| Development | $100K | $95K | -5% |
| Infrastructure | $30K | $28K | -7% |
| Other | $20K | $19K | -5% |
| **Total** | **$150K** | **$142K** | **-5%** |

### ROI Update
- Projected 3-year ROI: 1,443%
- Q1 revenue attributed: $280K
- On track for Q2 targets

---

## Risk Status

| Risk | Q1 Status | Mitigation |
|------|-----------|------------|
| SSO provider changes | 🟢 Managed | Abstraction layer in place |
| Adoption concerns | 🟢 Resolved | 40% dark mode adoption |
| Performance at scale | 🟢 Resolved | Load testing passed |

---

## Customer Impact

### Feedback Highlights
> "SSO was the blocker for our enterprise deal. Now we can proceed." - Enterprise Prospect

> "Dark mode is exactly what I needed. Great implementation." - Power User

### Metrics
| Metric | Before | After | Change |
|--------|--------|-------|--------|
| NPS Score | 42 | 50 | +8 |
| Support Tickets | 200/mo | 130/mo | -35% |
| Feature Requests (Dark) | #1 | Resolved | ✅ |

---

## Q2 Outlook

### Planned Initiatives
1. **Mobile App MVP** - Extend reach to mobile users
2. **Advanced Analytics** - Data-driven insights
3. **API v2** - Developer ecosystem growth

### Resource Requirements
| Resource | Q1 Actual | Q2 Request |
|----------|-----------|------------|
| Engineering | 5 FTE | 6 FTE |
| Budget | $142K | $180K |

### Risks to Monitor
- Mobile development timeline
- API adoption rate
- Competitive landscape

---

## Decisions Requested

| Decision | Deadline | Owner |
|----------|----------|-------|
| Approve Q2 budget | Jan 31 | CFO |
| Mobile app scope | Feb 5 | CPO |
| API pricing model | Feb 15 | CEO |

---

## Appendix

- [Full Q1 Report](./q1-report.md)
- [Financial Details](./q1-financials.md)
- [Customer Feedback](./q1-feedback.md)
```

### Presentation Format
```markdown
# Q1 Product Release

---

## Slide 1: Key Wins

### Delivered On Time, Under Budget
- ✅ Enterprise SSO
- ✅ Dark Mode
- ✅ 40% Performance Boost

**Budget**: $142K of $150K (-5%)

---

## Slide 2: Business Impact

| Metric | Result |
|--------|--------|
| Pipeline Unlocked | $2.4M |
| Support Reduction | 35% |
| NPS Increase | +8 points |

---

## Slide 3: Q2 Focus

1. Mobile App MVP
2. Advanced Analytics
3. API v2

**Ask**: Approve $180K Q2 budget

---
```

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
