# Milestone Initialization & Workflow Setup

## Conventions used in this document

- **`planFile`** — the plan filename PL produced for the current workflow run (`planning-N.md`, e.g. `planning-0.md`, `planning-3.md`). Computed by PL0 per `agents/product-manager.md § Plan File Naming`. Every downstream task carries it as `metadata.plan_file`; the same value is interpolated into `context_files`. Stage agents resolve the plan file from `task.metadata.plan_file` first, then newest `.context/planning-*.md`.
- **handoff-protocol mode** — the preferred metadata mode (per `skills/workflow/references/handoff-protocol.md`): tasks carry `state_file` + `context_refs` (anchor list); legacy `context_files` is retained for fallback path F1 (state.json absent). Examples below show both forms — use `context_refs` for new code; keep `context_files` as the safety net.

## PL0 state.json Initialization (Phase 1)

PL0 (or `commands/workflow.md` Phase 1) creates `.context/state.json` immediately after `mkdir -p .context/`. This seeds the workflow ledger that every subsequent stage reads and patches.

```bash
mkdir -p .context/

# Atomic write: temp + fsync + rename
tmp=".context/.state.json.$$.${RANDOM}.tmp"
cat > "$tmp" <<EOF
{
  "version": 1,
  "workflow_id": "${WORKFLOW_ID}",
  "plan_file": ".context/${PLAN_FILE}",
  "platform": "${PLATFORM:-all}",
  "stages": { "PL": { "status": "in_progress" } },
  "facts": {
    "files_modified": [],
    "tests_added": [],
    "decisions": [],
    "open_questions": [],
    "verdicts": {}
  },
  "handoffs": {}
}
EOF
sync "$tmp" 2>/dev/null || true
mv -f "$tmp" .context/state.json
```

Subsequent stage agents read `.context/state.json` first; if absent, they fall back to legacy `metadata.context_files` mode (path F1). See `handoff-protocol.md#fallback-paths`.

## Hook Installation

PL0 (or `commands/workflow.md` Phase 1) MUST verify the `state-merge.sh` SubagentStop hook is installed before proceeding. This hook is the Layer 2 safety net — it patches `state.json` from artifact frontmatter when stage agents forget to self-patch (Layer 1) or when the orchestrator's Step 6.5 check is skipped.

```bash
# Idempotent hook installation — run after state.json seed, before PL0 delegation.
# Source: ${CLAUDE_PLUGIN_ROOT}/.claude/hooks/state-merge.sh (ships with igrsoft plugin).

hook_src="${CLAUDE_PLUGIN_ROOT}/.claude/hooks/state-merge.sh"
hook_dst=".claude/hooks/state-merge.sh"

if [[ ! -x "$hook_dst" ]]; then
  mkdir -p .claude/hooks
  cp "$hook_src" "$hook_dst"
  chmod +x "$hook_dst"
fi
```

**PL0 invariant**: Before continuing to TaskCreate, verify:
1. `.context/state.json` exists and is valid JSON
2. `.claude/hooks/state-merge.sh` exists and is executable
3. The plugin's `plugin.json` registers the SubagentStop hook (this is declarative — no project-local action needed)

If hook source is not found (e.g. `CLAUDE_PLUGIN_ROOT` unset), log a warning and continue — the plugin.json-registered hook will still fire via the plugin hook system. The project-local copy is a belt-and-suspenders fallback for environments where plugin hooks are not supported.

### Sample TaskCreate using context_refs (handoff-protocol mode)

```typescript
const ar0 = TaskCreate({
  subject: "AR0: Architecture",
  description: "Design dark mode architecture with theme switching",
  activeForm: "Architecting solution",
  metadata: {
    stage: "AR", agent: "igrsoft:software-architector", model: "opus",
    error_file: ".context/errors/software-architector.md",
    state_file: ".context/state.json",
    context_refs: JSON.stringify([
      `${planFile}#requirements`,
      `${planFile}#scope`,
      `${planFile}#acceptance-criteria`
    ]),
    // Legacy fallback (path F1) — kept so workflow runs even if state.json absent:
    context_files: `${planFile},.context/errors/software-architector.md`,
    plan_file: planFile,
    workflow_id: workflowId, priority: "medium"
  }
});
```

## Milestone Initialization

When `--milestone:N` is specified:

### 1. Fetch Milestone Issues

```bash
# Get milestone info
gh api repos/:owner/:repo/milestones/{N} --jq '.title'

# Get all open issues
gh issue list --milestone "{title}" --json number,title,labels,body
```

### 2. Filter Issues with Existing PRs

Skip issues that already have linked PRs:

```bash
# Check for linked PRs on each issue
gh api /repos/:owner/:repo/issues/{issue#}/timeline --jq '[.[] | select(.event == "cross-referenced" and .source.issue.pull_request)] | length'
```

If count > 0, mark issue as `skipped_has_pr` and exclude from workflow.

### 3. Sort by Priority

| Priority | Label | Order |
|----------|-------|-------|
| Critical | P0, priority:critical | 1 |
| High | P1, priority:high | 2 |
| Medium | P2, priority:medium | 3 |
| Low | P3, priority:low | 4 |
| None | (unlabeled) | 5 |

### 4. Per-Issue Workspace Setup

For each issue in priority order:

#### Legacy Mode (default)

```bash
# Create isolated workspace
mkdir -p .workspaces/milestone-{N}/{issue#}/.context

# CRITICAL: Create branch from base (using remote to avoid conflicts)
git fetch origin develop  # or base branch from issue body
git checkout -b feature/{issue#}-{slug} origin/develop
```

#### Worktree Mode (`--worktree`)

```bash
# Create worktree with dedicated branch (no checkout switching needed)
git fetch origin develop
git worktree add -b feature/{issue#}-{slug} \
  .worktrees/milestone-{N}/{issue#} origin/develop

# Create .context/ inside worktree
mkdir -p .worktrees/milestone-{N}/{issue#}/.context
```

**Key difference**: No `git checkout` needed. Each worktree has its own branch checked out independently. Multiple issues can run truly in parallel without branch conflicts.

### 5. Initialize Orchestrator

Create orchestrator.json to track all issues.

#### Legacy Mode

Location: `.workspaces/orchestrator.json`

```json
{
  "version": "2.0",
  "milestone_number": 1,
  "milestone_title": "Sprint 2025-W05",
  "parallel_tracks": 2,
  "base_branch": "develop",
  "created_at": "2026-01-31T10:00:00Z",
  "issues": [
    {
      "number": 27,
      "title": "feat: Add watermark support",
      "priority": "P0",
      "status": "pending",
      "track": null,
      "branch": "feature/27-watermark-support",
      "workspace": ".workspaces/milestone-1/27"
    }
  ]
}
```

#### Worktree Mode

Location: `.worktrees/orchestrator.json`

```json
{
  "version": "3.0",
  "milestone_number": 1,
  "milestone_title": "Sprint 2025-W05",
  "parallel_tracks": 3,
  "isolation": "worktree",
  "base_branch": "develop",
  "created_at": "2026-02-23T10:00:00Z",
  "issues": [
    {
      "number": 27,
      "title": "feat: Add watermark support",
      "priority": "P0",
      "status": "pending",
      "track": null,
      "branch": "feature/27-watermark-support",
      "workspace": ".worktrees/milestone-1/27",
      "isolation": "worktree"
    }
  ]
}
```

### 6. Execute Per-Issue Workflow

Each issue runs the full staged workflow independently:

```
Issue #27 → feature/27-watermark → PL→AR→TL→DV→DR→QA→DC→FN→ST → PR → complete
Issue #26 → feature/26-font-family → PL→AR→TL→DV→DR→QA→DC→FN→ST → PR → complete
```

See `shared/milestone-helpers.md` for helper functions.

## Workflow Initialization

Only PL0 is created at startup. PL0 creates all subsequent stage tasks after planning.

```typescript
const workflowId = "dark-mode-2025";

// Create only PL0 — PL agent creates subsequent stages after planning
TaskCreate({
  subject: "PL0: Planning",
  description: "Define requirements, assess complexity, create stage tasks",
  activeForm: "Planning task requirements",
  metadata: { stage: "PL", agent: "igrsoft:product-manager", model: "opus", workflow_id: workflowId, priority: "medium" }
});

// Start immediately
TaskUpdate({ taskId: "1", status: "in_progress", owner: "product-manager" });
```

## Pre-Stage Exploration Cache

Before creating PL0, the orchestrator SHOULD create `.context/exploration.md` when it has
performed codebase exploration. This prevents stage agents from re-reading the same files.

### When to Create

- Orchestrator launched Explore agents before PL0
- User provided Figma URLs or external context
  - When Figma URLs are provided, PL0 captures screenshots to `.context/designs/figma-*.png` and summarizes design context here

> **Note**: Figma screenshot capture applies to ALL workflow triggers including `micro:`.
> For `micro:`, create `.context/designs/` and save screenshots even though no `.context/planning-N.md` is generated.
- Task involves modifying existing code (not greenfield)

### Template

```markdown
# Exploration Cache
<!-- Generated by orchestrator — read by all stage agents -->
<!-- Agents: read this INSTEAD of re-exploring the codebase -->

## File Inventory

| File | Lines | Description |
|------|-------|-------------|
| `Source/Navigation/AppCoordinator.swift` | 510 | Centralized navigation coordinator |
| `Source/Features/Settings/Views/SettingsView.swift` | 198 | Settings ZStack overlay with panel system |

## Key Interfaces

### [Section Name] (e.g., "Settings Panel Pattern")
~~~swift
// Source/Features/Settings/Views/SettingsView.swift:10-27
enum SettingsPanel {
    case grid, profile, editProfile, ...
    var animationSpeed: CGFloat { ... }
}
~~~

### [Section Name] (e.g., "Navigation Routes")
~~~swift
// Source/Navigation/Route.swift:135-157
enum FullScreenRoute: Hashable, Identifiable {
    case tryOnMakeup(lookID: String?)
    ...
}
~~~

## Patterns

- **Settings panel**: `@Binding var activePanel: SettingsPanel` + `SettingsPanelHeader`
- **Full-screen cover**: `FullScreenRoute` enum → `AppCoordinatorView.fullScreenContent(for:)`
- **Flag-based auto-open**: `shouldOpenDevicesOnSettings` pattern in AppCoordinator

## External Context

### Figma Design
- **Figma URL**: [original URL]
- **File Key**: [fileKey] | **Node ID**: [nodeId]
- **Screenshots captured**:
  - `.context/designs/figma-[screen]-[node-id].png` — [description]
- **Design context summary**: [colors, layout, components from get_design_context]

## User Decisions
- [Decision 1]: [choice made]
- [Decision 2]: [choice made]
```

### Size Budget

exploration.md SHOULD be 500-1500 tokens (roughly 50-150 lines).
Include actual code snippets only for interfaces/enums that agents need to match.
For implementation details, use `file:line` references.

## PL Creates Subsequent Tasks

After planning completes, PL0 creates stage tasks based on complexity score. Each task is self-describing with `metadata.agent` specifying the executor and `metadata.model` specifying the model alias. **Capture returned task IDs** to correctly set up dependency chains.

```typescript
// Example: PL0 creates stages for a medium-complexity task
const workflowId = "dark-mode-2025";

// Capture task IDs returned by TaskCreate.
// NOTE: context_files includes error_file per task-system § context_files ↔ error_file coupling.
// If omitted, the orchestrator appends it at delegation time (normalizeMetadata).
const ar0 = TaskCreate({
  subject: "AR0: Architecture",
  description: "Design dark mode architecture with theme switching",
  activeForm: "Architecting solution",
  metadata: {
    stage: "AR", agent: "igrsoft:software-architector", model: "opus",
    error_file: ".context/errors/software-architector.md",
    context_files: `exploration.md,${planFile},.context/errors/software-architector.md`,
    plan_file: planFile,  // e.g. "planning-0.md" — propagated so AR resolves the right plan
    workflow_id: workflowId, priority: "medium"
  }
});

const dv0 = TaskCreate({
  subject: "DV0: Development",
  description: "Implement dark mode theme system and color tokens",
  activeForm: "Implementing code",
  metadata: {
    stage: "DV", agent: "igrsoft:developer", model: "opus",
    error_file: ".context/errors/developer.md",
    context_files: `exploration.md,${planFile},analyzing.md,coordination.md,.context/errors/developer.md`,
    plan_file: planFile,
    workflow_id: workflowId, priority: "medium"
  }
});

const dr0 = TaskCreate({
  subject: "DR0: Developer Review",
  description: "Review code quality, patterns, and platform-specific best practices",
  activeForm: "Reviewing code",
  metadata: {
    stage: "DR", agent: "igrsoft:technical-lead", model: "sonnet",
    error_file: ".context/errors/technical-lead.md",
    context_files: `exploration.md,${planFile},analyzing.md,coordination.md,development.md,.context/errors/technical-lead.md`,
    plan_file: planFile,
    workflow_id: workflowId, priority: "medium"
  }
});

const qa0 = TaskCreate({
  subject: "QA0: QA Testing",
  description: "Test theme switching, contrast ratios, persistence",
  activeForm: "Testing solution",
  metadata: {
    stage: "QA", agent: "igrsoft:qa-engineer", model: "sonnet",
    error_file: ".context/errors/qa-engineer.md",
    context_files: `exploration.md,${planFile},developer-review.md,testing.md,.context/errors/qa-engineer.md`,
    plan_file: planFile,
    workflow_id: workflowId, priority: "medium"
  }
});

// Chain dependencies using captured IDs (PL0 is taskId "1" from initial creation)
TaskUpdate({ taskId: ar0, addBlockedBy: ["1"] });  // AR0 ← PL0
TaskUpdate({ taskId: dv0, addBlockedBy: [ar0] });  // DV0 ← AR0
TaskUpdate({ taskId: dr0, addBlockedBy: [dv0] });  // DR0 ← DV0
TaskUpdate({ taskId: qa0, addBlockedBy: [dr0] });  // QA0 ← DR0

// Mark PL0 completed
TaskUpdate({ taskId: "1", status: "completed" });
```

## Task Execution Pattern

When a task starts, the executor reads `metadata.agent` and spawns the agent. **Convention**: `metadata.agent` MUST be fully-qualified `plugin:agent` form (e.g., `igrsoft:developer`, `apple-developer:ios-developer`). Bare names are accepted by the back-compat shim below but are deprecated and should be replaced.

```typescript
const task = TaskGet({ taskId: currentTaskId });
const agentType = task.metadata.agent;  // e.g., "igrsoft:developer" or "apple-developer:ios-developer"
const model = task.metadata.model;      // e.g., "haiku"

// Back-compat shim: qualified names used as-is. Bare names prepend "igrsoft:" and
// log a deprecation warning — emit qualified form at the call site instead.
const subagentType = agentType.includes(':') ? agentType : `igrsoft:${agentType}`;

// Build context-aware prompt
const explorationExists = fileExists('.context/exploration.md');
const previousArtifacts = getPreviousStageArtifacts(task.metadata.stage);

let prompt = task.description;
if (explorationExists) {
  prompt += `\n\n## Shared Exploration Cache\nRead .context/exploration.md for pre-explored codebase context. Do NOT re-read files listed there unless you need to modify them.\n`;
}
for (const artifact of previousArtifacts) {
  prompt += `\n## Previous Stage: Read .context/${artifact}\n`;
}

Task({
  subagent_type: subagentType,           // qualified `plugin:agent` (bare → "igrsoft:{name}" via back-compat shim)
  model: model,                           // explicit model — do NOT rely on frontmatter inheritance
  prompt: prompt                           // context-enriched instructions
});
```

## Stage Sub-Task Splitting

Two patterns for splitting DV into sub-tasks:

### TL-Initiated Split (Parallel Streams)

TL creates DVN tasks during coordination. All streams run concurrently after TL completes. DR0 waits for all.

```
                  ┌→ DV0 ─┐
PL0 → AR0 → TL0 ─┤→ DV1 ─├→ DR0 → QA0
                  └→ DV2 ─┘
```

```typescript
// TL narrows DV0 scope to primary stream
TaskUpdate({ taskId: dv0_id, description: "Implement theme color tokens (owns: Source/Theme/Colors/)" });

// TL creates parallel streams. All DVN share the same error_file (developer.md)
// with distinct section headers per sub-task (## DV1 Retry N, ## DV2 Retry N).
const dv1 = TaskCreate({
  subject: "DV1: Implement theme switcher",
  description: "Add toggle and persistence (owns: Source/Settings/Theme/)",
  metadata: {
    stage: "DV", agent: "igrsoft:developer", model: "opus",
    error_file: ".context/errors/developer.md",
    context_files: `${planFile},analyzing.md,coordination.md,.context/errors/developer.md`,
    plan_file: planFile,
    workflow_id: workflowId, priority: "medium"
  }
});

const dv2 = TaskCreate({
  subject: "DV2: Implement dark mode assets",
  description: "Create dark variants for all image assets (owns: Assets/Dark/)",
  metadata: {
    stage: "DV", agent: "igrsoft:developer", model: "opus",
    error_file: ".context/errors/developer.md",
    context_files: `${planFile},analyzing.md,coordination.md,.context/errors/developer.md`,
    plan_file: planFile,
    workflow_id: workflowId, priority: "medium"
  }
});

// All DVN blocked by TL0 (not DV0) — enables true parallelism
TaskUpdate({ taskId: dv1, addBlockedBy: [tl0_id] });
TaskUpdate({ taskId: dv2, addBlockedBy: [tl0_id] });

// DR0 must wait for ALL DV tasks
TaskUpdate({ taskId: dr0_id, addBlockedBy: [dv1, dv2] });
```

### DV-Initiated Split (Sequential Sub-tasks)

DV agent splits during its own execution. Sub-tasks are children of DV0 — sequential, not parallel.

```typescript
// Developer splits DV0 into focused sub-tasks.
// Sub-tasks share developer.md — orchestrator auto-appends error_file to context_files.
const dv1 = TaskCreate({
  subject: "DV1: Implement theme color tokens",
  description: "Create semantic color tokens for light/dark themes",
  metadata: {
    stage: "DV", agent: "igrsoft:developer", model: "opus",
    error_file: ".context/errors/developer.md",
    context_files: `${planFile},analyzing.md,.context/errors/developer.md`,
    plan_file: planFile,
    workflow_id: workflowId, priority: "medium"
  }
});

const dv2 = TaskCreate({
  subject: "DV2: Implement theme switcher",
  description: "Add toggle and persistence for theme preference",
  metadata: {
    stage: "DV", agent: "igrsoft:developer", model: "opus",
    error_file: ".context/errors/developer.md",
    context_files: `${planFile},analyzing.md,.context/errors/developer.md`,
    plan_file: planFile,
    workflow_id: workflowId, priority: "medium"
  }
});

// Sequential: DV1 and DV2 blocked by DV0
TaskUpdate({ taskId: dv1, addBlockedBy: [dv0_id] });
TaskUpdate({ taskId: dv2, addBlockedBy: [dv0_id] });
```
