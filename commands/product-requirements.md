---
name: product-requirements
description: Generate a Product Requirements Document (PRD) from task description or user stories
argument-hint: <feature or task description>
model: sonnet
allowed-tools: Read, Glob, Grep, Write
related:
  - agents/product-manager.md
  - commands/roadmap.md
---

# Product Requirements Command

Generate a Product Requirements Document (PRD) from task description or user stories.

## Usage

```
/product-requirements "Feature description"
/product-requirements --from-user-story "As a user..."
/product-requirements --template [full|lite|api]
```

## Options

- `--from-user-story` - Generate from user story format
- `--template <type>` - PRD template (default: full)
- `--include-metrics` - Add success metrics section
- `--technical` - Include technical requirements

## Examples

```
/product-requirements "Add dark mode support to the application"
/product-requirements --from-user-story "As a user, I want to toggle dark mode so I can reduce eye strain"
/product-requirements --template api --technical "REST API for user management"
/product-requirements "Team dashboard" --include-metrics
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
| lite | Quick features | Overview, Stories, Requirements |
| api | API features | Endpoints, Schemas, Examples |

## Integration

This command feeds into:
- `/arch-decision` - Technical decisions from requirements
- `/test-plan` - Test cases from acceptance criteria
- `/worktask` - Requirements for PL stage
