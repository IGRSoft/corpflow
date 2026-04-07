---
name: cross-plugin-handoff
description: Protocol for handoffs between igrsoft workflow and external plugins (apple-developer, security-scanning, etc.). Use when delegating work to external plugins.
effort: medium
---

## Orchestrator Implementation Gate (BINDING)

When the orchestrator receives results from ANY external plugin command (apple-developer:analyze-error, apple-developer:code-debug, debugging-toolkit:smart-debug, security-scanning:*, etc.) that include fix suggestions, code changes, or implementation recommendations:

1. **PRESENT** the analysis results and proposed fix to the user
2. **DO NOT** call Write, Edit, or any file-modifying Bash command
3. **WAIT** for explicit user approval before implementing any changes

**Exception**: If the user's original request explicitly includes implementation intent (e.g., "fix this and apply the changes", "auto-fix", "just fix it"), the approval gate is satisfied by the original request.

# Cross-Plugin Handoff Protocol

Defines the handoff protocol between igrsoft workflow stages and external plugin agents.

For plugin-specific protocol tables and error handling, see `${CLAUDE_SKILL_DIR}/references/plugin-protocols.md`

## When AR Stage Collaborates with apple-architector

Unlike DV stage delegation where task ownership transfers, the AR stage uses a **consultation model** — `software-architector` retains task ownership and merges results.

### Collaboration Protocol

1. `software-architector` detects Apple platform context during AR0
2. Completes system-level architecture first (API, backend, infra, data)
3. Delegates Swift app architecture to `apple-developer:apple-architector`
4. Receives compressed summary + reads `.context/swift-architecture.md`
5. Merges into unified `analyzing.md`

### Delegation Prompt Template

```
Provide Swift app architecture for the igrsoft workflow AR stage:

## Task
{task_description}

## Planning Context (compressed)
{planning_summary from .context/planning.md}

## System Architecture Constraints
- API patterns: {REST/GraphQL/gRPC decisions}
- Data layer: {persistence decisions}
- Concurrency constraints: {system-level async requirements}

## Expected Output
1. Select architecture pattern (MVVM/TCA/MVI/Clean/etc.) with rationale
2. Define module structure and dependency boundaries
3. Define state management and DI strategy
4. Define concurrency strategy (actors, async/await patterns)
5. Define navigation pattern
6. Define Swift test architecture (unit, integration, UI)
7. Write full output to .context/swift-architecture.md
8. Return compressed summary (max 500 tokens)
```

### Return Protocol

`apple-architector` writes `.context/swift-architecture.md` with full detail and returns a compressed summary (max 500 tokens). `software-architector` reads the full file when merging into `analyzing.md`.

### analyzing.md Merge Template

When Apple platform is detected, `analyzing.md` gains these sections:

```markdown
## Swift App Architecture
### Pattern: [MVVM/TCA/MVI/etc.]
**Rationale**: [from apple-architector]
### Module Structure
[file/target structure from apple-architector]
### State & Dependency Boundaries
[DI strategy, state management]
### Concurrency Strategy
[async/await, actors, Sendable patterns]
### Navigation Pattern
[coordinator/NavigationStack approach]
```

The `## Test Architecture` section splits into system tests (from `software-architector`) and Swift app tests (from `apple-architector`).

### Conflict Resolution

System constraints override app-level preferences. If apple-architector's pattern choice conflicts with system architecture (e.g., TCA's unidirectional flow vs. required bidirectional API streaming), `software-architector` documents the trade-off in an ADR and chooses the compatible option.

## When DV Stage Delegates to apple-developer

### 1. Context Preparation

Before delegating, prepare context from workflow artifacts:

```markdown
## Compressed Planning Context (from .context/planning.md)
- Feature: {feature_name}
- User stories: {count} stories
- Acceptance criteria: {key_criteria}
- Constraints: {platform, performance, etc.}

## Compressed Architecture Context (from .context/analyzing.md)
- Approach: {technical_approach}
- Patterns: {architecture_patterns}
- Key decisions: {decisions}
- Data models: {summary}
```

### 2. Task Ownership Transfer

Transfer task to external plugin agent:

```typescript
TaskUpdate({
  taskId: "{id}",
  status: "in_progress",
  owner: "apple-developer:ios-developer",  // or specific agent
  metadata: {
    // Include worktree context when applicable
    workspace_path: ".worktrees/milestone-1/42",  // if worktree mode
    isolation: "worktree"                          // signals worktree mode to external agent
  }
});
```

External agents receiving worktree-isolated tasks should:
1. Read `workspace_path` from task metadata
2. Operate on files inside the worktree path
3. Use `git -C {workspace_path}` for any git commands
4. Write artifacts to `{workspace_path}/.context/`

### 3. Delegation Prompt Template

```
Implement the following for the igrsoft workflow DV stage:

## Task
{task_description}

## Planning Context (compressed)
{planning_summary}

## Architecture Context (compressed)
{architecture_summary}

## Requirements
- {acceptance_criteria}

## Constraints
- Platform: {platform}
- Architecture decisions: {decisions}

## Expected Output
1. Implementation code
2. Write summary to .context/development.md
3. Return compressed handoff for QA stage (max 500 tokens)
```

### 4. Return Protocol

External agent should:
1. Update task status to completed
2. Write to `.context/development.md`
3. Return compressed summary for next stage

## Direct Orchestrator Dispatch

The orchestrator loop resolves `metadata.agent` dynamically: bare names prepend `igrsoft:`, fully-qualified names (containing `:`) dispatch as-is. This enables PL0 to route stages directly to external plugin agents without an igrsoft intermediary.

```typescript
// PL0 creates a DV stage task routed directly to apple-developer
TaskCreate({
  subject: "DV0: Implement SwiftUI feature",
  description: "Implement the onboarding flow using SwiftUI NavigationStack",
  metadata: {
    stage: "DV",
    agent: "apple-developer:ios-developer",  // fully-qualified → dispatched directly
    model: "opus",
    workflow_id: workflowId
  }
});
```

Use direct dispatch when:
- The task is entirely within one external plugin's domain (e.g., pure Swift/Apple work)
- PL0 can determine at planning time that no igrsoft routing is needed
- The external agent's handoff format (see below) is used for stage continuity

Bare names like `"developer"` continue to resolve to `igrsoft:developer` — fully backward compatible.

## Handoff to QA Stage (QA)

### From apple-developer to qa-engineer

The external agent provides:

```markdown
## Development Handoff (max 500 tokens)

PHASE: D (Development)
STATUS: complete
AGENT: apple-developer:{agent}

IMPLEMENTATION:
- Feature: {name}
- Files modified: {list}
- Tests added: {list}

KEY_DECISIONS:
- {decision_1}
- {decision_2}

QA_SCENARIOS:
- {scenario_1}: {expected_result}
- {scenario_2}: {expected_result}

EDGE_CASES:
- {edge_case_1}
- {edge_case_2}

KNOWN_ISSUES:
- {any_issues}
```

### qa-engineer Processing

```typescript
// qa-engineer receives handoff
// Reads development.md
// Creates QA stage tasks
TaskCreate({
  subject: "Test {feature}",
  description: "Verify implementation per development handoff...",
  activeForm: "Testing {feature}"
});
```

## Context Compression Guidelines

### Token Budgets

See `${CLAUDE_SKILL_DIR}/../context-compression/SKILL.md` for authoritative inter-stage budgets.

For cross-plugin compressed summaries specifically:

| Context Type | Max Tokens |
|--------------|------------|
| Planning summary for external agent | 300 |
| Architecture summary for external agent | 300 |
| Development handoff to external agent | 500 |
| Full stage output (inline reference) | 1000 |

### Compression Template

```
STAGE: {stage_name}
STATUS: {complete|partial|blocked}
DURATION: {time}
TOKEN_USAGE: {tokens}

CRITICAL_ITEMS:
- [P0] {critical_item}
- [P1] {important_item}

KEY_METRICS:
- {metric}: {value}

CONTEXT_FOR_NEXT_STAGE:
- {relevant_context}

FULL_OUTPUT_REF: .context/{stage}.md
```

## Best Practices

1. **Always compress context**: Don't pass full documents between plugins
2. **Reference files**: Use `.context/` paths for detailed data
3. **Update tasks**: Keep task ownership current
4. **Document failures**: Log partial completions clearly
5. **Validate handoffs**: Ensure critical info isn't lost in compression
6. **Version context**: Include timestamp in handoff summaries
