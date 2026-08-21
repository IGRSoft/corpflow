---
name: cross-plugin-handoff
description: Protocol for handoffs between corpflow worktask and external plugins (apple-developer, system-developer, android-developer, frontend-developer, backend-developer, ai-engineer, security-scanning). Use when delegating work to external plugins.
effort: medium
---

## Orchestrator Implementation Gate (BINDING)

When ANY external plugin command (apple-developer:debug, apple-developer:review-code, debugging-toolkit:smart-debug, security-scanning:*, …) returns fix suggestions, code changes, or implementation recommendations:

1. **PRESENT** the analysis and the proposed fix to the user
2. **DO NOT** call Write, Edit, or any file-modifying Bash command
3. **WAIT** for explicit user approval before implementing any change

**Exception**: the original request already carried implementation intent ("just fix it", "auto-fix") — that satisfies the gate.

# Cross-Plugin Handoff Protocol

corpflow's playbook for delegating worktask stages to external plugin agents.

- **Normative contract**: `${CLAUDE_SKILL_DIR}/references/plugin-contract.md` — what an integrating plugin must satisfy and what corpflow guarantees back. Where it and this file disagree, the contract wins.
- **Per-plugin stage→agent tables, error handling, model configuration**: `${CLAUDE_SKILL_DIR}/references/plugin-protocols.md`.
- **Plugin-side template**: `${CLAUDE_SKILL_DIR}/templates/CORPFLOW.md`, copied to an integrating plugin's root.

## Dispatch Injection (BINDING)

The plugin-facing seam is **one file per plugin**: `CORPFLOW.md` at that plugin's repository root. Nothing else in a sibling names corpflow, so every delegation to an external plugin agent MUST open its prompt with:

```
Read CORPFLOW.md at the root of your plugin and follow it. It is the contract for this worktask.
```

Omit it and the target cannot learn the stage contract — it carries no corpflow instructions of its own.

## Frontmatter Schema (BINDING for cross-plugin agents)

Cross-plugin agents MUST adopt the **full** schema when they take over a stage — canonical at `skills/worktask/references/handoff-protocol.md` (frontmatter + state.json + cache layout). It binds every dev plugin in the registry `skills/shared/compatible-plugins.md` plus the support plugins (`debugging-toolkit:*`, `security-scanning:*`).

### Required schema elements

- Artifact starts with `---\nhandoff:\n` per `handoff-protocol.md#frontmatter-schema`.
- Per-stage required fields per `handoff-protocol.md#frontmatter-schema § Per-stage required-field matrix` — DV `files_touched`; DR/SR `key_decisions`; PL/AR `key_decisions + next_stage_focus`.
- state.json patched per `handoff-protocol.md#atomic-write`, or omitted — the SubagentStop hook repairs from the frontmatter.

Copy-paste stage templates: `coordination.md#shared-snippets § Snippet C` (C-1 … C-12). No relaxed subset is offered — one parser is simpler than two and the fields above are already minimal.

### Worked example: apple-developer:ios-developer takes over DV

```yaml
---
handoff:
  stage: DV
  verdict: ok
  summary: "Implemented dark-mode token in iOS app. 6 Swift files modified, 4 tests added."
  files_touched:
    - Sources/Theme/ThemeManager.swift
    - Tests/ThemeManagerTests.swift
  next_stage_focus: "DR reviews ThemeManager DI; QA runs UI snapshot regression"
  refs:
    decisions: architecture.md#decisions
    tests: development.md#tests-added
---
```

#### error_file derivation

`.context/errors/<basename>.md`, where basename is the last `:`-separated segment of the qualified agent name (`apple-developer:ios-developer` → `ios-developer.md`, likewise `c-developer.md`, `kotlin-architector.md`, `react-developer.md`, `be-test-generator.md`, `llm-engineer.md`). Collision join rule: `state-ledger.md § error_file derivation`; the prefix policy that prevents collisions: `skills/shared/compatible-plugins.md § Naming`.

#### Build evidence defaults

Per-plugin `requires_screenshots` defaults and Build Evidence adapters: `skills/shared/compatible-plugins.md § Handoff defaults`. UI platforms default `true` with a capture adapter; non-UI platforms default `false` and supply transcripts, eval/k6/Lighthouse reports and build logs under `.context/logs/` via `cli_fallback_adapter`.

## #relaxed-profile

**Status**: deferred — the full schema is mandated by the current TL/DV decision (TL `coordination.md#open-questions` q6). If a relaxed profile is ever negotiated, this section defines its minimum fields (likely `stage + verdict + summary + refs`) and the parser switch (a `profile: relaxed` flag). Until then: full schema.

## When AR Stage Collaborates with Platform Architectors

AR uses a **consultation model** — unlike DV, ownership does not transfer: `software-architector` keeps the stage and merges the result.

Written below against `apple-developer:apple-architector`; applies unchanged to `system-developer:system-architector`, `android-developer:kotlin-architector`, `frontend-developer:frontend-architector`, `backend-developer:backend-architector`, and `ai-engineer:ai-architector`, substituting the agent and its `.context/<platform>-architecture.md` artifact (per-platform table: `agents/software-architector.md § Platform Architecture Collaboration`).

### Collaboration Protocol

`software-architector` detects platform context during AR0 → completes system-level architecture first (API, backend, infra, data) → delegates app architecture to the platform architect → reads the compressed summary plus `.context/swift-architecture.md` → merges into the unified `architecture.md`.

### Delegation Prompt Template

```
Provide Swift app architecture for the corpflow worktask AR stage:

## Task
{task_description}

## Planning Context (compressed)
{planning_summary from .context/<plan_file> — resolve via `task.metadata.plan_file`; fallback: newest `.context/planning-*.md`}

## System Architecture Constraints
- API patterns: {REST/GraphQL/gRPC decisions}
- Data layer: {persistence decisions}
- Concurrency constraints: {system-level async requirements}

## Expected Output
1. Architecture pattern (MVVM/TCA/MVI/Clean/etc.) with rationale
2. Module structure and dependency boundaries
3. State management and DI strategy
4. Concurrency strategy (actors, async/await patterns)
5. Navigation pattern
6. Swift test architecture (unit, integration, UI)
7. Write full output to .context/swift-architecture.md
8. Return compressed summary (max 500 tokens)
```

### Return and Merge Protocol

`apple-architector` writes `.context/swift-architecture.md` in full and returns a ≤500-token summary; `software-architector` reads the file when merging. On a detected Apple platform `architecture.md` gains `## Swift App Architecture` with `### Pattern` (+ rationale), `### Module Structure`, `### State & Dependency Boundaries`, `### Concurrency Strategy`, and `### Navigation Pattern`; its `## Test Architecture` splits into system tests (`software-architector`) and Swift app tests (`apple-architector`).

### Conflict Resolution

System constraints override app-level preferences. Where the architect's pattern conflicts with system architecture (e.g. TCA's unidirectional flow vs. required bidirectional API streaming), `software-architector` records the trade-off in an ADR and takes the compatible option.

## When DV Stage Delegates to apple-developer

### 1. Context Preparation

Compress the worktask artifacts before delegating:

```markdown
## Compressed Planning Context (from .context/<plan_file>)
- Feature, user-story count, key acceptance criteria, constraints (platform, performance)

## Compressed Architecture Context (from .context/architecture-N.md)
- Technical approach, architecture patterns, key decisions, data-model summary
```

### 2. Task Ownership Transfer

```bash
# workspace_path + isolation signal worktree mode to the external agent.
state-patch.sh --task-meta "$TASK_ID" --set '{
  "owner":"apple-developer:ios-developer",
  "workspace_path":".worktrees/milestone-1/42",
  "isolation":"worktree"}'
state-patch.sh --task-status "$TASK_ID" in_progress
```

An external agent receiving a worktree-isolated task reads `workspace_path` from task metadata, operates on files inside it, runs git as `git -C {workspace_path}`, and writes artifacts to `{workspace_path}/.context/`.

### 3. Delegation Prompt Template

```
Implement the following for the corpflow worktask DV stage:

## Task
{task_description}

## Planning Context (compressed)
{planning_summary}

## Architecture Context (compressed)
{architecture_summary}

## Requirements
- {acceptance_criteria}

## Constraints
- Platform: {platform}
- Architecture decisions: {decisions}
- Code documentation: compact source comments only — non-obvious WHY/contract; function docs 1–3 lines + one-sentence "- Parameter" fields; never the WHAT, design history, Figma/rgba design sources, verification logs, call-site lists, AC-/REQ- IDs, issue-ID provenance, or #Preview comments (skills/shared/code-documentation.md)

## Expected Output
1. Implementation code
2. Write summary to .context/development-N.md
3. Return compressed handoff for QA stage (max 500 tokens)
```

### 4. Return Protocol

The external agent updates task status to completed, writes `.context/development-N.md`, and returns a compressed summary for the next stage.

## Direct Orchestrator Dispatch

The orchestrator loop dispatches `metadata.agent` directly. **Convention**: always emit the fully-qualified `plugin:agent` form (`corpflow:developer`, `apple-developer:ios-developer`) — identical syntax routes a stage to any installed plugin.

Use it when the task sits entirely within one external plugin's domain and PL0 can determine at planning time that no corpflow routing is needed; stage continuity then rides on the handoff schema above.

### Direct dispatch example

```bash
# PL0 seeds a DV stage task routed directly to apple-developer.
# error_file derives from basename (last ':'-separated segment) → ios-developer.md.
# plan_file is the bare basename; state.json holds the path shape
# (handoff-protocol.md § state.json schema).
state-patch.sh --task-create DV0 --metadata "$(jq -n \
  --arg plan "$PLAN_FILE" --argjson ri "$RUN_INDEX" --arg wid "$WORKTASK_ID" \
  '{stage:"DV",
    agent:"apple-developer:ios-developer",
    model:"opus",
    description:"Implement the onboarding flow using SwiftUI NavigationStack",
    error_file:".context/errors/ios-developer.md",
    context_refs:(["\($plan)#requirements","architecture-\($ri).md#decisions"]|tojson),
    plan_file:$plan, worktask_id:$wid}')"
```

### Skill Name Resolution

Plugin skills are invoked by their frontmatter `name`, not the directory basename — cross-plugin skill references must use the `name:` value.

### /reload-plugins

Since CC 2.1.221 a plugin installed via `/plugin` activates immediately when safe, so `/reload-plugins` is the fallback, not the routine step (`/plugin install` also refreshes a stale marketplace catalog and retries before reporting a plugin not found). Skills and commands changed during a session appear in the slash menu without a restart.

> In-session pickup does **not** relax the version-keyed cache rule: the installed-marketplace path resolves under `~/.claude/plugins/cache/<owner>/<plugin>/<version>/`, so renaming or adding a skill/command/agent still needs a version bump for installed consumers (`skills/shared/plugin-root-resolution.md`). Verify against the cache path first.

### MCP Dynamic Server Inheritance

Subagents inherit MCP tools from dynamically-injected servers, so a handoff to an agent relying on MCP tools (e.g. XcodeBuildMCP) needs no explicit MCP grant in its `tools:` list, provided the parent session has the server connected.

## Handoff to QA Stage (QA)

### From apple-developer to qa-engineer

The external agent provides:

```markdown
## Development Handoff (max 500 tokens)

PHASE: DV (Development)
STATUS: complete
AGENT: apple-developer:{agent}

IMPLEMENTATION:
- Feature: {name}
- Files modified: {list}
- Tests added: {list}

KEY_DECISIONS:
- {decision}

QA_SCENARIOS:
- {scenario}: {expected_result}

EDGE_CASES:
- {edge_case}

KNOWN_ISSUES:
- {any_issues}
```

### qa-engineer Processing

```bash
# qa-engineer reads development.md, then seeds the QA stage task.
state-patch.sh --task-create QA0 --metadata '{
  "stage":"QA","agent":"corpflow:qa-engineer","model":"sonnet",
  "description":"Verify implementation per development handoff"}'
```

## Context Compression Guidelines

Inter-stage budgets and the corpflow-side handoff shape: `${CLAUDE_SKILL_DIR}/../context-compression/SKILL.md` (§ Context Budget by Handoff, § Handoff Template). Plugin-side return shape: `templates/CORPFLOW.md § Return summary`. Cross-plugin summaries specifically:

| Context Type | Max Tokens |
|--------------|------------|
| Planning summary for external agent | 300 |
| Architecture summary for external agent | 300 |
| Development handoff to external agent | 500 |
| Full stage output (inline reference) | 1000 |

## Best Practices

Compress rather than paste — summaries plus `.context/` paths, never whole documents. Patch task owner/status at transfer and on return. Log partial completions and what was achieved. Check that compression dropped nothing critical, and stamp each summary with stage + run index so it stays attributable.
