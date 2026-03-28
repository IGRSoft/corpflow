---
name: cc-update
description: Update plugin agents, commands, and skills with new Claude Code features, then sync MEMORY.md and README.md version tracking
argument-hint: '<version> [--notes <url|text>] [--dry-run]'
allowed-tools: Read, Glob, Grep, Write, Edit, WebFetch
model: sonnet
---

# Claude Code Plugin Update Command

Update plugin agents, commands, and skills to leverage new Claude Code features, deep analyze new features to see full picture of changes. Reads release notes (auto-fetched or provided), maps new capabilities to affected plugin files, applies updates, and syncs MEMORY.md version tracking and README.md min version.

## Version Source

Read current minimum Claude Code version from `README.md` line:
```
claude-code min version: "X.Y.Z"
```

At the end of the update, bump this value in `README.md` to the new version when breaking changes or new required features are detected. If no breaking changes, keep the existing min version and note it in the report.

## Usage

```
/cc-update 2.1.77
/cc-update 2.1.77 --notes https://github.com/anthropics/claude-code/releases/tag/v2.1.77
/cc-update 2.1.77 --notes "New PostToolUse hook; ExitWorktree now GA for all agents"
/cc-update 2.1.77 --scope agents --dry-run
```

## Options

- `<version>` - Claude Code version in X.Y.Z format (e.g., 2.1.77) [required, positional]
- `--notes <url|text>` - Release notes URL or raw text (optional; auto-fetches from GitHub releases if omitted)
- `--scope <agents|commands|skills|all>` - Scope of files to update (default: all)
- `--dry-run` - Preview all proposed changes without writing files
- `--memory-only` - Skip file updates; update only MEMORY.md version tracking
- `--bump-min` - Force bump `README.md` min version even without breaking changes
- `--agent <name>` - Restrict update to a specific agent file (e.g., developer)
- `--command <name>` - Restrict update to a specific command file (e.g., workflow)
- `--force` - Proceed even if version is older than current min version

## Examples

```
# Full update — fetch notes, scan all files, apply changes, update README min version
/cc-update 2.1.77 --notes https://github.com/anthropics/claude-code/releases/tag/v2.1.77

# Dry-run first to preview impact before touching files
/cc-update 2.1.77 --dry-run

# Update only MEMORY.md after manually editing agents
/cc-update 2.1.77 --memory-only

# Agents-only scope with inline release text
/cc-update 2.1.77 --scope agents --notes "New Elicitation hook; team agents inherit model"

# Target a single agent for surgical update
/cc-update 2.1.77 --agent developer --notes "EnterWorktree now supports sparse paths"

# Force bump min version even if no breaking changes detected
/cc-update 2.1.77 --bump-min
```

## Batch Workflow

For multi-version updates (e.g., 2.1.77 through 2.1.86):
1. Run `/cc-update <version> --dry-run` per version to preview cumulative impact
2. Apply updates version-by-version in chronological order
3. Consolidate MEMORY.md entries into a range header (e.g., "Claude Code 2.1.77→2.1.86")
4. Commit once after the full batch

## Output Format

```markdown
# Claude Code Update Report — v2.1.77

## Release Summary

| Field | Value |
|-------|-------|
| CC Version | 2.1.77 |
| Previous Min Version | 2.1.76 (from README.md) |
| Notes Source | https://github.com/anthropics/claude-code/releases/tag/v2.1.77 |
| Scope | all |
| Dry Run | No |
| Files Scanned | 78 |

## Feature Extraction

| Feature | Category | Impact Level |
|---------|----------|-------------|
| PostToolUse hook added | Hooks | High |
| ExitWorktree now GA | Tools | Medium |
| Opus 4.7 model alias registered | Model | Medium |
| Sparse worktree path filtering | Context | Low |

## Impact Mapping

### High Impact

#### PostToolUse hook — agents/developer.md, skills/agent-coordination.md

**Why affected**: `developer` documents hook patterns; `agent-coordination` skill covers SubagentStart/SubagentStop — PostToolUse extends this pattern.

**Proposed changes**:
- `agents/developer.md` — Add PostToolUse to hook documentation block
- `skills/agent-coordination.md` — Add PostToolUse row to Hook-Based Stage Monitoring table

<!-- Medium and Low impact entries follow the same structure with proportionally less detail -->

## Files Modified

| File | Status | Changes |
|------|--------|---------|
| agents/developer.md | ✅ Updated | PostToolUse hook + GA worktree note |
| agents/workflow-engineer.md | ✅ Updated | GA worktree note |
| skills/agent-coordination.md | ✅ Updated | PostToolUse row, sparsePaths note |
| skills/shared/stage-codes.md | ✅ Updated | Model alias footnote |

## MEMORY.md Update

Add version section under `## Claude Code {VERSION} Key Features Integrated` with categorized entries (`### Hooks`, `### Tools`, etc.). Update version fields:

| Field | Before | After |
|-------|--------|-------|
| Claude Code latest known | 2.1.76 | 2.1.77 |
| Claude Code min required | 2.1.72 | 2.1.72 (unchanged) |

Add optimization history entry: `- YYYY-MM-DD: vX.Y.Z — Claude Code {VERSION} update ({N} files, key changes)`

## README.md Min Version Update

| Field | Before | After | Reason |
|-------|--------|-------|--------|
| claude-code min version | "2.1.76" | "2.1.77" | PostToolUse hook required by updated patterns |

Bump when updated files depend on new CC capabilities. Use `--bump-min` to force.

## Summary

| Metric | Value |
|--------|-------|
| Features extracted | 4 |
| Files updated | 4 |
| Files unchanged | 74 |
| MEMORY.md updated | Yes |
| README.md min version | 2.1.76 → 2.1.77 |

## Next Steps

1. Review changes: `git diff agents/ skills/ README.md`
2. Run `/prompt-audit --agents` to verify consistency
3. Commit: `#N chore: update plugin for Claude Code v2.1.77 features`
```

## Feature Category Mapping

How changelog entries are categorized and routed to affected files:

| Category | Keywords | Affected File Types |
|----------|----------|---------------------|
| **Hooks** | hook, PostToolUse, SubagentStart, PreToolUse, PostCompact, Elicitation, StopFailure, CwdChanged, FileChanged, TaskCreated, WorktreeCreate, conditional if | agents with hook docs, agent-coordination skill |
| **Tools** | new tool, ExitWorktree, EnterWorktree, TaskCreate, worktree, SendMessage | agents with tool in `tools:` frontmatter |
| **Model** | model alias, Opus/Sonnet/Haiku version, effort level | stage-codes skill, agents with full model IDs |
| **Context** | compaction, context window, sparsePaths, worktree, circuit breaker | context-compression skill, agent-coordination skill |
| **Subagents** | subagent, background agent, teammate, partial result, resume removed | agent-coordination skill, developer/project-manager agents |
| **MCP** | MCP, elicitation, server deduplication, deferred tools, description cap | agent-coordination skill, cross-plugin-handoff skill |
| **Cost** | token, cache, prompt cache, cost reduction | cost-optimization skill |
| **Frontmatter** | effort, maxTurns, disallowedTools, initialPrompt, paths YAML, description cap | stage-codes skill, prompt-engineer agent |
| **Commands** | slash command, /clear, /reload-plugins | workflow command, relevant command files |

## Integration

This command is used by:
- `prompt-engineer` agent for plugin updates after CC releases
- Manually, when a new Claude Code version adds features the plugin should leverage
- As a prerequisite before running `/prompt-audit`

Not part of the 8/10-stage workflow — standalone maintenance command with stage code **PE**. Recommended cadence: run within one week of each Claude Code release. Use `--dry-run` first to review impact scope, then apply.

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| WebFetch fails | Fall back to `--notes` inline text; prompt user if neither available |
| No release notes for version | Report "No notes found" and exit without changes |
| Version older than current min | Warn and skip unless `--force` is used |
| `--scope` yields zero changes | Report clean scan; skip MEMORY.md update |
| MEMORY.md missing or malformed | Create version tracking section from scratch |
| Plugin version bump suggested | 3.2.0 → 3.3.0 |

## Related

- [prompt-engineer](../agents/prompt-engineer.md) - Prompt engineering agent (primary user)
- [optimize-agent](./optimize-agent.md) - Optimize individual agents post-update
- [optimize-command](./optimize-command.md) - Optimize individual commands post-update
- [prompt-audit](./prompt-audit.md) - Audit ecosystem after updates are applied
- [agent-coordination](../skills/agent-coordination.md) - Hook and subagent patterns updated by this command
- [stage-codes](../skills/shared/stage-codes.md) - Frontmatter fields and model references updated by this command
- [hook-monitoring](../skills/agent-coordination/references/hook-monitoring.md) - Hook lifecycle patterns updated by this command
