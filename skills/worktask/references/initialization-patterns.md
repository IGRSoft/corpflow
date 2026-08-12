# Worktask Initialization & Setup

## Conventions used in this document

- **`planFile`** — the plan filename PL produced for the current worktask run (`planning-N.md`, e.g. `planning-0.md`, `planning-3.md`). Computed by PL0 per `agents/product-manager.md § Plan File Naming`. Every downstream task carries it as `metadata.plan_file`; the same value is interpolated into `context_files`. Stage agents resolve the plan file from `task.metadata.plan_file` first, then newest `.context/planning-*.md`.
- **handoff-protocol mode** — the preferred metadata mode (per `skills/worktask/references/handoff-protocol.md`): tasks carry `state_file` + `context_refs` (anchor list); `context_files` is the F1 fallback (state.json absent — see `../../worktask/references/handoff-protocol.md#f1-fallback`). Examples below show both forms — use `context_refs` for new code; keep `context_files` as the safety net.

## PL0 state.json Initialization (Phase 1)

PL0 (or `commands/worktask.md` Phase 1) creates `.context/state.json` immediately after `mkdir -p .context/`. This seeds the worktask ledger that every subsequent stage reads and patches. The seed is **re-run aware**: `run_index` (and the matching `plan_file`) is the next free planning index `N` computed from any pre-existing `.context/planning-*.md` (`0` on a fresh `.context/`). `run_index` is a **required** schema field (`handoff-protocol.md#state-json-schema`) — never omit it. The canonical executable snippet lives in `commands/worktask.md` Phase 1 step 3a.

### Seed snippet — next free planning index

```bash
mkdir -p .context/

# Re-run aware: next free planning index (0 on a fresh .context/)
# nullglob: empty glob expands to nothing instead of erroring under zsh
# ("no matches found") or staying literal under bash.
setopt null_glob 2>/dev/null || shopt -s nullglob 2>/dev/null || true
N=0
for f in .context/planning-*.md; do
  [ -e "$f" ] || continue
  i="${f##*planning-}"; i="${i%.md}"
  case "$i" in *[!0-9]*) continue ;; esac
  [ "$i" -ge "$N" ] && N=$((i + 1))
done
```

### plan_file shape boundary

Both shapes appear in this file: the state seed below writes the **path** shape
(`.context/planning-N.md`); every `TaskCreate` snippet further down writes the **basename**
shape (`planning-N.md`). Both are legal and every reader MUST accept either — the rule and
its resolution order are canonical in `handoff-protocol.md § plan_file shape boundary`.

### Seed snippet — atomic write

```bash
# …continued: atomic write of the seeded state.json (same shell session; uses $N)
# See § Seeded workspace_path.
WORKSPACE_PATH=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# Atomic write: temp + fsync + rename
tmp=".context/.state.json.$$.${RANDOM}.tmp"
cat > "$tmp" <<EOF
{
  "version": 1,
  "worktask_id": "${WORKTASK_ID}",
  "plan_file": ".context/planning-${N}.md",
  "platform": "${PLATFORM:-all}",
  "run_index": ${N},
  "metadata": { "workspace_path": "${WORKSPACE_PATH}" },
  "stages": { "PL": { "status": "in_progress" } },
  "facts": {
    "goal": "${GOAL}",
    "files_modified": [],
    "tests_added": [],
    "decisions": [],
    "open_questions": [],
    "verdicts": {},
    "dispatched_agents": []
  },
  "handoffs": {}
}
EOF
sync "$tmp" 2>/dev/null || true
mv -f "$tmp" .context/state.json
```

### Seeded goal

`GOAL` is the task description, JSON-escaped and truncated to 240 chars
(`handoff-protocol.md § facts.goal`). Seed it here rather than leaving it for PL0's state
patch: nothing in the patch path actually writes the field, so a run where PL completes by
any other route left it unset — and `publish-pl-issue.sh` then published a kebab-slug issue
title with an empty Summary (issue #375). PM still refines it; the seed only guarantees it
is never absent. On a `/megatask` per-issue run the issue title is the goal.

### Seeded workspace_path

`metadata.workspace_path` is the absolute root of the tree the worktask owns. It is seeded
here, unconditionally, on every run — a `/megatask` per-issue run overwrites it with the
per-issue worktree path, but no run may leave it unset.

#### Readers that silently no-op without it

Three guards read it and every one *passes silently* when it is empty, so an unstamped ledger
disables all three at once rather than failing loudly:

| Reader | Behaviour when `workspace_path` is unset |
|---|---|
| `commands/worktask.md § Workspace-root cross-check` | compares the orchestrator root against itself → always equal |
| `skills/worktask/scripts/dv-tree-preflight.sh` `resolve_assigned()` | resolves empty → warn, exit 0 (never blocks) |
| `agents/developer.md § Worktree cwd discipline` path-prefix check | gated on "when set" → never runs |

That is not hypothetical: a DV stage once pinned itself to a stale worktree of a *different*
clone, wrote nothing, and passed all three checks. Isolation is not assignment — see
`workspace-modes.md § Sibling-worktree hazard`.

### Post-seed notes

`facts.dispatched_agents: []` is seeded (additive, version:1) so the orchestrator loop appends per-`task_id` dispatch entries in place. The other v1 additive fields (`stages.<CODE>.completed_via`/`last_error`/`worktree`, `facts.capabilities`) are written on demand — never seeded; their absence is meaningful. Schema: `handoff-protocol.md#state-json-schema`.

Subsequent stage agents read `.context/state.json` first; if absent, they fall back to `metadata.context_files` mode (path F1 — see `handoff-protocol.md#f1-fallback`; matrix at `handoff-protocol.md#fallback-paths`).

## Hook Installation

PL0 (or `commands/worktask.md` Phase 1) MUST verify the `state-merge.sh` SubagentStop hook is installed before proceeding. This hook is the Layer 2 safety net — it patches `state.json` from artifact frontmatter when stage agents forget to self-patch (Layer 1) or when the orchestrator's Step 6.5 check is skipped.

### Install snippet

```bash
# Idempotent hook installation — run after state.json seed, before PL0 delegation.
# Source: <plugin-root>/.claude/hooks/state-merge.sh (ships with company-workflow plugin).

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"  # Claude Code substitutes this token when loading this file
# Empty? Substitute <plugin-root>: the dir containing .claude-plugin/plugin.json — two levels
# above this skill's base directory (see skills/shared/plugin-root-resolution.md).
[ -d "$PLUGIN_ROOT" ] || PLUGIN_ROOT="<plugin-root>"
hook_src="$PLUGIN_ROOT/.claude/hooks/state-merge.sh"
hook_dst=".claude/hooks/state-merge.sh"

if [[ ! -x "$hook_dst" ]]; then
  mkdir -p .claude/hooks
  cp "$hook_src" "$hook_dst"
  chmod +x "$hook_dst"
fi
```

### PL0 invariant

Before continuing to TaskCreate, verify:
1. `.context/state.json` exists and is valid JSON
2. `.claude/hooks/state-merge.sh` exists and is executable
3. The plugin's `plugin.json` registers the SubagentStop hook (this is declarative — no project-local action needed)

If hook source is not found (e.g. plugin root unresolved — the fallback line left unsubstituted), log a warning and continue — the plugin.json-registered hook will still fire via the plugin hook system. The project-local copy is a belt-and-suspenders fallback for environments where plugin hooks are not supported.

### Sample TaskCreate using context_refs (handoff-protocol mode)

`planFile` is the **basename** shape — see § plan_file shape boundary.

```typescript
const ar0 = TaskCreate({
  subject: "AR0: Architecture",
  description: "Design dark mode architecture with theme switching",
  activeForm: "Architecting solution",
  metadata: {
    stage: "AR", agent: "company-workflow:software-architector", model: "opus",
    error_file: ".context/errors/software-architector.md",
    state_file: ".context/state.json",
    context_refs: JSON.stringify([
      `${planFile}#requirements`,
      `${planFile}#scope`,
      `${planFile}#acceptance-criteria`
    ]),
    // F1 fallback — kept so the worktask runs even if state.json is absent:
    context_files: `${planFile},.context/errors/software-architector.md`,
    plan_file: planFile,
    worktask_id: worktaskId, priority: "medium"
  }
});
```

## Multi-Issue Initialization → `/megatask`

Single-issue setup is the only initialization this skill owns. **Multi-issue batches across a GitHub
milestone or an explicit issue array are orchestrated by `/megatask`**, not by `/worktask` — including
issue fetching, PR-skip detection, priority + dependency/blocker ordering, orchestrator.json, and
per-issue worktree creation. `/megatask` launches one `/worktask` per ready issue (gates pre-bypassed),
so the per-issue setup above still applies inside each worktree.

See:
- `../../megatask/SKILL.md` — orchestrator pattern, worktree topology, monitoring loop
- `../../megatask/references/dependency-graph.md` — DAG construction, cycle detection, levelled schedule
- `../../megatask/references/schemas.md` — orchestrator.json (v3.1) + workspace.json schemas
- `../../shared/milestone-helpers/SKILL.md` — branch naming, PR detection, worktree helpers

## Worktask Initialization

Only PL0 is created at startup. PL0 creates all subsequent stage tasks after planning.

```typescript
const worktaskId = "dark-mode-2025";

// Create only PL0 — PL agent creates subsequent stages after planning
TaskCreate({
  subject: "PL0: Planning",
  description: "Define requirements, assess complexity, create stage tasks",
  activeForm: "Planning task requirements",
  metadata: { stage: "PL", agent: "company-workflow:product-manager", model: "opus", worktask_id: worktaskId, priority: "medium" }
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

> **Note**: Figma screenshot capture applies to ALL worktasks, including low-complexity runs where PL0 drops stages. For a run with no `.context/planning-N.md`, create `.context/designs/` and save screenshots anyway.
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
```

#### Template (continued)

```markdown
<!-- …continued: patterns, external context, user decisions -->

## Patterns

- **Settings panel**: `@Binding var activePanel: SettingsPanel` + `SettingsPanelHeader`
- **Full-screen cover**: `FullScreenRoute` enum → `AppCoordinatorView.fullScreenContent(for:)`
- **Flag-based auto-open**: `shouldOpenDevicesOnSettings` pattern in AppCoordinator

## External Context

### Figma Design
- **Figma URL**: [original URL]
- **File Key**: [fileKey] | **Node ID**: [nodeId]
- **Screenshots captured**:
  - `.context/designs/figma-[screen]-[state]-[node-id].png` — [description]
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

### Setup — flags

```typescript
// Example: PL0 creates stages for a medium-complexity task
const worktaskId = "dark-mode-2025";
// requires_screenshots: the value PL0 stamped on the plan frontmatter, computed
// by `skills/worktask/scripts/detect-ui-change.sh <plan> --platform <p>`
// (true whenever the change set touches UI; fail-safe true on detector error).
// Read it back from the plan frontmatter and propagate to DV + QA below.
const requiresScreenshots = planMetadata.requires_screenshots; // boolean
```

### AR0 task

AR0 is a tier default at score ≥11, not a mandate — PL0 resolves its inclusion against
`skills/estimation-methodology/SKILL.md § Stage Inclusion Criteria (PL0 authority)` and records
the outcome in `skipped_stages`/`added_stages`. The block below is the AR-included branch; when
AR is excluded, skip this `TaskCreate` entirely and chain DV0 directly off PL0.

#### AR0 TaskCreate

```typescript
// …continued: AR0 creation
// Capture task IDs returned by TaskCreate.
// NOTE: context_files includes error_file per task-system § context_files ↔ error_file coupling.
// If omitted, the orchestrator appends it at delegation time (normalizeMetadata).
const ar0 = TaskCreate({
  subject: "AR0: Architecture",
  description: "Design dark mode architecture with theme switching",
  activeForm: "Architecting solution",
  metadata: {
    stage: "AR", agent: "company-workflow:software-architector", model: "opus",
    error_file: ".context/errors/software-architector.md",
    context_files: `exploration.md,${planFile},.context/errors/software-architector.md`,
    plan_file: planFile,  // e.g. "planning-0.md" — propagated so AR resolves the right plan
    worktask_id: worktaskId, priority: "medium"
  }
});
```

### DV0 task

**context_files seeding rule**: `architecture-${N}.md` appears in DV0's `context_files` if and only
if AR0 was included. When AR is excluded it MUST NOT appear in any downstream `context_files`,
and no `metadata.architecture_ref` is stamped on DV0/DR0/QA0.

#### DV0 TaskCreate

```typescript
// …continued: DV0 creation
const dv0 = TaskCreate({
  subject: "DV0: Development",
  description: "Implement dark mode theme system and color tokens",
  activeForm: "Implementing code",
  metadata: {
    stage: "DV", agent: "company-workflow:developer", model: "opus",
    error_file: ".context/errors/developer.md",
    context_files: `exploration.md,${planFile},architecture.md,coordination.md,.context/errors/developer.md`,
    plan_file: planFile,
    // requires_screenshots is the value PL0 stamped on the plan frontmatter
    // (set by detect-ui-change.sh — see agents/product-manager.md). Propagated
    // here so the capture skill + dv-screenshot-gate fire deterministically.
    requires_screenshots: requiresScreenshots,
    worktask_id: worktaskId, priority: "medium"
  }
});
```

### DR0 task

```typescript
// …continued: DR0 creation
const dr0 = TaskCreate({
  subject: "DR0: Developer Review",
  description: "Review code quality, patterns, and platform-specific best practices",
  activeForm: "Reviewing code",
  metadata: {
    stage: "DR", agent: "company-workflow:technical-lead", model: "sonnet",
    error_file: ".context/errors/technical-lead.md",
    context_files: `exploration.md,${planFile},architecture.md,coordination.md,development.md,.context/errors/technical-lead.md`,
    plan_file: planFile,
    worktask_id: worktaskId, priority: "medium"
  }
});
```

### QA0 task

```typescript
// …continued: QA0 creation
const qa0 = TaskCreate({
  subject: "QA0: QA Testing",
  description: "Test theme switching, contrast ratios, persistence",
  activeForm: "Testing solution",
  metadata: {
    stage: "QA", agent: "company-workflow:qa-engineer", model: "sonnet",
    error_file: ".context/errors/qa-engineer.md",
    context_files: `exploration.md,${planFile},developer-review.md,testing.md,.context/errors/qa-engineer.md`,
    plan_file: planFile,
    // Same flag PL0 stamped on the plan frontmatter — QA's Q1.5 manifest
    // ingestion / advisory-skip reads it (agents/qa-engineer.md).
    requires_screenshots: requiresScreenshots,
    worktask_id: worktaskId, priority: "medium"
  }
});
```

### Dependency chain

```typescript
// …continued: wire dependencies, close PL0
// Chain dependencies using captured IDs (PL0 is taskId "1" from initial creation)
TaskUpdate({ taskId: ar0, addBlockedBy: ["1"] });  // AR0 ← PL0
// DV0's predecessor is whichever of TL0/AR0/PL0 is the last stage actually created:
// TL0 when TL ran, AR0 when AR ran without TL, PL0 when neither did.
TaskUpdate({ taskId: dv0, addBlockedBy: [ar0] });  // DV0 ← AR0 (AR-included branch)
TaskUpdate({ taskId: dr0, addBlockedBy: [dv0] });  // DR0 ← DV0
TaskUpdate({ taskId: qa0, addBlockedBy: [dr0] });  // QA0 ← DR0

// Mark PL0 completed
TaskUpdate({ taskId: "1", status: "completed" });
```

## Task Execution Pattern

When a task starts, the executor reads `metadata.agent` and spawns the agent. **Convention**: `metadata.agent` MUST be fully-qualified `plugin:agent` form (e.g., `company-workflow:developer`, `apple-developer:ios-developer`). Bare names are not accepted.

### Resolve agent & model

```typescript
const task = TaskGet({ taskId: currentTaskId });
const agentType = task.metadata.agent;  // e.g., "company-workflow:developer" or "apple-developer:ios-developer"
const model = task.metadata.model;      // e.g., "haiku"

const subagentType = agentType;  // already fully-qualified `plugin:agent`
```

### Build prompt & dispatch

```typescript
// …continued: same execution flow
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
  subagent_type: subagentType,           // qualified `plugin:agent`
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

#### Narrow scope & DV1 stream

```typescript
// TL narrows DV0 scope to primary stream
TaskUpdate({ taskId: dv0_id, description: "Implement theme color tokens (owns: Source/Theme/Colors/)" });

// TL creates parallel streams. All DVN share the same error_file (developer.md)
// with distinct section headers per sub-task (## DV1 Retry N, ## DV2 Retry N).
const dv1 = TaskCreate({
  subject: "DV1: Implement theme switcher",
  description: "Add toggle and persistence (owns: Source/Settings/Theme/)",
  metadata: {
    stage: "DV", agent: "company-workflow:developer", model: "opus",
    error_file: ".context/errors/developer.md",
    context_files: `${planFile},architecture.md,coordination.md,.context/errors/developer.md`,
    plan_file: planFile,
    worktask_id: worktaskId, priority: "medium"
  }
});
```

#### DV2 stream

```typescript
// …continued: second parallel stream
const dv2 = TaskCreate({
  subject: "DV2: Implement dark mode assets",
  description: "Create dark variants for all image assets (owns: Assets/Dark/)",
  metadata: {
    stage: "DV", agent: "company-workflow:developer", model: "opus",
    error_file: ".context/errors/developer.md",
    context_files: `${planFile},architecture.md,coordination.md,.context/errors/developer.md`,
    plan_file: planFile,
    worktask_id: worktaskId, priority: "medium"
  }
});
```

#### Dependency wiring

```typescript
// …continued: block streams on TL0, DR0 on all streams
// All DVN blocked by TL0 (not DV0) — enables true parallelism
TaskUpdate({ taskId: dv1, addBlockedBy: [tl0_id] });
TaskUpdate({ taskId: dv2, addBlockedBy: [tl0_id] });

// DR0 must wait for ALL DV tasks
TaskUpdate({ taskId: dr0_id, addBlockedBy: [dv1, dv2] });
```

### DV-Initiated Split (Sequential Sub-tasks)

DV agent splits during its own execution. Sub-tasks are children of DV0 — sequential, not parallel.

#### DV1 sub-task

```typescript
// Developer splits DV0 into focused sub-tasks.
// Sub-tasks share developer.md — orchestrator auto-appends error_file to context_files.
const dv1 = TaskCreate({
  subject: "DV1: Implement theme color tokens",
  description: "Create semantic color tokens for light/dark themes",
  metadata: {
    stage: "DV", agent: "company-workflow:developer", model: "opus",
    error_file: ".context/errors/developer.md",
    context_files: `${planFile},architecture.md,.context/errors/developer.md`,
    plan_file: planFile,
    worktask_id: worktaskId, priority: "medium"
  }
});
```

#### DV2 sub-task & sequencing

```typescript
// …continued: second sub-task, then block both on DV0
const dv2 = TaskCreate({
  subject: "DV2: Implement theme switcher",
  description: "Add toggle and persistence for theme preference",
  metadata: {
    stage: "DV", agent: "company-workflow:developer", model: "opus",
    error_file: ".context/errors/developer.md",
    context_files: `${planFile},architecture.md,.context/errors/developer.md`,
    plan_file: planFile,
    worktask_id: worktaskId, priority: "medium"
  }
});

// Sequential: DV1 and DV2 blocked by DV0
TaskUpdate({ taskId: dv1, addBlockedBy: [dv0_id] });
TaskUpdate({ taskId: dv2, addBlockedBy: [dv0_id] });
```
