---
name: product-requirements
description: Generate a Product Requirements Document (PRD) from task description or user stories
argument-hint: '"<feature or task description>" | --from-user-story "<story>" [--template full|lite|api] [--include-metrics] [--technical]'
allowed-tools: Read, Glob, Grep, Write
related:
  - agents/product-manager.md
  - commands/roadmap.md
---

# Product Requirements Command

Generate a Product Requirements Document (PRD) from task description or user stories. The PRD is
written to `.context/prd-<feature-slug>.md`, the only file this command creates, which
`/milestone --from-prd` reads.

## Options

| Option | Values | Purpose |
|--------|--------|---------|
| `--from-user-story "<story>"` | — | Build the PRD from a user story instead of a feature description |
| `--template <type>` | `full`, `lite`, `api` | PRD template (default: `full`; see § Template Types) |
| `--include-metrics` | — | Add §7 Success Metrics to a `lite` or `api` PRD (`full` always carries it) |
| `--technical` | — | Add §6 Technical Requirements to a `lite` PRD (`full` and `api` always carry it) |

```
/product-requirements "<feature or task description>" | --from-user-story "<story>" [--template full|lite|api] [--include-metrics] [--technical]
/product-requirements "Add dark mode support to the application"
/product-requirements --from-user-story "As a user, I want to toggle dark mode so I can reduce eye strain"
/product-requirements --template api --include-metrics "REST API for user management"
/product-requirements "Team dashboard" --template lite --technical
```

## Output Format

PRD skeleton — parenthesised notes give each section's shape:

```markdown
# Product Requirements Document
## [Feature Name]

### Document Info (table: Author | Status | Version | Last Updated)

## 1. Overview — 1.1 Problem Statement · 1.2 Objective · 1.3 Success Criteria
## 2. User Stories — primary story, then table: ID | Story | Priority
## 3. Functional Requirements
  ### 3.1 Core Features (table: ID | Requirement | Priority | Notes)
  ### 3.2 Acceptance Criteria (Given/When/Then per FR)
## 4. Non-Functional Requirements (table: Category | Requirement | Target)
## 5. Design Requirements (color palette, component considerations)
## 6. Technical Requirements (implementation approach, dependencies)
## 7. Success Metrics (table: Metric | Current | Target | Measurement)
## 8. Out of Scope
## 9. Risks and Mitigations (table: Risk | Probability | Impact | Mitigation)
## 10. Timeline (table: Phase | Duration | Deliverables)
## Appendix (user research, references)
```

## Template Types

| Template | Use Case | Sections |
|----------|----------|----------|
| full | Complete features | All sections |
| lite | Quick features | §1 Overview, §2 User Stories, §3 Functional Requirements |
| api | API features | §1–3, plus §6 Technical Requirements as one row per endpoint: Method \| Path \| Request \| Response \| Errors |
