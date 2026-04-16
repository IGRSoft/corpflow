---
name: create-agent
description: Create new agent definitions with proper structure, model selection, and best practices
argument-hint: <agent name and purpose>
model: sonnet
allowed-tools: Read, Glob, Grep, Write
---

# Create Agent Command

Create new agent definitions with proper structure, model selection, and best practices. Generates production-ready agent files.

## Usage

```
/create-agent <name> --purpose <description>
/create-agent "database-admin" --purpose "Database administration and optimization"
/create-agent "api-designer" --model haiku --template minimal
```

## Options

- `--purpose <description>` - Agent purpose (required)
- `--model <haiku|sonnet|opus>` - Model selection (default: auto-select)
- `--template <minimal|standard|comprehensive>` - Template style (default: standard)
- `--tools <preset|list>` - Tool access preset or comma-separated list (see Tool Presets)
- `--stage <code>` - Workflow stage integration: PL, AR, TL, DV, DR, SR, QA, DC, RE, FN, ST, IR
- `--output <path>` - Output path (default: agents/<name>.md)

## Examples

```
/create-agent "database-admin" --purpose "Database schema design, query optimization, and migration management"
/create-agent "api-designer" --purpose "REST/GraphQL API design" --model haiku --template minimal
/create-agent "security-reviewer" --purpose "Security code review and vulnerability assessment" --model opus --tools read
/create-agent "test-automator" --purpose "Automated test generation" --stage QA --template comprehensive
```

## Templates

### Minimal
Basic structure for simple, focused agents:
- Frontmatter (name, description, model)
- Constraints (DO NOT) section (3 items)
- Purpose section
- Core capabilities (3-5 items)
- Basic response approach

### Standard (Default)
Balanced structure for most agents:
- Frontmatter (name, description, model, tools)
- Constraints (DO NOT) section (3-5 items)
- Purpose section
- Capabilities (organized by category)
- Workflow integration
- Task System integration
- Model Usage Note
- Constitutional Alignment (reference `skills/shared/constitutional-base.md`)
- Response approach
- Related agents/commands

### Comprehensive
Full structure for complex agents:
- Frontmatter (name, description, model, tools)
- Constraints (DO NOT) section (5-7 items)
- Expert purpose
- Detailed capabilities (multiple subsections)
- Behavioral traits
- Knowledge base
- Workflow integration with Task System format
- Model Usage Note with rationale
- Constitutional Alignment with agent-specific focus
- Response approach (numbered steps)
- Example interactions
- Anti-patterns
- Integration points

## Output Format

```markdown
# Agent Created: database-admin

## Generated File
`agents/database-admin.md`

## Configuration

| Setting | Value |
|---------|-------|
| Name | database-admin |
| Model | sonnet |
| Template | standard |
| Tools | read, bash |
| Stage | DV |

## Preview

---
name: database-admin
description: Database specialist for schema design, query optimization, and migration management. Handles PostgreSQL, MySQL, and SQLite with focus on performance and data integrity.
model: sonnet
---

You are a database administration specialist focused on schema design, query optimization, and migration management...

[Preview of first 500 characters]

## Model Selection Rationale

**Selected**: sonnet
**Reason**: Task involves moderate analysis (query optimization) and implementation (schema design) requiring balanced reasoning capabilities.

**Alternatives Considered**:
- haiku: Too limited for query optimization analysis
- opus: Overkill for standard database operations

## Next Steps

1. Review generated agent at `agents/database-admin.md`
2. Customize capabilities for your specific database stack
3. Add domain-specific examples
4. Test with `/optimize-agent agents/database-admin.md --dry-run`
```

## Model Auto-Selection

When `--model` is not specified, selection based on purpose analysis:

| Purpose Keywords | Model | Rationale |
|-----------------|-------|-----------|
| format, convert, check, validate | haiku | Procedural tasks |
| implement, review, analyze, design | sonnet | Balanced reasoning |
| architect, strategize, optimize, research | opus | Complex reasoning |

## Tool Presets

When using `--tools`, specify a preset name or a comma-separated tool list:

| Preset | Expands To |
|--------|-----------|
| read-only | Read, Glob, Grep |
| standard | Read, Glob, Grep, Write, Edit, Bash |
| full | Read, Glob, Grep, Write, Edit, Bash, TaskUpdate, TaskGet, TaskList |
| orchestrator | Read, Glob, Grep, Write, Edit, Bash, TaskCreate, TaskUpdate, TaskGet, TaskList |
| design | Read, Glob, Grep, Write, ToolSearch, TaskGet, TaskList |

### Cross-Plugin Delegation
Add Task delegation syntax to any preset: `--tools full,Task(apple-developer:ios-developer)`

## Agent Structure Guidelines

### Frontmatter (Required)
```yaml
---
name: agent-name
description: Brief description for routing (1-2 sentences). Use PROACTIVELY for...
model: haiku|sonnet|opus
tools: Read, Glob, Grep, Write, Edit, TaskUpdate, TaskGet, TaskList
---
```

### Description Best Practices
- Include "Use PROACTIVELY for..." to improve agent routing
- Example: "Database specialist for schema design. Use PROACTIVELY for query optimization, migration planning, or database architecture decisions."

### Constraints (DO NOT) Section
- First section after frontmatter identity sentence
- 3-7 specific prohibitions defining agent boundaries
- Example: "DO NOT modify production code directly" for QA agents

### Purpose Section
- Clear statement of agent's role
- Specific domain and boundaries
- Integration context

### Capabilities
- Organized by category
- Actionable, specific items
- No overlap with other agents

### Workflow Integration
- Stage codes (PL, AR, TL, DV, DR, SR, QA, DC, RE, FN, ST, IR)
- Task System integration
- Handoff protocols

### Model Usage Note
- Explain why the selected model is appropriate
- Reference task complexity and reasoning requirements

### Constitutional Alignment
- Reference `skills/shared/constitutional-base.md`
- Add agent-specific ethical focus areas

## Integration

This command is used by:
- prompt-engineer agent for creating new agents
- When expanding the agent ecosystem
- For specialized domain agents

## Related

- [prompt-engineer](../agents/prompt-engineer.md) - Prompt engineering agent
- [optimize-agent](./optimize-agent.md) - Optimize existing agents
- [create-command](./create-command.md) - Create new commands
- [create-skill](./create-skill.md) - Create new skills
- [prompt-audit](./prompt-audit.md) - Audit agent quality
