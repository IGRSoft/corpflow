# UX Flow Command

Create or analyze user experience flows for features, tasks, or user journeys.

## Usage

```
/ux-flow [feature or task] [options]
```

## Options

- `--mode [create|analyze|optimize]` - Operation mode (default: create)
- `--depth [basic|detailed|comprehensive]` - Detail level (default: detailed)
- `--include-edge-cases` - Include error states and edge cases
- `--platform <apple|android|web|all>` - Target platform context (default: all)

## Examples

```
/ux-flow "User registration"
/ux-flow "Checkout process" --mode analyze --depth comprehensive
/ux-flow "Password reset" --include-edge-cases
```

## What This Command Does

### Create Mode
1. Defines user goals and entry points
2. Maps happy path flow steps
3. Identifies decision points
4. Documents screen transitions
5. Outlines feedback and confirmation states

### Analyze Mode
1. Reviews existing flow implementation
2. Identifies friction points
3. Measures flow efficiency
4. Checks for accessibility issues
5. Suggests optimizations

### Optimize Mode
1. Analyzes current flow metrics
2. Identifies bottlenecks
3. Proposes improvements
4. Estimates impact of changes

## Output Format

```markdown
# UX Flow: [Feature/Task]

## Overview
- **User Goal**: [What user wants to achieve]
- **Entry Points**: [How users access this flow]
- **Success Criteria**: [What defines completion]
- **Est. Steps**: [Number of steps]

## User Flow Diagram

```
[Entry] → [Step 1] → [Step 2] → [Decision]
                                    ↓ Yes
                              [Step 3] → [Success]
                                    ↓ No
                              [Alternative Path]
```

## Detailed Steps

### Step 1: [Screen/State Name]
- **User Action**: [What user does]
- **System Response**: [What happens]
- **UI Elements**: [Key interface elements]
- **Next Step**: [Transition logic]

### Step 2: [Screen/State Name]
- **User Action**: [What user does]
- **System Response**: [What happens]
- **UI Elements**: [Key interface elements]
- **Next Step**: [Transition logic]

### Decision Point: [Decision Name]
- **Condition**: [What determines path]
- **Path A**: [If condition met]
- **Path B**: [If condition not met]

## Edge Cases

### Error: [Error Type]
- **Trigger**: [What causes error]
- **User Feedback**: [Error message/indicator]
- **Recovery**: [How user recovers]

### Edge Case: [Case Name]
- **Scenario**: [Description]
- **Handling**: [System behavior]
- **User Experience**: [What user sees]

## Loading States
- [Where loading occurs]
- [Loading indicator type]
- [Timeout handling]

## Accessibility Considerations
- Screen reader announcements
- Focus management
- Error communication
- Progress indication

## Metrics & Success
- **Completion Rate Target**: [%]
- **Time to Complete Target**: [seconds/minutes]
- **Drop-off Points to Monitor**: [List]

## Implementation Notes
- [Technical considerations]
- [API dependencies]
- [State management needs]
```

## Flow Diagram Notation

```
[Screen]       - UI screen or state
→              - Transition
↓ / ↑          - Vertical flow
{Decision}     - Decision point
(Action)       - User action
[[Modal]]      - Modal overlay
[[ Error ]]    - Error state
```

## Workflow Integration

Use this command:
- During PL stage for feature planning
- During AR stage for architecture validation
- During DV stage for implementation reference
- During QA stage for test case generation

## Related

- [designer](../agents/designer.md) - Designer agent
- [design-review](design-review.md) - Review designs
- [test-plan](test-plan.md) - Generate test plans from flows

Target: $ARGUMENTS
