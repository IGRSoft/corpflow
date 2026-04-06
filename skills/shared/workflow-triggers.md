---
name: workflow-triggers
description: Workflow trigger prefixes (workflow:/fworkflow:/quick:/micro:) and gate logic. Use when parsing workflow trigger commands or understanding workflow activation.
---

# Workflow Triggers Reference

## Trigger Types

| Trigger | Stages | Use Case |
|---------|--------|----------|
| `workflow:` | PL→AR→TL→DV→QA→DC→FN→ST | Standard 8-stage |
| `secure-workflow:` | PL→AR→TL→DV→SR→QA→DC→RE→FN→ST | Security-critical (10-stage) |
| `full-workflow:` | PL→AR→TL→DV→SR→QA→DC→RE→FN→ST | Complete pipeline |
| `emergency:` | IR→DV→QA→RE→FN | Hotfix/incident response |
| `micro:` | Direct (with plan) | Single-file changes |

## Micro Trigger Behavior

`micro:` skips the full stage pipeline but still follows a lightweight flow:

1. **Context setup**: If Figma URLs are provided, create `.context/designs/` and capture screenshots
2. **Present plan**: Briefly describe the intended change (files, approach, design reference)
3. **Wait for approval**: STOP and wait for explicit user approval before editing code
4. **Execute**: Implement the change directly (no stage agents)
5. **Verify**: Run formatter/build check

Even trivial changes deserve a moment of alignment with the user.

## Command Options

| Option | Effect |
|--------|--------|
| `--milestone:N` | Execute GitHub milestone issues |
| `--milestone:N:ISSUE` | Execute specific issue |
| `--parallel:N` | N concurrent tracks (max 5) |
| `--secure` | Use 10-stage with SR, RE |
| `--ethics-review` | Add ET checkpoint after PL |
| `--sequential` | DC waits for QA (default: parallel) |
| `--worktree` | Use git worktrees for issue isolation (supports sparse checkout via `worktree.sparsePaths`, auto-cleanup, fast startup). Requires --milestone |

## Security & Restrictions

| Setting | Version | Effect |
|---------|---------|--------|
| `disableSkillShellExecution` | 2.1.91 | Disables inline shell execution in skills, custom slash commands, and plugin commands |

> Auto mode respects explicit user boundaries ("don't push", "wait for X before Y") even when the action would otherwise be allowed (v2.1.90+).

## Auto-Detection

From task keywords:
- **Priority**: `critical`, `urgent`, `blocker` → High; `minor`, `optional` → Low
- **Platform**: `ios`, `macos`, `tvos`, `watchos`, `visionos` → Specific platform
- **Design**: UI/UX keywords → Designer joins PL stage automatically

## Agent Teams (Experimental)

When `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is set, milestone workflows can use agent teams for parallel issue execution. Agent teams enable independent teammate sessions instead of Task-based orchestration tracks.

| Option | Effect |
|--------|--------|
| `--milestone:N` + agent teams | Each issue spawned as independent teammate |
| `--parallel:N` | Still respected as max concurrent teammates |

See `milestone-workflow.md § Agent Teams Mode` for patterns.
