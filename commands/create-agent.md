---
name: create-agent
description: Create new agent definitions with proper structure, model selection, and best practices
model: sonnet
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
- `--tools <list>` - Tool access: read, write, edit, bash, all
- `--stage <code>` - Workflow stage integration: P, A, T, D, Q, W, F, S
- `--output <path>` - Output path (default: agents/<name>.md)

## Examples

```
/create-agent "database-admin" --purpose "Database schema design, query optimization, and migration management"
/create-agent "api-designer" --purpose "REST/GraphQL API design" --model haiku --template minimal
/create-agent "security-reviewer" --purpose "Security code review and vulnerability assessment" --model opus --tools read
/create-agent "test-automator" --purpose "Automated test generation" --stage Q --template comprehensive
```

## Templates

### Minimal
Basic structure for simple, focused agents:
- Frontmatter (name, description, model)
- Purpose section
- Core capabilities (3-5 items)
- Basic response approach

### Standard (Default)
Balanced structure for most agents:
- Frontmatter
- Purpose section
- Capabilities (organized by category)
- Workflow integration
- Response approach
- Related agents/commands

### Comprehensive
Full structure for complex agents:
- Frontmatter
- Expert purpose
- Detailed capabilities (multiple subsections)
- Behavioral traits
- Knowledge base
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
| Stage | D |

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

## Agent Structure Guidelines

### Frontmatter (Required)
```yaml
---
name: agent-name
description: Brief description for routing (1-2 sentences)
model: haiku|sonnet|opus
---
```

### Purpose Section
- Clear statement of agent's role
- Specific domain and boundaries
- Integration context

### Capabilities
- Organized by category
- Actionable, specific items
- No overlap with other agents

### Workflow Integration
- Stage codes (P, A, T, D, Q, W, F, S)
- Task System integration
- Handoff protocols

## Integration

This command is used by:
- prompt-engineer agent for creating new agents
- When expanding the agent ecosystem
- For specialized domain agents

## Related

- [prompt-engineer](../agents/prompt-engineer.md) - Prompt engineering agent
- [optimize-agent](./optimize-agent.md) - Optimize existing agents
- [prompt-audit](./prompt-audit.md) - Audit agent quality
