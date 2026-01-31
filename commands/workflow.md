# Workflow Command

Initialize a new workflow task with proper folder structure and Task System integration.

## Usage

```
/workflow --milestone:N              # Execute milestone N issues by priority
/workflow --milestone:N:ISSUE        # Execute specific issue from milestone N
/workflow "Task Title" [options]     # Execute a custom task
```

## Workflow Types

| Type | Stages | Trigger |
|------|--------|---------|
| Standard | PL→AR→TL→DV→QA→DC→FN→ST | `/workflow` |
| Secure | PL→AR→TL→DV→SR→QA→DC→RE→FN→ST | `--secure` |
| Emergency | IR→DV→QA→RE→FN | `/emergency` |

See `skills/shared/stage-codes.md` for stage details.

## Options

| Option | Effect |
|--------|--------|
| `--milestone:N` | Execute GitHub milestone N issues |
| `--milestone:N:ISSUE` | Execute specific issue |
| `--parallel:N` | N concurrent tracks (max 5) |
| `--auto-continue` | Skip approval gates |
| `--priority [High\|Medium\|Low]` | Task priority |
| `--platform <apple\|android\|web\|all>` | Target platform |
| `--with-design` | Include designer in PL |
| `--ethics-review` | Add ET checkpoint after PL |
| `--sequential` | DC waits for QA |
| `--secure` / `--full` | Use 10-stage workflow |

## Examples

```bash
# Milestone mode
/workflow --milestone:1
/workflow --milestone:1 --parallel:3
/workflow --milestone:2:123

# Standard mode
/workflow "Add dark mode support" --with-design
/workflow "Fix login crash" --priority High

# Secure workflow
/workflow "Implement OAuth" --secure

# Emergency
/emergency "Production login failing"
```

## What This Command Does

1. **Creates Context Folder**: `.context/` with `images/` subdirectory
2. **Creates planning.md Template**: Requirements, acceptance criteria, success metrics
3. **Creates Tasks with Dependencies**: See `skills/workflow.md` for task creation pattern
4. **Starts Planning Phase**: Prompts for requirements gathering

## Milestone Mode

When using `--milestone:N`, operates in **workspace mode**:

```
.workspaces/
├── orchestrator.json              # Root orchestrator state
└── milestone-{N}/
    └── {issue#}/
        ├── .context/              # Isolated artifacts
        ├── workspace.json         # Workspace state
        └── handoff.md             # Compressed context
```

### Orchestrator State

```json
{
  "milestone": { "number": 1, "title": "Sprint 1" },
  "configuration": { "parallel_tracks": 3 },
  "issues": [{ "number": 42, "status": "in_progress", "track": 1 }],
  "summary": { "total": 5, "completed": 1, "in_progress": 1, "pending": 3 }
}
```

### Track-Prefixed Task IDs

| Track | Task IDs |
|-------|----------|
| 1 | t1-1, t1-2, t1-3 |
| 2 | t2-1, t2-2, t2-3 |

See `skills/milestone-workflow.md` for full workspace documentation.

## Dynamic Sizing

Workflows are sized during PL/AR based on complexity (0-50 score):

| Score | Stages |
|-------|--------|
| 0-10 | PL → DV → QA |
| 11-20 | PL → AR → DV → QA |
| 21-30 | PL → AR → TL → DV → QA |
| 31+ | All stages |

See `skills/workflow.md` for complexity assessment.

## Workflow Modes

### Standard (`/workflow`)
- Full 8-stage process
- Stops at PL3 for user approval
- Dynamic stage deletion based on complexity

### With Design (`--with-design`)
- Designer joins PL stage for UX/UI input
- Adds design specifications to artifacts

### Ethics Review (`--ethics-review`)
Inserts ET stage after PL:
```
PL → ET → AR → TL → DV → QA → DC → FN → ST
```

Recommended for: user tracking, algorithmic recommendations, financial transactions, content moderation.

### Secure (`--secure`, `--full`)
10-stage with SR (Security Review) and RE (Release Engineering):
```
PL → AR → TL → DV → SR → QA → DC → RE → FN → ST
```

Use for: authentication, payments, PII, cryptography, external API secrets.

### Emergency (`/emergency`)
5-stage rapid response:
```
IR → DV → QA → RE → FN
```

## Output

```
Workflow Initiated (Standard)

Task: Add dark mode support
Location: .context/
Mode: Standard (will pause at PL3 for approval)

I've initiated the workflow. Starting planning...
```

## Next Steps

1. Complete planning.md with requirements
2. PL stage may delete unnecessary stages
3. PL3 approval gate - wait for user approval
4. Continue through remaining stages

## Related

- `skills/workflow.md` - Complete workflow documentation
- `skills/milestone-workflow.md` - GitHub milestone integration
- `skills/task-folder-organization.md` - Folder structure
- `agents/workflow-engineer.md` - Troubleshooting
