# Workflow Command

Initialize a new workflow task with proper folder structure, state management, and Task System integration.

## Usage

```
/workflow --milestone:N              # Execute all open issues in milestone N by priority
/workflow --milestone:N:ISSUE        # Execute specific issue from milestone N
/workflow "Task Title" [options]     # Execute a custom task
```

## Options

- `--milestone:N` - Execute GitHub milestone N issues by priority
- `--milestone:N:ISSUE` - Execute specific issue from milestone N
- `--priority [High|Medium|Low]` - Task priority (default: Medium)
- `--platform <apple|android|web|all>` - Target platform (default: all)
- `--mode [async|sync]` - Execution mode (default: async)
- `--with-design` - Include designer in planning phase (P stage)
- `--ethics-review` - Add ethics checkpoint after planning (recommended for high-risk features)
- `--sequential` - Force W to wait for Q (default: W+Q run parallel)
- `--auto-continue` - Skip per-issue approval gates in milestone execution (trusted workflows only)
- `--parallel:N` - Run N issues in parallel for milestones (default: 2, max: 5)

## Examples

```
/workflow --milestone:1                               # Work through milestone 1 by priority
/workflow --milestone:2:123                           # Work on issue #123 from milestone 2
/workflow "Add dark mode support" --with-design
/workflow "Fix login crash" --priority High --platform apple
/workflow "Redesign settings screen" --with-design --platform apple
/workflow "Add user tracking analytics" --ethics-review
```

## What This Command Does

1. **Creates Context Folder**
   - Location: `.context/`
   - Creates `images/` subdirectory for visual assets

2. **Creates planning.md Template**
   - Problem statement section
   - Requirements (functional and non-functional)
   - Acceptance criteria
   - Success metrics
   - Constraints and dependencies

4. **Creates Tasks with Dependencies**
   ```typescript
   // Create all 8 tasks with metadata
   const workflowId = "dark-mode-2025-01-26";
   const priority = "medium";  // from --priority option

   TaskCreate({ subject: "P: Planning", description: "Define requirements and acceptance criteria", activeForm: "Planning task requirements", metadata: { stage: "P", workflow_id: workflowId, priority } });  // id: "1"
   TaskCreate({ subject: "A: Architecture", description: "Design technical solution", activeForm: "Architecting solution", metadata: { stage: "A", workflow_id: workflowId, priority } });  // id: "2"
   TaskCreate({ subject: "T: Team Lead", description: "Coordinate approach and resources", activeForm: "Coordinating team", metadata: { stage: "T", workflow_id: workflowId, priority } });  // id: "3"
   TaskCreate({ subject: "D: Development", description: "Implement solution", activeForm: "Implementing code", metadata: { stage: "D", workflow_id: workflowId, priority } });  // id: "4"
   TaskCreate({ subject: "Q: QA Testing", description: "Test and validate", activeForm: "Testing solution", metadata: { stage: "Q", workflow_id: workflowId, priority } });  // id: "5"
   TaskCreate({ subject: "W: Documentation", description: "Write technical docs", activeForm: "Writing documentation", metadata: { stage: "W", workflow_id: workflowId, priority } });  // id: "6"
   TaskCreate({ subject: "F: Finalization", description: "Prepare release", activeForm: "Finalizing release", metadata: { stage: "F", workflow_id: workflowId, priority } });  // id: "7"
   TaskCreate({ subject: "S: Stakeholder", description: "Final approval", activeForm: "Awaiting approval", metadata: { stage: "S", workflow_id: workflowId, priority } });  // id: "8"

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

## Milestone Execution Mode (`--milestone`)

### All Issues: `/workflow --milestone:N`

Execute all open issues in milestone N, sorted by priority:

1. **Fetch Milestone** - `gh api /repos/{owner}/{repo}/milestones/N`
2. **Fetch Issues** - `gh api "/repos/{owner}/{repo}/issues?milestone=N&state=open"`
3. **Create milestone.json** - Sort issues by priority (P0 > P1 > P2 > P3)
4. **Execute Each Issue**:
   - Create branch: `feature/{issue#}-{slug}`
   - Run workflow stages (dynamically sized)
   - Create PR with "Closes #N"
   - Move to next issue

### Single Issue: `/workflow --milestone:N:ISSUE`

Execute specific issue from milestone N:

1. **Fetch & Validate** - Confirm issue belongs to milestone
2. **Create milestone.json** - Single issue context
3. **Execute Issue** - Same workflow as above

See [Milestone Workflow](../skills/milestone-workflow.md) for full documentation.

## Dynamic Workflow Sizing

Workflows are dynamically sized during P and A stages using the **Unified Complexity Assessment**.

**See**: `skills/workflow.md § Dynamic Workflow Sizing` for:
- Full complexity assessment table (5 factors, 0-50 scoring)
- Decision rules by score range
- Safe task deletion pattern
- Model routing by complexity

### Quick Reference

| Complexity Score | Stages Kept | P Stage Deletes |
|------------------|-------------|-----------------|
| 0-10 (Low) | P → D → Q | A, T, W, F, S |
| 11-20 (Medium) | P → A → D → Q | T, W, F, S |
| 21-30 (Moderate) | P → A → T → D → Q | W, F, S |
| 31+ (High) | All 8 stages | None |

## Workflow Modes

### Standard Workflow
- Full 8-stage process: P → A → T → D → Q → W → F → S
- Stops at P3 for user approval before continuing
- P and A stages dynamically delete unnecessary stages
- Use for: Major features, architectural changes, security-sensitive work

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
2. P stage may delete unnecessary stages (dynamic sizing)
3. P3 approval gate - wait for user approval
4. Continue through remaining stages (A stage may further prune)

## Related

- [Workflow System](../skills/workflow.md) - Complete workflow documentation
- [Milestone Workflow](../skills/milestone-workflow.md) - GitHub milestone integration
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
