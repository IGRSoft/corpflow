---
name: cross-plugin-handoff
description: Protocol for handoffs between igrsoft workflow and external plugins (apple-developer, security-scanning, etc.). Use when delegating work to external plugins.
effort: medium
---

# Cross-Plugin Handoff Protocol

Defines the handoff protocol between igrsoft workflow stages and external plugin agents.

For plugin-specific protocol tables and error handling, see `${CLAUDE_SKILL_DIR}/references/plugin-protocols.md`

## When D Stage Delegates to apple-developer

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
  owner: "apple-developer:swift-pro",  // or specific agent
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

## Handoff to Q Stage (QA)

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
