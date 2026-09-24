---
name: cross-plugin-handoff
description: Use when delegating a worktask stage to an external plugin agent (apple-, system-, android-, frontend-, backend-developer, ai-engineer) or integrating a new plugin. Covers dispatch injection, handoff schema, AR consultation and the plugin contract.
---

# Cross-Plugin Handoff Protocol

How corpflow delegates worktask stages to external plugin agents.

- **Normative contract**: `${CLAUDE_SKILL_DIR}/references/plugin-contract.md` — what an integrating plugin satisfies and what corpflow guarantees back. Where it and this file disagree, the contract wins.
- **Per-plugin stage→agent tables and error handling**: `${CLAUDE_SKILL_DIR}/references/plugin-protocols.md`.
- **Plugin-side template**: `${CLAUDE_SKILL_DIR}/templates/CORPFLOW.md`, copied to an integrating plugin's root.
- **Consultant return**: `consultant-return.v1` in `references/consultant-return-v1.md`, checked by `scripts/validate-consultant-return.sh`.
- **Alias routing and project override**: `skills/shared/routing-matrix.md`. To set up a project override, scaffold from `${CLAUDE_SKILL_DIR}/templates/PROJECT-CORPFLOW.md`.

## Implementation gate for external plugin commands

When an external plugin command (`apple-developer:debug`, `apple-developer:review-code`, `debugging-toolkit:smart-debug`, `security-scanning:*`, …) returns fix suggestions, code changes or implementation recommendations, present the analysis and the proposed fix, and wait for the user's explicit approval before any Write, Edit or file-modifying Bash. A request that already asked for the fix ("just fix it", "auto-fix") is that approval.

## Dispatch Injection

A sibling plugin's only corpflow-facing file is `CORPFLOW.md` at its repository root; nothing else in it names corpflow. So every delegation to an external plugin agent opens its prompt with:

```
Read CORPFLOW.md at the root of your plugin and follow it. It is the contract for this worktask.
```

The same prompt carries section `[4b]`, the model discipline block for `task.metadata.model`, copied verbatim from `skills/shared/model-prompting.md` (`handoff-protocol.md#cache-prefix`). The sibling cannot tell which model it was dispatched on, so the delegating stage supplies the block.

## Frontmatter Schema

A cross-plugin agent that takes over a stage uses the full schema in `skills/worktask/references/handoff-protocol.md#frontmatter-schema`. It binds every dev plugin in `skills/shared/compatible-plugins.md` plus the support plugins (`debugging-toolkit:*`, `security-scanning:*`).

- The artifact opens with `---\nhandoff:\n`.
- Per-stage required fields per `handoff-protocol.md § Per-stage required-field matrix` — DV `files_touched`; DR/SR `key_decisions`; PL/AR `key_decisions + next_stage_focus`.
- `state.json` is patched per `handoff-protocol.md#atomic-write`, or not at all — the SubagentStop hook repairs it from the frontmatter.

The annotated DV block and per-stage deltas a sibling follows: `templates/CORPFLOW.md § Handoff frontmatter`. corpflow's own per-stage templates: `skills/shared/stage-contracts.md § Per-Stage Frontmatter Templates`.

### error_file derivation

`.context/errors/<basename>.md`, where basename is the last `:`-separated segment of the agent id (`apple-developer:ios-developer` → `ios-developer.md`). Collision join rule: `skills/shared/state-ledger.md § error_file derivation`; the prefix policy that prevents collisions: `compatible-plugins.md § Naming`.

### Build evidence defaults

Per-plugin `requires_screenshots` defaults and Build Evidence adapters: `compatible-plugins.md § Handoff defaults`. UI platforms default `true` with a capture adapter; non-UI platforms default `false` and supply transcripts, eval/k6/Lighthouse reports and build logs under `.context/logs/` via `cli_fallback_adapter`.

## #relaxed-profile

Deferred: cross-plugin agents use the full schema. If a relaxed profile is ever agreed, its minimum fields (likely `stage + verdict + summary + refs`) and a `profile: relaxed` parser switch are defined here.

## When AR Stage Collaborates with Platform Architects

AR consults; ownership does not transfer. `software-architector` settles system-level architecture (API, backend, infra, data), consults the platform architect, and merges the result into `architecture.md`. Written below for `apple-developer:apple-architector`; for another platform substitute its architect and artifact from `agents/software-architector.md § Architect routing`.

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
7. Write full output to .context/apple-architecture.md
8. Return compressed summary (max 500 tokens)
```

### Return and Merge Protocol

The architect writes `.context/apple-architecture.md` in full and returns a ≤500-token summary; `software-architector` reads the file when merging. `architecture.md` gains `## Swift App Architecture` with `### Pattern` (+ rationale), `### Module Structure`, `### State & Dependency Boundaries`, `### Concurrency Strategy` and `### Navigation Pattern`; its `## Test Architecture` splits into system tests (`software-architector`) and Swift app tests (`apple-architector`).

System constraints override app-level preferences: where the architect's pattern conflicts with the system architecture (e.g. TCA's unidirectional flow vs. required bidirectional API streaming), `software-architector` takes the compatible option and records the trade-off in an ADR.

## When DV Stage Delegates to a Plugin Agent

DV is the one stage whose ownership transfers. The DV row's `metadata.agent` names the owner: a `<plugin>:` id means the sibling owns the row, its `metadata.artifact` and its ledger patches (`templates/CORPFLOW.md § Who owns the artifact`). `workspace_path` and `isolation` are already stamped on the row; the external agent operates only inside `workspace_path`, runs git as `git -C {workspace_path}`, and writes artifacts to `{workspace_path}/.context/`.

Pass compressed summaries, not documents: from `.context/<plan_file>` the feature, user-story count, key acceptance criteria and constraints; from `architecture-N.md` the approach, patterns, key decisions and data model.

### Delegation Prompt Template

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
- Code documentation: follow corpflow:code-comment-standard — non-obvious WHY and contract only

## Expected Output
1. Implementation code
2. Write summary to the DV row's artifact (tasks.<ID>.metadata.artifact)
3. Return compressed handoff for QA stage (max 500 tokens)
```

### Return Protocol

The external agent marks its task completed, writes the artifact its own DV row names (`metadata.artifact`; `skills/worktask/references/handoff-protocol.md § DV fan-out — ledger tasks`), and returns the summary shape in `templates/CORPFLOW.md § What you return` for the next stage.

## Direct Orchestrator Dispatch

The orchestrator loop dispatches `metadata.agent` directly, always in fully-qualified `plugin:agent` form (`corpflow:developer`, `apple-developer:ios-developer`), so the same syntax routes a stage to any installed plugin.

PL0 routes a stage straight to a sibling when the task sits entirely within one plugin's domain and needs no corpflow routing: it seeds the row with the sibling id in `agent` plus every field in `skills/worktask/references/pl0-procedure.md § Downstream propagation`. `error_file` derives from the id when absent, and stage continuity rides on the handoff schema above.

### Skill Name Resolution

Plugin skills are invoked by their frontmatter `name`, not the directory basename — cross-plugin skill references use the `name:` value.

### /reload-plugins

A plugin installed via `/plugin` activates immediately when safe, so `/reload-plugins` is the fallback, not the routine step. In-session pickup does not bypass the version-keyed cache: installed consumers resolve under `~/.claude/plugins/cache/<owner>/<plugin>/<version>/`, so adding or renaming a skill, command or agent still needs a version bump (`skills/shared/plugin-root-resolution.md`).

### MCP Dynamic Server Inheritance

Subagents inherit MCP tools from dynamically-injected servers, so a handoff to an agent relying on MCP tools (e.g. XcodeBuildMCP) needs no explicit MCP grant in its `tools:` list, provided the parent session has the server connected.

## Context Budgets

Inter-stage budgets and the corpflow-side handoff shape: `skills/context-compression/SKILL.md` (§ Stage Budget Table, § Handoff Template). Plugin-side return shape: `templates/CORPFLOW.md § What you return`. Cross-plugin summaries:

| Context Type | Max Tokens |
|--------------|------------|
| Planning summary for external agent | 300 |
| Architecture summary for external agent | 300 |
| Development handoff to external agent | 500 |
| Full stage output (inline reference) | 1000 |

Pass summaries plus `.context/` paths, never whole documents, and stamp each summary with stage and run index so it stays attributable.
