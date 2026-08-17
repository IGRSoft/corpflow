---
name: stage-codes
description: Reference table of all worktask stage codes (PL/AR/TL/DV/DR/SR/QA/DC/RE/FN/ST/IR). Use when looking up stage codes, agents, or worktask stage sequences.
---

# Stage Codes Reference

Single source of truth for worktask stage codes.

## Primary Stages (11-Stage)

| Code | Stage | Agent | Model |
|------|-------|-------|-------|
| PL | Planning | product-manager | opus |
| AR | Architecture | software-architector | opus |
| TL | Team Lead | team-lead | sonnet |
| DV | Development | developer | opus |
| DR | Developer Review | technical-lead | opus |
| SR | Security Review | security-reviewer | opus |
| QA | QA Testing | qa-engineer | sonnet |
| DC | Documentation | technical-writer | haiku |
| RE | Release Engineering | release-engineer | haiku |
| FN | Finalization | project-manager | sonnet |
| ST | Stakeholder | stakeholder | sonnet |
| IR | Incident Response | incident-responder | opus |

### Test-execution authority note

> Who may **execute** tests (vs. build-only) is a separate axis from `test_mode` breadth and is
> canonical in `skills/shared/testing-strategy.md § Test-Execution Authority`: DV runs scoped
> tests only, QA is the sole full-suite authority, every other stage code in this table is
> build-only. Not restated here — this table stays the stage/agent/model reference only.

### DV routing note

> DV defaults to `developer` (platform app code). For plugin worktask-infrastructure scope (`skills/worktask/scripts/*.sh`, the stage state-machine, `hooks/**`), PL0 routes DV to `workflow-engineer` instead — see `skills/worktask/references/pl0-procedure.md` § DV0 routing override. This table keeps the single unconditional default; the conditional rule lives there.

### Side-effect-bearing stages

> Canonical list. These two stages act **outside** the ledger when they complete, so re-running
> one is not a free retry: it can produce a second commit, PR or tag for one unit of work.
> `state-patch.sh --task-replay --cascade` therefore traverses through them but never resets
> them **as dependents**, and mirrors this list as one constant (bash cannot read the table; the
> bats parity test asserts the two agree). A directly named `--task-replay FN0` is still reset —
> an explicit id is the user's instruction, and with or without `--cascade` — but warns.

| Code | External side effect on completion |
|------|------------------------------------|
| FN | Commits, pushes, and opens the pull request |
| RE | Tags the release and publishes artifacts |

## Model Lookup

Orchestrator MUST pass `model` parameter when spawning stage agents:

| Model | Stages |
|-------|--------|
| opus | PL, AR, DV, SR, FN, DR |
| sonnet | TL, QA, ST, IR |
| haiku | DC, RE |

Support-agent model assignments live in the Support Agents table below.

## Support Agents (On-Demand)

| Code | Agent | Model | Invoked By |
|------|-------|-------|------------|
| DS | designer | sonnet | PL, AR, DV, QA |
| TC | technical-lead | opus | AR, TL, DV, QA |
| ET | ethics-reviewer | opus | Any stage |
| PE | prompt-engineer | opus | Agent optimization |
| WE | workflow-engineer | sonnet | Worktask troubleshooting |

Support agents don't own worktask stages but can be invoked on-demand via Task tool.

### Handoff Protocol exemption

> Owning no stage artifact means owning no ledger write: `designer` and `prompt-engineer` therefore carry **no** `## Handoff Protocol` / `### State Patch` section, and that absence is correct, not drift. Two rows in this table are not exempt: `technical-lead` also owns DR, and `workflow-engineer` takes DV0 under the routing override above — both carry the section. `ethics-reviewer` is support-only but does write `ethics-review-N.md` (Stage Artifacts below), so it patches state like a stage owner. Canonical rule and the full exemption list: `commands/create-agent.md § Handoff Protocol`.

### Model alias notes

> Model column uses aliases (`opus`, `sonnet`, `haiku`). Full model IDs (e.g., `claude-opus-5`) are also supported in agent frontmatter. Use aliases for portability across providers. **Fable 5** = `claude-fable-5`, the Mythos-class top reasoning model — it ships **1M context by default**, which fails dispatch on accounts without 1M credits (degrade guidance: `skills/shared/model-selection.md`). Under a managed `availableModels` allowlist (applied to subagent overrides; enforced via `enforceAvailableModels`) any alias here may silently resolve to a different model. **Opus 5** = `claude-opus-5`, the current default Opus (1M context, no credit gate) — the `opus` alias resolves here, and `/fast` and auto mode both apply to it (auto mode needs no `--enable-auto-mode` for Max subscribers).

### Default effort

> **Default effort is `high`** for API-key, Bedrock, Vertex, Foundry, Team, and Enterprise plans. Only Pro plan retains medium default. Agents with explicit `effort:` frontmatter are unaffected.

## Agent Frontmatter Fields

| Field | Type | Purpose |
|-------|------|---------|
| `effort` | `low`/`medium`/`high`/`xhigh`/`max` | Set default effort level for agent |
| `maxTurns` | number | Limit agent turn count |
| `disallowedTools` | comma-separated | Block specific tools from agent |
| `initialPrompt` | string | Auto-submit first turn on agent start |
| `permissionMode` | string | Controls permission flow for built-in agents launched via `--agent <name>` |
| `mcpServers` | YAML map | MCP servers loaded for both subagent and main-thread (`--agent`) sessions |
| `hooks` | YAML map | Hooks fire for both subagent and main-thread (`--agent`) runs |

> **`--print` mode honors agent frontmatter**: `tools:` and `disallowedTools:` are enforced in `--print`/SDK runs, matching interactive-mode behavior. Plugin agents shipping a least-privilege `tools:` line keep that contract in non-interactive flows.

### Skill/Command Frontmatter

Skills and slash commands can declare `effort` in YAML frontmatter to set effort level when invoked, and can also set `disallowed-tools` in frontmatter to restrict tool access within that skill/command's scope.

### keep-coding-instructions Frontmatter

The `keep-coding-instructions` field in plugin output style frontmatter preserves coding instructions across style changes.

### Skill Name Resolution

Plugin skills use the frontmatter `name` field for invocation instead of directory basename. Ensure all SKILL.md files have accurate `name:` frontmatter. Skills also honor `context` and `agent` frontmatter fields.

### paths: Frontmatter

The `paths:` field accepts a YAML list of globs for flexible path-based activation:

```yaml
paths:
  - "src/**/*.swift"
  - "Tests/**/*.swift"
```

## Worktask Pipelines

```
9-stage:   PL → AR → TL → DV → DR → QA → DC → FN → ST
11-stage:  PL → AR → TL → DV → DR → SR → QA → DC → RE → FN → ST
Emergency: IR → DV → DR → QA → RE → FN
```

AR and TL are the optional members of these sets: AR is a tier default PL0 may override in
either direction, TL runs only when PL0 splits the work across ≥2 developers. See
`skills/estimation-methodology/SKILL.md § Stage Inclusion Criteria (PL0 authority)`.

## Subject Numbering

Task subjects use `[CODE][N]:` format with 0-based index per stage code:

```
PL0: Planning          ← PL is always 0 only (singleton)
AR0: Architecture
DV0: Development       ← agents can split: DV0, DV1, DV2
DR0: Developer Review  ← always present after DV
QA0: QA Testing        ← agents can split: QA0, QA1
```

- N increments sequentially per seeded task for the same stage code
- The `stage` metadata field stays unnumbered (`"DV"`, not `"DV0"`)
- `metadata.agent` specifies which agent executes the task
- `metadata.model` specifies the model alias; orchestrator MUST pass this to the Agent tool

## Stage Artifacts

| Code | Artifact |
|------|----------|
| EX | exploration.md |
| PL | planning-N.md (numbered per `skills/worktask/references/pl0-procedure.md § Plan File & Run Index Naming`) |
| AR | architecture-N.md |
| TL | coordination-N.md |
| DV | development-N.md |
| DR | developer-review-N.md |
| SR | security-review-N.md |
| QA | testing-N.md |
| DC | documentation-N.md |
| RE | release-N.md |
| FN | complete-summary-N.md |
| ST | retrospective-N.md |
| IR | incident-N.md |
| ET | ethics-review-N.md |

N inherits from PL0's `planning-N.md` (see `skills/worktask/references/pl0-procedure.md § Plan File & Run Index Naming`).
