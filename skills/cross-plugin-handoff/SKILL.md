---
name: cross-plugin-handoff
description: Protocol for handoffs between corpflow worktask and external plugins (apple-developer, system-developer, android-developer, frontend-developer, backend-developer, ai-engineer, security-scanning). Use when delegating work to external plugins.
effort: medium
---

## Orchestrator Implementation Gate (BINDING)

When the orchestrator receives results from ANY external plugin command (apple-developer:debug, apple-developer:review-code, debugging-toolkit:smart-debug, security-scanning:*, etc.) that include fix suggestions, code changes, or implementation recommendations:

1. **PRESENT** the analysis results and proposed fix to the user
2. **DO NOT** call Write, Edit, or any file-modifying Bash command
3. **WAIT** for explicit user approval before implementing any changes

**Exception**: If the user's original request explicitly includes implementation intent (e.g., "fix this and apply the changes", "auto-fix", "just fix it"), the approval gate is satisfied by the original request.

# Cross-Plugin Handoff Protocol

Defines the handoff protocol between corpflow worktask stages and external plugin agents.

> **The normative contract is `${CLAUDE_SKILL_DIR}/references/plugin-contract.md`.** It is the single
> source for what an integrating plugin must satisfy and what corpflow guarantees in return. This
> skill is corpflow's own delegation playbook; where the two disagree, the contract wins.

For plugin-specific protocol tables and error handling, see `${CLAUDE_SKILL_DIR}/references/plugin-protocols.md`

## Dispatch Injection (BINDING)

The plugin-facing seam is **one file per plugin**: `CORPFLOW.md` at that plugin's repository root,
copied from `${CLAUDE_SKILL_DIR}/templates/CORPFLOW.md`. Nothing else in a sibling names corpflow, so
every delegation to an external plugin agent MUST open its prompt with:

```
Read CORPFLOW.md at the root of your plugin and follow it. It is the contract for this worktask.
```

Omit it and the target has no way to learn the stage contract — it carries no corpflow instructions
of its own. This is the one thing corpflow owes every compatible plugin.

## Frontmatter Schema (BINDING for cross-plugin agents)

The canonical schema lives at `skills/worktask/references/handoff-protocol.md` (frontmatter + state.json + cache layout). Cross-plugin agents (e.g. `apple-developer:ios-developer`, `apple-developer:macos-developer`, `system-developer:c-developer`, `system-developer:cpp-developer`, `system-developer:python-developer`, `system-developer:bash-developer`, `android-developer:android-phone-developer`, `android-developer:kotlin-architector`, `frontend-developer:react-developer`, `frontend-developer:fe-test-generator`, `backend-developer:go-developer`, `backend-developer:database-engineer`, `ai-engineer:llm-engineer`, `debugging-toolkit:*`, `security-scanning:*`) MUST adopt the **full schema** when they take over a worktask stage. The registry of compatible plugins and their functional-role agents is `skills/shared/compatible-plugins.md`:

### Required schema elements

- Artifact starts with `---\nhandoff:\n` YAML block per `handoff-protocol.md#frontmatter-schema`.
- Per-stage required fields per `handoff-protocol.md#frontmatter-schema § Per-stage required-field matrix`.
- state.json patched per `handoff-protocol.md#atomic-write` (or omitted — orchestrator's SubagentStop hook will repair).

Copy-paste templates for the 12 stages live in `coordination.md#shared-snippets § Snippet C` (snippets C-1 … C-12). Cross-plugin agents copy the appropriate stage template and substitute placeholders.

### Why full schema (not relaxed subset)

One parser is simpler than two. The required fields per stage are minimal (DV needs `files_touched`; DR/SR need `key_decisions`; PL/AR need `key_decisions + next_stage_focus`). A relaxed subset would require a separate parser path in the orchestrator and harness — not worth the cost.

### Worked example: apple-developer:ios-developer takes over DV

```yaml
---
handoff:
  stage: DV
  verdict: ok
  summary: "Implemented dark-mode token in iOS app. 6 Swift files modified, 4 tests added."
  files_touched:
    - Sources/Theme/ThemeManager.swift
    - Sources/Settings/ThemeToggleViewModel.swift
    - Tests/ThemeManagerTests.swift
  next_stage_focus: "DR reviews ThemeManager DI; QA runs UI snapshot regression"
  refs:
    decisions: architecture.md#decisions
    tests: development.md#tests-added
---
```

#### error_file derivation

The `error_file` for an apple-developer agent is `.context/errors/ios-developer.md` (last segment of qualified name) per `state-ledger.md § error_file derivation`. The same rule applies to every other dev plugin: `.context/errors/c-developer.md`, `.context/errors/kotlin-architector.md`, `.context/errors/react-developer.md`, `.context/errors/be-test-generator.md`, `.context/errors/llm-engineer.md`.

##### Basename collisions

Because the basename is the whole key, two plugins shipping the same bare agent name write to the same error file. `apple-developer` and `android-developer` both ship `security-auditor`, `test-generator`, and `code-fixer` — see `skills/shared/compatible-plugins.md § Naming` before routing both in one worktask.

#### Build evidence defaults

system-developer DV takeovers follow the identical frontmatter shape; note that systems work defaults `metadata.requires_screenshots: false` and supplies Build Evidence (terminal transcripts under `.context/logs/`) via the `cli_fallback_adapter` instead of UI screenshots. android-developer DV takeovers default `metadata.requires_screenshots: true` and supply Build Evidence via the `android_adapter` (`adb exec-out screencap -p`) plus Gradle build/test transcripts under `.context/logs/`; there is no Android build MCP, so builds run through scoped `Bash(gradle:*|./gradlew|adb:*)`.

##### Web, back-end and AI evidence

frontend-developer DV takeovers default `metadata.requires_screenshots: true` via the `web_adapter` (Playwright / Chrome MCP) plus Lighthouse and axe reports. backend-developer and ai-engineer DV takeovers default `false`: back-end evidence is API request/response transcripts, test output, k6 reports, and migration logs; AI evidence is eval reports, metric tables, and training transcripts — all under `.context/logs/`. Full table: `skills/shared/compatible-plugins.md § Handoff defaults`.

## #relaxed-profile

Reserved subsection for a future relaxed-profile schema in case the apple-developer team formally objects to full-schema adoption.

**Status**: deferred. Full schema is mandated by current TL/DV decision (see TL coordination.md#open-questions q6).

If/when relaxed profile is negotiated, this section will define the minimum fields (likely `stage + verdict + summary + refs`) and the parser switch logic (e.g. presence of `profile: relaxed` flag in the frontmatter). Until then, cross-plugin agents follow the full schema above.

## When AR Stage Collaborates with Platform Architectors

Unlike DV stage delegation where task ownership transfers, the AR stage uses a **consultation model** — `software-architector` retains task ownership and merges results.

The protocol below is written against `apple-developer:apple-architector` as the worked example. It applies unchanged to `system-developer:system-architector`, `android-developer:kotlin-architector`, `frontend-developer:frontend-architector`, `backend-developer:backend-architector`, and `ai-engineer:ai-architector`, substituting the agent and its `.context/<platform>-architecture.md` artifact (per-platform table in `agents/software-architector.md § Platform Architecture Collaboration`).

### Collaboration Protocol

1. `software-architector` detects Apple platform context during AR0
2. Completes system-level architecture first (API, backend, infra, data)
3. Delegates Swift app architecture to `apple-developer:apple-architector`
4. Receives compressed summary + reads `.context/swift-architecture.md`
5. Merges into unified `architecture.md`

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
1. Select architecture pattern (MVVM/TCA/MVI/Clean/etc.) with rationale
2. Define module structure and dependency boundaries
3. Define state management and DI strategy
4. Define concurrency strategy (actors, async/await patterns)
5. Define navigation pattern
6. Define Swift test architecture (unit, integration, UI)
7. Write full output to .context/swift-architecture.md
8. Return compressed summary (max 500 tokens)
```

### Return Protocol

`apple-architector` writes `.context/swift-architecture.md` with full detail and returns a compressed summary (max 500 tokens). `software-architector` reads the full file when merging into `architecture.md`.

### architecture.md Merge Template

When Apple platform is detected, `architecture.md` gains these sections:

```markdown
## Swift App Architecture
### Pattern: [MVVM/TCA/MVI/etc.]
**Rationale**: [from apple-architector]
### Module Structure
[file/target structure from apple-architector]
### State & Dependency Boundaries
[DI strategy, state management]
### Concurrency Strategy
[async/await, actors, Sendable patterns]
### Navigation Pattern
[coordinator/NavigationStack approach]
```

The `## Test Architecture` section splits into system tests (from `software-architector`) and Swift app tests (from `apple-architector`).

### Conflict Resolution

System constraints override app-level preferences. If apple-architector's pattern choice conflicts with system architecture (e.g., TCA's unidirectional flow vs. required bidirectional API streaming), `software-architector` documents the trade-off in an ADR and chooses the compatible option.

## When DV Stage Delegates to apple-developer

### 1. Context Preparation

Before delegating, prepare context from worktask artifacts:

```markdown
## Compressed Planning Context (from .context/<plan_file>)
- Feature: {feature_name}
- User stories: {count} stories
- Acceptance criteria: {key_criteria}
- Constraints: {platform, performance, etc.}

## Compressed Architecture Context (from .context/architecture-N.md)
- Approach: {technical_approach}
- Patterns: {architecture_patterns}
- Key decisions: {decisions}
- Data models: {summary}
```

### 2. Task Ownership Transfer

Transfer task to external plugin agent:

```bash
# workspace_path + isolation signal worktree mode to the external agent.
state-patch.sh --task-meta "$TASK_ID" --set '{
  "owner":"apple-developer:ios-developer",
  "workspace_path":".worktrees/milestone-1/42",
  "isolation":"worktree"}'
state-patch.sh --task-status "$TASK_ID" in_progress
```

External agents receiving worktree-isolated tasks should:
1. Read `workspace_path` from task metadata
2. Operate on files inside the worktree path
3. Use `git -C {workspace_path}` for any git commands
4. Write artifacts to `{workspace_path}/.context/`

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

External agent should:
1. Update task status to completed
2. Write to `.context/development-N.md`
3. Return compressed summary for next stage

## Direct Orchestrator Dispatch

The orchestrator loop dispatches `metadata.agent` directly. **Convention**: always emit fully-qualified `plugin:agent` form (e.g., `corpflow:developer`, `apple-developer:ios-developer`). This convention enables PL0 to route stages to any plugin agent — `corpflow:`, `apple-developer:`, or any other installed plugin — using identical syntax at every call site.

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

### When to use direct dispatch

Use direct dispatch when:
- The task is entirely within one external plugin's domain (e.g., pure Swift/Apple work)
- PL0 can determine at planning time that no corpflow routing is needed
- The external agent's handoff format (see below) is used for stage continuity

Every `metadata.agent` value carries its plugin prefix.

### Skill Name Resolution

Plugin skills use the frontmatter `name` field for invocation instead of directory basename. Cross-plugin skill references must use the `name:` value, not the directory path.

### /reload-plugins

`/reload-plugins` picks up new skills without requiring a full restart. Since CC 2.1.221 a plugin installed via `/plugin` activates immediately when safe, so `/reload-plugins` is the fallback rather than the routine step; `/plugin install` also refreshes a stale marketplace catalog and retries before reporting a plugin not found.

> Skills and commands **changed during a session** now appear in the slash menu without a restart, and a plugin skill carrying a frontmatter `name` keeps its plugin prefix in autocomplete. This eases local plugin development, but it does **not** relax the version-keyed cache rule: the installed-marketplace path still resolves under `~/.claude/plugins/cache/<owner>/<plugin>/<version>/`, so renaming or adding a skill/command/agent still requires a version bump for installed consumers (`skills/shared/plugin-root-resolution.md`). Verify against the cache path before relying on in-session pickup.

### MCP Dynamic Server Inheritance

Subagents inherit MCP tools from dynamically-injected servers. Cross-plugin handoffs to external agents that rely on MCP tools (e.g., XcodeBuildMCP) work without explicit MCP tool grants in the subagent's `tools:` list, as long as the parent session has the MCP server connected.

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
- {decision_1}
- {decision_2}

QA_SCENARIOS:
- {scenario_1}: {expected_result}
- {scenario_2}: {expected_result}

EDGE_CASES:
- {edge_case_1}
- {edge_case_2}

KNOWN_ISSUES:
- {any_issues}
```

### qa-engineer Processing

```bash
# qa-engineer receives the handoff.
# Reads development.md, then seeds the QA stage task.
state-patch.sh --task-create QA0 --metadata '{
  "stage":"QA","agent":"corpflow:qa-engineer","model":"sonnet",
  "description":"Verify implementation per development handoff"}'
```

## Context Compression Guidelines

### Token Budgets

See `${CLAUDE_SKILL_DIR}/../context-compression/SKILL.md` for authoritative inter-stage budgets.

For cross-plugin compressed summaries specifically:

| Context Type | Max Tokens |
|--------------|------------|
| Planning summary for external agent | 300 |
| Architecture summary for external agent | 300 |
| Development handoff to external agent | 500 |
| Full stage output (inline reference) | 1000 |

### Compression Template

```
STAGE: {stage_name}
STATUS: {complete|partial|blocked}
DURATION: {time}
TOKEN_USAGE: {tokens}

CRITICAL_ITEMS:
- [P0] {critical_item}
- [P1] {important_item}

KEY_METRICS:
- {metric}: {value}

CONTEXT_FOR_NEXT_STAGE:
- {relevant_context}

FULL_OUTPUT_REF: .context/{stage}.md
```

## Best Practices

1. **Always compress context**: Don't pass full documents between plugins
2. **Reference files**: Use `.context/` paths for detailed data
3. **Update tasks**: Keep task ownership current
4. **Document failures**: Log partial completions clearly
5. **Validate handoffs**: Ensure critical info isn't lost in compression
6. **Version context**: Include timestamp in handoff summaries
