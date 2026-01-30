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
  owner: "apple-developer:swift-pro"  // or specific agent
});
```

### 3. Delegation Prompt Template

```
Implement the following for the igrsoft workflow D stage:

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
3. Return compressed handoff for Q stage (max 500 tokens)
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
// Creates Q stage tasks
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

### code-documentation Plugin (Marketplace)

| igrsoft Stage | code-documentation Agent | Handoff Data |
|---------------|-------------------------|--------------|
| DV (Development) | code-reviewer | PR diff, code changes |

**Invocation:**
```typescript
Task({
  prompt: "Review PR for code quality: {changes}",
  subagent_type: "code-documentation:code-reviewer"
});
```

### application-performance Plugin (Marketplace)

| igrsoft Stage | application-performance Agent | Handoff Data |
|---------------|------------------------------|--------------|
| DV (Development) | performance-engineer | implementation for perf review |
| QA (Quality) | performance-engineer | benchmark requirements |

**Invocation:**
```typescript
Task({
  prompt: "Analyze performance impact: {changes}",
  subagent_type: "application-performance:performance-engineer"
});
```

### cicd-automation Plugin (Marketplace)

| igrsoft Stage | cicd-automation Agent | Handoff Data |
|---------------|----------------------|--------------|
| RE (Release) | deployment-engineer | release artifacts |
| FN (Finalization) | deployment-engineer | deployment plan |

**Invocation:**
```typescript
Task({
  prompt: "Prepare CI/CD for release v{version}",
  subagent_type: "cicd-automation:deployment-engineer"
});
```

### accessibility-compliance Plugin (Marketplace)

| igrsoft Stage | accessibility-compliance Agent | Handoff Data |
|---------------|-------------------------------|--------------|
| QA (Quality) | ui-visual-validator | UI components for WCAG audit |

**Invocation:**
```typescript
Task({
  prompt: "Audit accessibility for WCAG 2.2 compliance",
  subagent_type: "accessibility-compliance:ui-visual-validator"
});
```

## Context Compression Guidelines

### Token Budgets

| Context Type | Max Tokens |
|--------------|------------|
| Planning summary | 300 |
| Architecture summary | 300 |
| Development handoff | 500 |
| Full stage output | 1000 |

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

## Best Practices

1. **Always compress context**: Don't pass full documents between plugins
2. **Reference files**: Use `.context/` paths for detailed data
3. **Update tasks**: Keep task ownership current
4. **Document failures**: Log partial completions clearly
5. **Validate handoffs**: Ensure critical info isn't lost in compression
6. **Version context**: Include timestamp in handoff summaries
