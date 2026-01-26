# Workflow Command

Initialize a new workflow task with proper folder structure, state management, and Task System integration.

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
- `--ethics-review` - Add ethics checkpoint after planning (recommended for high-risk features)

## Examples

```
/workflow "Add dark mode support" --with-design
/workflow "Fix login crash" --priority High --platform apple
/workflow "Refactor database layer" --fast
/workflow "Add form validation" --quick
/workflow "Redesign settings screen" --with-design --platform apple
/workflow "Add user tracking analytics" --ethics-review
/workflow "Implement recommendation algorithm" --ethics-review --priority High
```

## What This Command Does

1. **Creates Context Folder**
   - Location: `.context/`
   - Creates `images/` subdirectory for visual assets

2. **Initializes workflow-state.json**
   ```json
   {
     "$schema": "workflow-state-v2",
     "workflow_id": "dark-mode-2025-01-26",
     "title": "Task Title",
     "created_at": "2025-01-26T10:00:00Z",
     "updated_at": "2025-01-26T10:00:00Z",
     "workflow_type": "standard",
     "options": {
       "with_design": false,
       "ethics_review": false,
       "priority": "medium",
       "platform": "all"
     },
     "task_ids": {
       "planning": "1",
       "ethics": null,
       "architecture": "2",
       "teamlead": "3",
       "development": "4",
       "qa": "5",
       "documentation": "6",
       "finalization": "7",
       "stakeholder": "8"
     },
     "state": { "current": "planning:preparing", "statusCode": "0", "agent": "P" },
     "retries": { "1": 0, "2": 0, "3": 0, "4": 0, "5": 0, "6": 0, "7": 0, "8": 0, "max": 3 },
     "approvals": {},
     "escalations": [],
     "artifacts": {
       "planning": ".context/planning.md",
       "architecture": ".context/analyzing.md",
       "development": ".context/development.md",
       "testing": ".context/testing.md",
       "documentation": ".context/documentation.md",
       "complete": ".context/complete.md"
     }
   }
   ```

3. **Creates planning.md Template**
   - Problem statement section
   - Requirements (functional and non-functional)
   - Acceptance criteria
   - Success metrics
   - Constraints and dependencies

4. **Creates Tasks with Dependencies**
   ```typescript
   // Create all 8 tasks
   TaskCreate({ subject: "P: Planning", description: "Define requirements and acceptance criteria", activeForm: "Planning task requirements" });  // id: "1"
   TaskCreate({ subject: "A: Architecture", description: "Design technical solution", activeForm: "Architecting solution" });  // id: "2"
   TaskCreate({ subject: "T: Team Lead", description: "Coordinate approach and resources", activeForm: "Coordinating team" });  // id: "3"
   TaskCreate({ subject: "D: Development", description: "Implement solution", activeForm: "Implementing code" });  // id: "4"
   TaskCreate({ subject: "Q: QA Testing", description: "Test and validate", activeForm: "Testing solution" });  // id: "5"
   TaskCreate({ subject: "W: Documentation", description: "Write technical docs", activeForm: "Writing documentation" });  // id: "6"
   TaskCreate({ subject: "F: Finalization", description: "Prepare release", activeForm: "Finalizing release" });  // id: "7"
   TaskCreate({ subject: "S: Stakeholder", description: "Final approval", activeForm: "Awaiting approval" });  // id: "8"

   // Set up sequential dependency chain
   TaskUpdate({ taskId: "2", addBlockedBy: ["1"] });  // A blocked by P
   TaskUpdate({ taskId: "3", addBlockedBy: ["2"] });  // T blocked by A
   TaskUpdate({ taskId: "4", addBlockedBy: ["3"] });  // D blocked by T
   TaskUpdate({ taskId: "5", addBlockedBy: ["4"] });  // Q blocked by D
   TaskUpdate({ taskId: "6", addBlockedBy: ["5"] });  // W blocked by Q
   TaskUpdate({ taskId: "7", addBlockedBy: ["6"] });  // F blocked by W
   TaskUpdate({ taskId: "8", addBlockedBy: ["7"] });  // S blocked by F

   // Start Planning
   TaskUpdate({ taskId: "1", status: "in_progress", owner: "product-manager" });
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
TaskCreate({ subject: "P: Planning", description: "Quick planning", activeForm: "Planning..." });  // id: "1"
TaskCreate({ subject: "D: Development", description: "Implementation", activeForm: "Implementing..." });  // id: "2"
TaskCreate({ subject: "Q: QA Testing", description: "Testing", activeForm: "Testing..." });  // id: "3"

TaskUpdate({ taskId: "2", addBlockedBy: ["1"] });  // D blocked by P
TaskUpdate({ taskId: "3", addBlockedBy: ["2"] });  // Q blocked by D
TaskUpdate({ taskId: "1", status: "in_progress", owner: "product-manager" });
```

### Design-Integrated Workflow (`--with-design`)
- Adds designer to P stage for UX/UI planning input
- Designer provides: user flow analysis, component requirements, accessibility considerations
- Use for: UI features, user-facing changes, design system updates
- Sets `options.with_design: true` in workflow-state.json

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

### Ethics-Review Workflow (`--ethics-review`)

For features with potential ethical implications, add an ethics checkpoint:

```
P → E → A → T → D → Q → W → F → S
```

When `--ethics-review` is enabled:

1. **Ethics Stage (E) Inserted** after P approval:
   - Ethics-reviewer agent evaluates constitutional compliance
   - Checks for potential user harm, manipulation, privacy concerns
   - Reviews against Claude's constitutional principles

2. **Automatic Ethics Triggers** - Even without flag, ethics review is recommended for:
   - User data collection or tracking
   - Algorithmic recommendations
   - Financial transactions
   - Content moderation
   - AI/ML decision-making
   - Children or vulnerable populations

3. **Ethics Review Output**:
   - Constitutional compliance assessment
   - Identified concerns and risks
   - Mitigation recommendations
   - Go/no-go recommendation

```typescript
// With ethics review: P → E → A → T → D → Q → W → F → S
TaskCreate({ subject: "P: Planning", description: "Define requirements", activeForm: "Planning..." });  // id: "1"
TaskCreate({ subject: "E: Ethics Review", description: "Constitutional compliance", activeForm: "Reviewing ethics..." });  // id: "2"
TaskCreate({ subject: "A: Architecture", description: "Design solution", activeForm: "Architecting..." });  // id: "3"
// ... rest of stages with shifted IDs

TaskUpdate({ taskId: "2", addBlockedBy: ["1"] });  // E blocked by P
TaskUpdate({ taskId: "3", addBlockedBy: ["2"] });  // A blocked by E
// ... rest of dependency chain
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
- [ethics-reviewer](../agents/ethics-reviewer.md) - Ethics reviewer for `--ethics-review` workflows
- [ethics-review](ethics-review.md) - Standalone ethics review command
- [harm-assessment](harm-assessment.md) - Harm assessment command
- [design-review](design-review.md) - Design review command
- [design-specs](design-specs.md) - Generate design specifications
- [ux-flow](ux-flow.md) - Create user experience flows
- [a11y-audit](a11y-audit.md) - Accessibility audit command
- [claude-constitution](../skills/claude-constitution.md) - Constitutional principles
