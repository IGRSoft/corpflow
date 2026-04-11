# Team Communication Protocols

Structured messaging patterns for multi-agent coordination, including message type selection, anti-patterns, and deadlock resolution.

## Message Types

### Direct Message (Default)

Send to a specific agent when:
- Passing results that only one agent needs
- Requesting a specific agent to take action
- Responding to a question from one agent

### Broadcast

Send to all active agents when:
- Announcing a shared dependency change
- Reporting a blocking issue that affects everyone
- Providing status updates that all agents need

### Task Update

Use TaskUpdate when:
- Changing task status (pending → in_progress → completed)
- Recording a decision that affects downstream tasks
- Marking a blocker or dependency resolution

## Message Content Guidelines

| Guideline | Good | Bad |
|-----------|------|-----|
| Context-complete | "File `Auth.swift:42` has a race condition between `login()` and `refresh()`" | "There's an issue in the auth file" |
| Actionable | "Block: Need API response schema before implementing decoder" | "Waiting on something" |
| Scoped | "Phase 1 security findings: 2 Critical, 1 High" | "Done with my part" |
| Referenced | "Per AD3 in analyzing.md, use references/ pattern" | "As discussed earlier" |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|-------------|---------|-----|
| Chat loops | Two agents asking each other questions endlessly | Set max 2 clarification rounds, then escalate to orchestrator |
| Broadcast spam | Sending status updates as broadcasts | Use direct message unless 3+ agents need the info |
| Missing context | "Done" without results or artifact path | Always include artifact path and summary |
| Implicit handoff | Assuming next agent will read your output | Explicitly reference output file in handoff message |
| Stale references | Referencing files that were moved or renamed | Use `${CLAUDE_SKILL_DIR}` relative paths |

## Deadlock Resolution

Deadlock occurs when agents are mutually blocked:

### Detection

Signs of deadlock:
- Two tasks both show `blockedBy` referencing each other
- Agent reports "waiting for X" while X reports "waiting for Y" which waits for first agent
- Task stays `in_progress` without progress for extended time

### Resolution Steps

1. **Identify the cycle**: Check `TaskList` for circular `blockedBy` chains
2. **Break the cycle**: Orchestrator removes one `blockedBy` dependency
3. **Provide missing context**: If deadlock is from missing information, orchestrator provides it directly
4. **Reassign**: If an agent is stuck, reassign its task to a fresh agent with explicit context

### Prevention

- Minimize bidirectional dependencies between tasks
- Prefer linear dependency chains: A → B → C
- Use orchestrator as hub for cross-cutting decisions
- Set timeout expectations: escalate to orchestrator after 3 failed attempts

## Graceful Shutdown

When work is complete:

1. Each agent marks its task as `completed` with summary
2. Orchestrator collects all results
3. Orchestrator synthesizes into final output
4. No agent should continue working after its task is `completed`

For agents that detect they cannot complete their task:
1. Update task with current progress and blocker description
2. Escalate to orchestrator with specific ask
3. Do NOT silently fail or produce partial output without flagging it
