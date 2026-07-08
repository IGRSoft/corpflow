---
name: cc-update
description: Update plugin agents, commands, and skills with new Claude Code features, then sync MEMORY.md and README.md version tracking
argument-hint: '<version> [--notes <url|text>] [--dry-run]'
allowed-tools: Read, Glob, Grep, Write, Edit, WebFetch
model: sonnet
related:
  - agents/prompt-engineer.md
  - commands/optimize-agent.md
  - commands/optimize-command.md
  - commands/prompt-audit.md
  - skills/agent-coordination/SKILL.md
  - skills/shared/stage-codes.md
  - skills/agent-coordination/references/hook-monitoring.md
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
- `--command <name>` - Restrict update to a specific command file (e.g., worktask)
- `--force` - Proceed even if version is older than current min version
- `--worktask-impact-only` - Emit just the `## Worktask Efficiency Impact` table (the standing efficiency-analysis pass output) for a quick read, without applying file edits

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

## Batch Worktask

For multi-version updates (e.g., 2.1.77 through 2.1.86):
1. Run `/cc-update <version> --dry-run` per version to preview cumulative impact
2. Apply updates version-by-version in chronological order
3. Add/extend one row in MEMORY.md `## CC Feature Band Index` (e.g. `2.1.77→2.1.86`); never write categorized feature narratives into MEMORY.md — those go only in the canonical band file (step 5)
4. Commit once after the full batch
5. Write the consolidated band file at the canonical path:
   `~/.claude/projects/<project-slug>/memory/cc-features-<FROM>-<TO>.md` using the prior band's structure (categorized: Model & Effort / Hooks / Tools / Plugins / Context / Performance / Subagents / Security / UX / Settings — only categories that apply).
6. **Plugin version bump policy** (the DV agent picks the tier and records rationale in `.context/development-N.md`; mirror across `MEMORY.md` "Plugin version" line and `.claude-plugin/plugin.json` if present):
   - **Patch (X.Y.Z → X.Y.Z+1):** additive, non-breaking, doc-only changes.
   - **Minor (X.Y.Z → X.Y+1.0):** new agent/skill/command added, or existing tools list expanded, or backwards-compatible behavior change.
   - **Major (X.Y.Z → X+1.0.0):** breaking change to existing agents/commands/skills (renames, removed tools, altered stage codes).

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

## Worktask Efficiency Impact

Output of the standing `## Worktask Efficiency Analysis (required pass)` (see the section below this fence). Behavioral rows lead — they each get an implementation task, prioritized above doc-only edits.

| Feature | Axis | Verdict | Improvement (mechanism) |
|---------|------|---------|--------------------------|
| Stop/SubagentStop `hookSpecificOutput.additionalContext` | Gates | **Behavioral** | DV screenshot-gate block path now emits actionable remediation into the re-run's context (self-healing gate) instead of a dead-end block |
| `claude agents --json waitingFor` | Resume/recovery | **Behavioral** | Resume loop reads `waitingFor` → 3-way reattach/await/re-dispatch, avoiding blind respawn of a waiting agent and redundant nudging of a busy one |
| ExitWorktree now GA | Parallelism | Doc-only | reference accuracy; no pipeline-execution change |
| Opus 4.7 model alias | Dispatch | N/A | no worktask gate/handoff/resume surface |

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

MEMORY.md is a lean rolling file (~5KB hard cap). Update ONLY:
1. `Plugin version:` line — keep the exact `- Plugin version: **X.Y.Z** (<one-line summary>)` shape (release tooling parses it)
2. `Claude Code latest integrated band` line
3. One new/extended row in `## CC Feature Band Index` — full categorized feature narratives go ONLY in the canonical band file (Batch step 5), never in MEMORY.md
4. Prepend one `## Release History` line: `- YYYY-MM-DD: vX.Y.Z — Claude Code {VERSION} update ({N} files, key changes)` (≤25 words); enforce the 12-row cap by deleting the oldest

| Field | Before | After |
|-------|--------|-------|
| Claude Code latest integrated band | 2.1.51→2.1.76 | 2.1.51→2.1.86 |
| Claude Code min required | 2.1.72 | 2.1.72 (unchanged) |

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
4. **If invoked under `/worktask`**: hand control back to the orchestrator. DR (technical-lead) reviews the diff; QA validates frontmatter integrity. Do NOT self-commit when running inside a worktask — FN (or the user, in compressed worktasks) owns the commit.
```

## Worktask Efficiency Analysis (required pass)

A **standing, required pass** run on every invocation (including `--dry-run`; skipped only under `--memory-only`). Feature Extraction answers *which files* a feature touches; this pass answers the question that surfaces behavioral wins: **how does each feature change worktask behavior/efficiency?** Its output is the `## Worktask Efficiency Impact` report table (inside Output Format above), and it is the explicit input that promotes a feature from "documented" to "implemented."

For each extracted feature, score it against the worktask **leverage axes** and assign a verdict:

**Leverage axes**:
- **Gates** — DV/DR/QA/SR feedback & hook blocks (e.g., `hookSpecificOutput.additionalContext`, screenshot-gate, gate-feedback contract).
- **Handoffs** — stage→stage compression, schema returns, cache-prefix prompt layout.
- **Resume/recovery** — session discovery, reattach vs re-dispatch (`claude agents --json`, `waitingFor`, PostCompact).
- **Parallelism** — worktree isolation, megatask tracks.
- **Dispatch** — headless CLI flags, permission/model/effort metadata.
- **Observability/Cost** — OTEL, audit rows, token baselines.

**Verdict per feature** (mutually exclusive):
- **Behavioral** — changes pipeline *execution* (a gate, handoff, resume loop, or parallelism mechanism). Gets its own implementation task, **prioritized above doc-only edits**. Record the *mechanism*: which gate/handoff/loop changes and how.
- **Doc-only** — accuracy / reference update; no execution change.
- **N/A** — no worktask surface.

Behavioral rows lead the `## Worktask Efficiency Impact` table so the report opens with the changes that alter how the pipeline runs. This pass feeds (and orders) Impact Mapping.

## Feature Category Mapping

How changelog entries are categorized and routed to affected files:

| Category | Keywords | Affected File Types |
|----------|----------|---------------------|
| **Hooks** | hook, PostToolUse, SubagentStart, PreToolUse, PostCompact, Elicitation, StopFailure, CwdChanged, FileChanged, TaskCreated, WorktreeCreate, conditional if, scheduled task, webhook, trigger delivery, task notification | agents with hook docs, agent-coordination skill, worktask resume reference |
| **Tools** | new tool, ExitWorktree, EnterWorktree, TaskCreate, worktree, SendMessage, TeamCreate/TeamDelete removed, implicit team, Agent(name:) spawn, team_name ignored | agents with tool in `tools:` frontmatter, task-system + agent-teams skills |
| **Model** | model alias, Opus/Sonnet/Haiku version, effort level, availableModels, /fast allowlist, model-deprecation | stage-codes skill, agents with full model IDs, model-selection skill |
| **Context** | compaction, context window, sparsePaths, worktree, circuit breaker, --fallback-model | context-compression skill, agent-coordination skill |
| **Subagents** | subagent, background agent, teammate, partial result, resume removed, implicit team, Agent(name:) spawn, pre-launch spawn classification, fg/bg nesting depth | agent-coordination skill, developer/project-manager agents, task-system + agent-teams skills |
| **MCP** | MCP, elicitation, server deduplication, deferred tools, description cap, server-level disallowedTools, auth-stub tools | agent-coordination skill, cross-plugin-handoff skill |
| **Cost** | token, cache, prompt cache, cost reduction | cost-optimization skill |
| **Frontmatter** | effort, maxTurns, disallowedTools, initialPrompt, paths YAML, description cap, Tool(param:value) permission syntax, model: deprecation | stage-codes skill, prompt-engineer agent, model-selection skill |
| **Commands** | slash command, /clear, /reload-plugins, Tool(param:value) permission syntax | worktask command, relevant command files, agent-coordination skill |
| **Security** | auto mode, destructive git block, commit --amend guard, IaC destroy block, trigger delivery can't auto-approve, attribution.sessionUrl, auth-stub tools headless | git-conventions skill, resume reference, security-reviewer agent |

## Integration

This command is used by:
- `prompt-engineer` agent for plugin updates after CC releases
- Manually, when a new Claude Code version adds features the plugin should leverage
- As a prerequisite before running `/prompt-audit`

Not part of the 9/11-stage worktask — standalone maintenance command with stage code **PE**. Recommended cadence: run within one week of each Claude Code release. Use `--dry-run` first to review impact scope, then apply.

The **`## Worktask Efficiency Analysis (required pass)`** runs on **every** invocation (including `--dry-run`, where it previews behavioral wins before any file is touched). It is skipped only under `--memory-only` (which deliberately bypasses file analysis). No new *required* flag is added — the surface stays stable; the optional `--worktask-impact-only` emits just the resulting `## Worktask Efficiency Impact` table for a quick read. This pass is the explicit gate that promotes a feature from "documented" to "implemented": every Behavioral verdict it produces becomes an implementation task ahead of doc-only edits.

## Worktask Routing (BINDING)

When this command is embedded in a `/worktask` invocation (e.g., `/worktask /cc-update X.Y.Z`), the orchestrator MUST route the implementation stage to `igrsoft:prompt-engineer`. Do NOT default to `igrsoft:developer`. Rationale: cc-update is metadata/prompt engineering, not platform code.

PL0 must set `metadata.agent: "igrsoft:prompt-engineer"` on the implementation task even when the worktask framework labels the stage slot as DV. This binding overrides the default DV → developer mapping for any worktask whose `metadata.embedded_commands` includes `cc-update`.

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| WebFetch unavailable or fails | Try in order: (a) Bash + `curl -fsSL https://api.github.com/repos/anthropics/claude-code/releases/tags/v<VERSION>` and parse the `body` field with `jq`; (b) `--notes <url\|text>` inline; (c) prompt the user. Do NOT silently proceed without notes. |
| No release notes for version | Report "No notes found" and exit without changes |
| Version older than current min | Warn and skip unless `--force` is used |
| `--scope` yields zero changes | Report clean scan; skip MEMORY.md update |
| MEMORY.md missing or malformed | Recreate the lean skeleton (Version Tracking + CC Feature Band Index + Release History) from scratch |
| Plugin version bump suggested | 3.2.0 → 3.3.0 |
| Team-tool removed by a band (e.g. TeamCreate/TeamDelete → implicit team) | Rewrite the team/coordination docs to the new model (`Agent(name: …)` spawn, `team_name` ignored). Bump **Minor**, not Major, when the removed tools were never in any agent's `tools:` frontmatter — no breaking change to plugin agents, only reference-doc corrections. |

