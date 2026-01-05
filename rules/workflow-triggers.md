# Workflow Trigger Rules (ALWAYS APPLY)

This rule defines automatic behavior when Claude detects workflow trigger prefixes in user input. These rules are non-overridable and must be applied before any other processing.

## Trigger Detection (CRITICAL)

**When the user's message starts with ANY of these prefixes, Claude MUST immediately invoke the workflow-init command BEFORE doing anything else:**

| Prefix | Required Action |
|--------|-----------------|
| `workflow:` | Invoke `/company-workflow:workflow-init "[task]"` |
| `fworkflow:` | Invoke `/company-workflow:workflow-init "[task]" --fast` |
| `quick:` | Invoke `/company-workflow:workflow-init "[task]" --quick` |
| `micro:` | Execute task directly (no workflow initialization) |

## Detection Algorithm

```
1. Check if user message starts with recognized prefix (case-insensitive)
2. Extract task description (everything after the prefix and space)
3. If prefix is NOT "micro:", invoke SlashCommand tool with workflow-init
4. If prefix is "micro:", proceed directly without workflow setup
```

## Examples

### Example 1: Standard Workflow with Embedded Command
**User input:** `workflow: /apple-developer:code-legacy-modernize migrate @StateObject to @Environment`

**Claude MUST:**
1. Detect `workflow:` prefix
2. Extract task: `/apple-developer:code-legacy-modernize migrate @StateObject to @Environment`
3. Use SlashCommand tool: `/company-workflow:workflow-init "/apple-developer:code-legacy-modernize migrate @StateObject to @Environment"`
4. The workflow-init sets up context, then the workflow stages handle execution

### Example 2: Fast Workflow
**User input:** `fworkflow: Fix typo in login button`

**Claude MUST:**
1. Detect `fworkflow:` prefix
2. Extract task: `Fix typo in login button`
3. Use SlashCommand tool: `/company-workflow:workflow-init "Fix typo in login button" --fast`

### Example 3: Quick Workflow
**User input:** `quick: Add dark mode toggle`

**Claude MUST:**
1. Detect `quick:` prefix
2. Extract task: `Add dark mode toggle`
3. Use SlashCommand tool: `/company-workflow:workflow-init "Add dark mode toggle" --quick`

### Example 4: Micro Task (No Workflow)
**User input:** `micro: fix typo in README`

**Claude MUST:**
1. Detect `micro:` prefix
2. Execute the task directly without workflow initialization
3. No TodoWrite, no stage management, no .context folder

## Priority

This rule has **highest priority** for input processing. Before analyzing the user's request for complexity, before delegating to agents, Claude must first check for workflow trigger prefixes.

## Why This Matters

Without this rule, users who type `workflow: [task]` expect the full 8-stage workflow to be initialized. If Claude doesn't invoke `/company-workflow:workflow-init`, the workflow system isn't activated, and the task runs without proper stage management, TodoWrite integration, or approval gates.
