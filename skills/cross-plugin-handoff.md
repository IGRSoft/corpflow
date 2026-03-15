---
name: cross-plugin-handoff
description: Protocol for handoffs between igrsoft workflow and external plugins (apple-developer, security-scanning, etc.)
---

# Cross-Plugin Handoff Protocol

Defines the handoff protocol between igrsoft workflow stages and external plugin agents.

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

## Plugin-Specific Protocols

### apple-developer Plugin

| igrsoft Stage | apple-developer Agent | Handoff Data |
|---------------|----------------------|--------------|
| DV (Development) | swift-pro, ios-developer, etc. | planning + architecture context |
| QA (Quality) | test-generator | development context + test requirements |
| RE (Release) | ios-developer | App Store submission data |

### security-scanning Plugin

| igrsoft Stage | security-scanning Agent | Handoff Data |
|---------------|------------------------|--------------|
| SR (Security) | security-auditor | code + OWASP checklist |
| SR (Security) | threat-modeling-expert | architecture + threat analysis |

### debugging-toolkit Plugin

| igrsoft Stage | debugging-toolkit Agent | Handoff Data |
|---------------|------------------------|--------------|
| DV (Development) | debugger | error logs, stack traces |
| DV (Development) | dx-optimizer | workflow friction points |
| IR (Incident) | debugger | production logs, RCA context |

### Future Plugin Integration (Not Yet Installed)

The following marketplace plugins are planned but not currently installed. Do NOT invoke these agents until the corresponding plugin is added to the project configuration.

| Plugin | Agent | Use Case |
|--------|-------|----------|
| `code-documentation` | `code-reviewer` | PR code review |
| `application-performance` | `performance-engineer` | Performance analysis |
| `cicd-automation` | `deployment-engineer` | CI/CD automation |
| `accessibility-compliance` | `ui-visual-validator` | WCAG auditing |

## Context Compression Guidelines

### Token Budgets

See `skills/context-compression.md` for authoritative inter-stage budgets.

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

## Error Handling

### External Agent Failure

```typescript
IF external_agent_fails:
  1. Log failure: "Agent {name} failed: {error}"
  2. IF critical_task:
       Retry with same context (max 3 attempts)
       IF still_fails:
         TaskUpdate({ taskId, status: "pending" })  // Reset for manual handling
         Create blocker task
     ELSE:
       Mark partial completion
       Document what was achieved
  3. Include failure in handoff:
     PARTIAL_FAILURES:
     - Agent: {name}, Error: {error}, Impact: {impact}
```

### Context Overflow

If handoff exceeds token budget:
1. Compress P2/P3 items
2. Reference full output via file path
3. Include only critical items inline

## Model Configuration

> Agent frontmatter accepts full model IDs (e.g., `claude-opus-4-5`) in addition to aliases (`opus`). Cross-plugin handoffs can specify exact model versions when precision matters for provider-specific behavior.

## Best Practices

1. **Always compress context**: Don't pass full documents between plugins
2. **Reference files**: Use `.context/` paths for detailed data
3. **Update tasks**: Keep task ownership current
4. **Document failures**: Log partial completions clearly
5. **Validate handoffs**: Ensure critical info isn't lost in compression
6. **Version context**: Include timestamp in handoff summaries
