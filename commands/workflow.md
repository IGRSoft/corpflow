# Workflow Command

Initialize a new workflow task with proper folder structure, state management, and TodoWrite integration.

## Usage

```
/workflow "Task Title" [options]
```

## Options

- `--priority [High|Medium|Low]` - Task priority (default: Medium)
- `--platform <apple|android|web|all>` - Target platform (default: all)
- `--mode [async|sync]` - Execution mode (default: async)
- `--fast` - Use fast workflow (skip P3 approval gate)
- `--quick` - Use quick 3-stage workflow (P → D → Q only)
- `--with-design` - Include designer in planning phase (P stage)

## Examples

```
/workflow "Add dark mode support" --with-design
/workflow "Fix login crash" --priority High --platform apple
/workflow "Refactor database layer" --fast
/workflow "Add form validation" --quick
/workflow "Redesign settings screen" --with-design --platform apple
```

## What This Command Does

1. **Creates Context Folder**
   - Location: `.context/`
   - Creates `images/` subdirectory for visual assets

2. **Initializes task-state.json**
   ```json
   {
     "task_id": "current-task",
     "title": "Task Title",
     "state": { "current": "planning:preparing", "statusCode": "0", "agent": "P" },
     "priority": "medium",
     "platform": "all",
     "retries": { "P": 0, "A": 0, "T": 0, "D": 0, "Q": 0, "W": 0, "F": 0, "S": 0, "max": 3 }
   }
   ```

3. **Creates planning.md Template**
   - Problem statement section
   - Requirements (functional and non-functional)
   - Acceptance criteria
   - Success metrics
   - Constraints and dependencies

4. **Initializes TodoWrite**
   ```typescript
   TodoWrite({
     todos: [
       { content: "P1: Planning", status: "in_progress", activeForm: "Planning task requirements" },
       { content: "A0: Architecture", status: "pending", activeForm: "Architecting solution" },
       { content: "T0: Team Lead", status: "pending", activeForm: "Coordinating team" },
       { content: "D0: Development", status: "pending", activeForm: "Implementing code" },
       { content: "Q0: QA Testing", status: "pending", activeForm: "Testing solution" },
       { content: "W0: Documentation", status: "pending", activeForm: "Writing technical documentation" },
       { content: "F0: Finalization", status: "pending", activeForm: "Finalizing release" },
       { content: "S0: Stakeholder", status: "pending", activeForm: "Awaiting approval" }
     ]
   });
   ```

5. **Starts Planning Phase**
   - Prompts for requirements gathering
   - Guides through planning.md completion

## Workflow Modes

### Standard Workflow
- Full 8-stage process: P → A → T → D → Q → W → F → S
- Stops at P3 for user approval before continuing
- Use for: Major features, architectural changes, security-sensitive work

### Fast Workflow (`--fast`)
- Same 8 stages but skips P3 approval gate
- Planning auto-approves and continues to Architecture
- Use for: Trusted tasks, bug fixes, well-defined features

### Quick Workflow (`--quick`)
- 3-stage process: P → D → Q only
- Skips Architecture (A), Team Lead (T), Documentation (W), Finalization (F), Stakeholder (S)
- Use for: Small fixes, simple features, focused changes

```typescript
// Quick workflow TodoWrite initialization
TodoWrite({
  todos: [
    { content: "P1: Planning", status: "in_progress", activeForm: "Planning task requirements" },
    { content: "D0: Development", status: "pending", activeForm: "Implementing code" },
    { content: "Q0: QA Testing", status: "pending", activeForm: "Testing solution" }
  ]
});
```

### Design-Integrated Workflow (`--with-design`)
- Adds designer to P stage for UX/UI planning input
- Designer provides: user flow analysis, component requirements, accessibility considerations
- Use for: UI features, user-facing changes, design system updates

When `--with-design` is enabled:

1. **P Stage Enhanced** - Product Manager + Designer collaborate:
   - Product Manager defines requirements and acceptance criteria
   - Designer adds UX requirements, wireframes, component needs
   - Combined output in planning.md with design section

2. **A Stage Design Alignment** - Architecture includes:
   - UI component architecture review
   - Design system compatibility check
   - Animation/interaction feasibility

3. **D Stage Design Support** - Developer gets:
   - Design specifications
   - Asset requirements
   - Interaction behavior definitions

4. **Q Stage Design QA** - Testing includes:
   - Visual regression criteria
   - Accessibility compliance checks
   - Cross-platform consistency

```typescript
// Design-integrated workflow TodoWrite initialization
TodoWrite({
  todos: [
    { content: "P1: Planning + Design", status: "in_progress", activeForm: "Planning requirements with design input" },
    { content: "A0: Architecture", status: "pending", activeForm: "Architecting solution with design alignment" },
    { content: "T0: Team Lead", status: "pending", activeForm: "Coordinating team" },
    { content: "D0: Development", status: "pending", activeForm: "Implementing code with design specs" },
    { content: "Q0: QA + Design QA", status: "pending", activeForm: "Testing solution and design fidelity" },
    { content: "W0: Documentation", status: "pending", activeForm: "Writing technical documentation" },
    { content: "F0: Finalization", status: "pending", activeForm: "Finalizing release" },
    { content: "S0: Stakeholder", status: "pending", activeForm: "Awaiting approval" }
  ]
});
```

## Output

```
Workflow Initiated (Standard)

Task: Add dark mode support
Location: .context/
Mode: Standard (will pause at P3 for approval)

I've initiated the workflow. Starting planning...
```

## Next Steps

After initialization:
1. Complete planning.md with requirements and acceptance criteria
2. P3 approval gate (standard workflow) or auto-continue (fast workflow)
3. Architecture stage begins
4. Continue through remaining stages

## Related

- [Workflow System](../skills/workflow.md) - Complete workflow documentation
- [Task Folder Organization](../skills/task-folder-organization.md) - Folder structure
- [workflow-engineer](../agents/workflow-engineer.md) - Troubleshooting
- [designer](../agents/designer.md) - Designer agent for `--with-design` workflows
- [design-review](design-review.md) - Design review command
- [design-specs](design-specs.md) - Generate design specifications
- [ux-flow](ux-flow.md) - Create user experience flows
- [a11y-audit](a11y-audit.md) - Accessibility audit command
