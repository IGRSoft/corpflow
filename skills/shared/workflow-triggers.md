# Workflow Triggers Reference

## Trigger Types

| Trigger | Stages | Use Case |
|---------|--------|----------|
| `workflow:` | PL→AR→TL→DV→QA→DC→FN→ST | Standard 8-stage |
| `secure-workflow:` | PL→AR→TL→DV→SR→QA→DC→RE→FN→ST | Security-critical (10-stage) |
| `full-workflow:` | PL→AR→TL→DV→SR→QA→DC→RE→FN→ST | Complete pipeline |
| `emergency:` | IR→DV→QA→RE→FN | Hotfix/incident response |
| `micro:` | Direct | Single-file changes |

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
