# Plugin-Specific Protocols

## apple-developer Plugin

| igrsoft Stage | apple-developer Agent | Handoff Data |
|---------------|----------------------|--------------|
| DV (Development) | swift-pro, ios-developer, etc. | planning + architecture context |
| QA (Quality) | test-generator | development context + test requirements |
| RE (Release) | ios-developer | App Store submission data |

## security-scanning Plugin

| igrsoft Stage | security-scanning Agent | Handoff Data |
|---------------|------------------------|--------------|
| SR (Security) | security-auditor | code + OWASP checklist |
| SR (Security) | threat-modeling-expert | architecture + threat analysis |

## debugging-toolkit Plugin

| igrsoft Stage | debugging-toolkit Agent | Handoff Data |
|---------------|------------------------|--------------|
| DV (Development) | debugger | error logs, stack traces |
| DV (Development) | dx-optimizer | workflow friction points |
| IR (Incident) | debugger | production logs, RCA context |

## Future Plugin Integration (Not Yet Installed)

The following marketplace plugins are planned but not currently installed. Do NOT invoke these agents until the corresponding plugin is added to the project configuration.

| Plugin | Agent | Use Case |
|--------|-------|----------|
| `code-documentation` | `code-reviewer` | PR code review |
| `application-performance` | `performance-engineer` | Performance analysis |
| `cicd-automation` | `deployment-engineer` | CI/CD automation |
| `accessibility-compliance` | `ui-visual-validator` | WCAG auditing |

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

> As of CC 2.1.77, the Agent tool `resume` parameter is removed. Use `SendMessage` to communicate with running background agents. `SendMessage` auto-resumes stopped agents in the background.
