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
| `--with-design` | Include designer in PL |
| `--sequential` | DC waits for QA (default: parallel) |

## Auto-Detection

From task keywords:
- **Priority**: `critical`, `urgent`, `blocker` → High; `minor`, `optional` → Low
- **Platform**: `ios`, `macos`, `tvos`, `watchos`, `visionos` → Specific platform
