---
name: pm-requirements
description: Generate a Product Requirements Document (PRD) from task description or user stories
argument-hint: <feature or task description>
model: sonnet
---

# PM Requirements Command

Generate a Product Requirements Document (PRD) from task description or user stories.

## Usage

```
/pm-requirements "Feature description"
/pm-requirements --from-user-story "As a user..."
/pm-requirements --template [full|lite|api]
```

## Options

- `--from-user-story` - Generate from user story format
- `--template <type>` - PRD template (default: full)
- `--include-metrics` - Add success metrics section
- `--technical` - Include technical requirements

## Examples

```
/pm-requirements "Add dark mode support to the application"
/pm-requirements --from-user-story "As a user, I want to toggle dark mode so I can reduce eye strain"
/pm-requirements --template api "REST API for user management"
```

## Output Format

### Full PRD Template
```markdown
# Product Requirements Document
## Dark Mode Support

### Document Info
| Field | Value |
|-------|-------|
| Author | Product Manager |
| Status | Draft |
| Version | 1.0 |
| Last Updated | [Date] |

---

## 1. Overview

### 1.1 Problem Statement
Users report eye strain when using the application in low-light environments. 50% of user feedback requests mention dark mode as a desired feature.

### 1.2 Objective
Implement a dark mode option that reduces eye strain and improves user experience in low-light conditions.

### 1.3 Success Criteria
- 80% of users who try dark mode continue using it
- Reduce eye strain complaints by 60%
- No increase in accessibility issues

---

## 2. User Stories

### Primary User Story
**As a** user who works in low-light environments
**I want to** switch to a dark color scheme
**So that** I can reduce eye strain and work more comfortably

### Additional User Stories

| ID | Story | Priority |
|----|-------|----------|
| US-001 | As a user, I want to toggle dark mode from settings | Must |
| US-002 | As a user, I want my preference saved across sessions | Must |
| US-003 | As a user, I want dark mode to follow system settings | Should |
| US-004 | As a user, I want a quick toggle in the header | Could |

---

## 3. Functional Requirements

### 3.1 Core Features

| ID | Requirement | Priority | Notes |
|----|-------------|----------|-------|
| FR-001 | Toggle dark/light mode in settings | Must | Single click toggle |
| FR-002 | Persist preference in user profile | Must | Sync across devices |
| FR-003 | Auto-detect system preference | Should | Initial default |
| FR-004 | Quick toggle in header/nav | Could | Power users |
| FR-005 | Scheduled dark mode | Won't | Future consideration |

### 3.2 Acceptance Criteria

#### FR-001: Toggle Dark Mode
```gherkin
Given I am on the settings page
When I click the dark mode toggle
Then the UI immediately switches to dark theme
And all colors meet WCAG contrast requirements
```

#### FR-002: Persist Preference
```gherkin
Given I have enabled dark mode
When I log out and log back in
Then dark mode is still enabled
And the setting is consistent across all my devices
```

---

## 4. Non-Functional Requirements

| Category | Requirement | Target |
|----------|-------------|--------|
| Performance | Theme switch latency | < 100ms |
| Accessibility | Color contrast ratio | ≥ 4.5:1 (AA) |
| Compatibility | Browser support | Last 2 versions |
| Storage | Preference storage | < 1KB |

---

## 5. Design Requirements

### 5.1 Color Palette
| Element | Light Mode | Dark Mode |
|---------|------------|-----------|
| Background | #FFFFFF | #1A1A1A |
| Text Primary | #1A1A1A | #FFFFFF |
| Text Secondary | #666666 | #A0A0A0 |
| Accent | #0066CC | #4D9FFF |

### 5.2 Component Considerations
- All components must support theme switching
- No hard-coded colors in components
- Use CSS variables or theme tokens

---

## 6. Technical Requirements

### 6.1 Implementation Approach
- Use CSS custom properties for theming
- Store preference in user profile (API) and localStorage (fallback)
- Support system preference via `prefers-color-scheme` media query

### 6.2 Dependencies
- Design system color tokens
- User preferences API endpoint
- LocalStorage fallback mechanism

---

## 7. Success Metrics

| Metric | Current | Target | Measurement |
|--------|---------|--------|-------------|
| Dark mode adoption | N/A | 40% | Analytics |
| Eye strain complaints | 100/month | 40/month | Support tickets |
| Session duration (dark mode users) | N/A | +10% | Analytics |
| Accessibility score | 92 | 95 | Lighthouse |

---

## 8. Out of Scope

- Scheduled dark mode (time-based)
- Custom color themes
- Per-page theme settings
- Dark mode for emails

---

## 9. Risks and Mitigations

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Inconsistent colors across components | Medium | High | Use design system tokens |
| Performance impact | Low | Medium | CSS-only implementation |
| Accessibility issues in dark mode | Medium | High | WCAG audit before release |

---

## 10. Timeline

| Phase | Duration | Deliverables |
|-------|----------|--------------|
| Design | 1 week | Color system, mockups |
| Development | 2 weeks | Implementation |
| QA | 1 week | Testing, fixes |
| Release | 1 day | Rollout |

---

## Appendix

### A. User Research
- Survey results: 50% requested dark mode
- Competitor analysis: 8/10 competitors have dark mode
- User interviews: Eye strain is primary motivation

### B. References
- [WCAG 2.1 Contrast Guidelines](https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html)
- Design system documentation
```

## Template Types

| Template | Use Case | Sections |
|----------|----------|----------|
| full | Complete features | All sections |
| lite | Quick features | Overview, Stories, Requirements |
| api | API features | Endpoints, Schemas, Examples |

## Integration

This command feeds into:
- `/arch-decision` - Technical decisions from requirements
- `/test-plan` - Test cases from acceptance criteria
- `/workflow` - Requirements for PL stage

## Related

- [product-manager](../agents/product-manager.md) - Product expertise
- [pm-prioritize](./pm-prioritize.md) - Feature prioritization
- [pm-roadmap](./pm-roadmap.md) - Roadmap planning
