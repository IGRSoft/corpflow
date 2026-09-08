---
name: cc-update
description: Update plugin agents, commands, and skills with new Claude Code features, then sync MEMORY.md and README.md version tracking
version: 0.2.0
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

Read the release notes (auto-fetched or `--notes`), map the new capabilities to affected plugin files, apply the updates, then sync MEMORY.md version tracking and the README.md min version.

## Usage

```
/cc-update <version> [--notes <url|text>] [--scope agents|commands|skills|all] [--dry-run]
```

## Options

| Option | Meaning |
|--------|---------|
| `<version>` | CC version `X.Y.Z` (e.g. 2.1.77) — required, positional |
| `--notes <url\|text>` | Notes URL or raw text; auto-fetches from GitHub releases if omitted |
| `--scope <agents\|commands\|skills\|all>` | Files to update (default: `all`) |
| `--dry-run` | Preview proposed changes; write nothing |
| `--memory-only` | MEMORY.md tracking only; skips file analysis |

### Options — narrowing and overrides

| Option | Meaning |
|--------|---------|
| `--agent <name>` | Restrict to one agent file (e.g. `developer`) |
| `--command <name>` | Restrict to one command file (e.g. `worktask`) |
| `--bump-min` | Force the README.md min-version bump without breaking changes |
| `--force` | Proceed when `<version>` is older than the current min |
| `--worktask-impact-only` | Emit just the `## Worktask Efficiency Impact` table; no file edits |

## Examples

```
/cc-update 2.1.77 --notes https://github.com/anthropics/claude-code/releases/tag/v2.1.77
/cc-update 2.1.77 --dry-run                    # preview impact first
/cc-update 2.1.77 --memory-only                # after manual agent edits
/cc-update 2.1.77 --agent developer            # surgical single file
/cc-update 2.1.77 --bump-min                   # force min bump
/cc-update 2.1.77 --scope agents --notes "New Elicitation hook; agents inherit model"
/cc-update 2.1.77 --command worktask           # one command file
/cc-update 2.1.70 --force                      # older than the recorded min version
/cc-update 2.1.77 --worktask-impact-only       # impact table only, no file edits
```

## Version Source

`README.md` carries `claude-code min version: "X.Y.Z"` — the "previous min". Bump it when updated files depend on new or newly-required CC capabilities, or on `--bump-min`; otherwise keep it and say so in the report.

## Batch Worktask

Multi-version updates (e.g. 2.1.77 through 2.1.86):

1. `--dry-run` per version for cumulative impact.
2. Apply chronologically, version by version.
3. Add/extend ONE MEMORY.md `## CC Feature Band Index` row (e.g. `2.1.77→2.1.86`); categorized narratives never go into MEMORY.md, only into the band file (step 5).
4. Commit once after the full batch.
5. Write the band file at `~/.claude/projects/<project-slug>/memory/cc-features-<FROM>-<TO>.md`, reusing the prior band's categories (Model & Effort / Hooks / Tools / Plugins / Context / Performance / Subagents / Security / UX / Settings — applicable ones only).
6. Apply the bump policy below.

### Plugin Version Bump Policy

Batch step 6. DV picks the tier, records the rationale in `.context/development-N.md`, and mirrors it in the MEMORY.md `Plugin version` line and `.claude-plugin/plugin.json` if present.

| Tier | Trigger |
|------|---------|
| **Patch** X.Y.Z+1 | Additive, non-breaking, doc-only |
| **Minor** X.Y+1.0 | New agent/skill/command, expanded tools list, or backwards-compatible behavior change |
| **Major** X+1.0.0 | Breaking: renames, removed tools, altered stage codes |

## Worktask Efficiency Analysis (required pass)

Standing pass on **every** invocation, `--dry-run` included (there it previews behavioral wins before any file is touched); skipped only under `--memory-only`, which bypasses file analysis by design. No required flag is added — `--worktask-impact-only` only narrows the output.

Feature Extraction answers *which files* a feature touches; this pass answers *how it changes worktask behavior*, and is the gate promoting a feature from "documented" to "implemented". Score each feature against the leverage axes, assign exactly one verdict, emit `## Worktask Efficiency Impact`, and order Impact Mapping by it.

### Leverage Axes

- **Gates** — DV/DR/QA/SR feedback and hook blocks (`hookSpecificOutput.additionalContext`, screenshot gate, gate-feedback contract).
- **Handoffs** — stage→stage compression, schema returns, cache-prefix prompt layout.
- **Resume/recovery** — session discovery, reattach vs re-dispatch (`claude agents --json`, `waitingFor`, PostCompact).
- **Parallelism** — worktree isolation, megatask tracks.
- **Dispatch** — headless CLI flags, permission/model/effort metadata.
- **Observability/Cost** — OTEL, audit rows, token baselines.

### Verdict per Feature (mutually exclusive)

- **Behavioral** — changes pipeline *execution* (gate, handoff, resume loop, parallelism). Gets its own implementation task, **prioritized above doc-only edits**; record the *mechanism* — which gate/handoff/loop changes, and how. Behavioral rows lead the impact table.
- **Doc-only** — accuracy/reference update; no execution change.
- **N/A** — no worktask surface (e.g. a model alias).

## Feature Category Mapping

Changelog entries are categorized by keyword and routed to the file types below.

### Categories — Hooks, Tools

| Category | Keywords | Affected files |
|----------|----------|----------------|
| **Hooks** | hook, PostToolUse, SubagentStart, PreToolUse, PostCompact, Elicitation, StopFailure, CwdChanged, FileChanged, TaskCreated, WorktreeCreate, conditional if, scheduled task, webhook, trigger delivery, task notification | agents with hook docs, agent-coordination, worktask resume reference |
| **Tools** | new tool, ExitWorktree, EnterWorktree, TaskCreate, worktree, SendMessage, TeamCreate/TeamDelete removed, implicit team, Agent(name:) spawn, team_name ignored | agents with the tool in `tools:`, state-ledger + agent-teams |

### Categories — Model, Context, Subagents

| Category | Keywords | Affected files |
|----------|----------|----------------|
| **Model** | model alias, Opus/Sonnet/Haiku version, effort level, availableModels, /fast allowlist, model-deprecation | stage-codes, agents with full model IDs, model-selection |
| **Context** | compaction, context window, sparsePaths, worktree, circuit breaker, --fallback-model | context-compression, agent-coordination |
| **Subagents** | subagent, background agent, teammate, partial result, resume removed, implicit team, Agent(name:) spawn, pre-launch spawn classification, fg/bg nesting depth | agent-coordination, developer + project-manager agents, state-ledger + agent-teams |

### Categories — MCP, Cost, Frontmatter

| Category | Keywords | Affected files |
|----------|----------|----------------|
| **MCP** | MCP, elicitation, server deduplication, deferred tools, description cap, server-level disallowedTools, auth-stub tools | agent-coordination, cross-plugin-handoff |
| **Cost** | token, cache, prompt cache, cost reduction | cost-optimization |
| **Frontmatter** | effort, maxTurns, disallowedTools, initialPrompt, paths YAML, description cap, Tool(param:value) permission syntax, model: deprecation | stage-codes, prompt-engineer agent, model-selection |

### Categories — Commands, Security

| Category | Keywords | Affected files |
|----------|----------|----------------|
| **Commands** | slash command, /clear, /reload-plugins, Tool(param:value) permission syntax | worktask + relevant command files, agent-coordination |
| **Security** | auto mode, destructive git block, commit --amend guard, IaC destroy block, trigger delivery can't auto-approve, auth-stub tools headless | git-conventions, resume reference, security-reviewer agent |

## Output Format

One markdown report, `# Claude Code Update Report — v<VERSION>`, with these sections in order.

### Output Format — sections

| Section | Content |
|---------|---------|
| `## Release Summary` | `Field \| Value`: CC Version, Previous Min Version (from README.md), Notes Source, Scope, Dry Run, Files Scanned |
| `## Feature Extraction` | `Feature \| Category \| Impact Level` — category per Feature Category Mapping; impact High/Medium/Low |
| `## Worktask Efficiency Impact` | `Feature \| Axis \| Verdict \| Improvement (mechanism)` — the required pass's output; Behavioral rows first, then Doc-only, then N/A, one row shape throughout |
| `## Impact Mapping` | `### High/Medium/Low Impact` groups; per feature a `#### <feature> — <files>` block with **Why affected** and **Proposed changes** (`path — change` per file), detail decreasing by tier |

### Output Format — sections (cont.)

| Section | Content |
|---------|---------|
| `## Files Modified` | `File \| Status \| Changes`; status `✅ Updated` |
| `## MEMORY.md Update` | Rules below, plus `Field \| Before \| After` for the integrated band and min required version |
| `## README.md Min Version Update` | `Field \| Before \| After \| Reason` for `claude-code min version` |
| `## Summary` | `Metric \| Value`: features extracted, files updated, files unchanged, MEMORY.md updated, min version transition |
| `## Next Steps` | The 4 steps below |

### Output Format — MEMORY.md rules

MEMORY.md is a lean rolling file (~5KB hard cap). Trim BEFORE writing — an oversized write errors explicitly, never silently truncates. Update ONLY:

1. `- Plugin version: **X.Y.Z** (<one-line summary>)` — keep that exact shape; release tooling parses it.
2. The `Claude Code latest integrated band` line.
3. One new/extended `## CC Feature Band Index` row — narratives live only in the band file (Batch step 5).
4. One prepended `## Release History` line, `- YYYY-MM-DD: vX.Y.Z — Claude Code {VERSION} update ({N} files, key changes)` (≤25 words); enforce the 12-row cap by deleting the oldest.

### Output Format — Next Steps

1. Review: `git diff agents/ skills/ README.md`
2. `/prompt-audit --agents` to verify consistency
3. Commit: `#N chore: update plugin for Claude Code v<VERSION> features`
4. **Under `/worktask`**: hand back to the orchestrator — DR reviews the diff, QA validates frontmatter. Never self-commit inside a worktask; FN (or the user, in compressed worktasks) owns the commit.

## Integration

Used by the `prompt-engineer` agent after CC releases, manually when a release adds features worth leveraging, and as a prerequisite for `/prompt-audit`.

Standalone maintenance command with stage code **PE**, outside the 9/11-stage worktask. Cadence: within a week of each CC release — `--dry-run` first, then apply.

## Worktask Routing (BINDING)

Embedded in a worktask (e.g. `/worktask /cc-update X.Y.Z`), the implementation stage MUST route to `corpflow:prompt-engineer`, never the default `corpflow:developer` — cc-update is metadata/prompt engineering, not platform code.

PL0 MUST set `metadata.agent: "corpflow:prompt-engineer"` on the implementation task even when the framework labels that slot DV. This overrides the DV → developer mapping for any worktask whose `metadata.embedded_commands` includes `cc-update`.

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| WebFetch unavailable or fails | In order: (a) Bash + `curl -fsSL https://api.github.com/repos/anthropics/claude-code/releases/tags/v<VERSION>`, parsing `body` with `jq`; (b) inline `--notes <url\|text>`; (c) ask the user. Never silently proceed without notes. |
| No notes for the version | Report "No notes found"; exit without changes |
| Version older than current min | Warn and skip unless `--force` |
| `--scope` yields zero changes | Report clean scan; skip the MEMORY.md update |
| MEMORY.md missing/malformed | Recreate the lean skeleton (Version Tracking + CC Feature Band Index + Release History) |

### Edge Cases — Team-Tool Removal

| Scenario | Behavior |
|----------|----------|
| Team tool removed by a band (e.g. TeamCreate/TeamDelete → implicit team) | Rewrite team/coordination docs to the new model (`Agent(name: …)` spawn, `team_name` ignored). Bump **Minor**, not Major, when the removed tools were never in any agent's `tools:` frontmatter — reference-doc corrections only, no breaking change. |
