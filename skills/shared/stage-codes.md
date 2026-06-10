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
| AR | Architecture | software-architector | fable |
| TL | Team Lead | team-lead | sonnet |
| DV | Development | developer | fable |
| DR | Developer Review | technical-lead | sonnet |
| SR | Security Review | security-reviewer | fable |
| QA | QA Testing | qa-engineer | sonnet |
| DC | Documentation | technical-writer | haiku |
| RE | Release Engineering | release-engineer | haiku |
| FN | Finalization | project-manager | opus |
| ST | Stakeholder | stakeholder | sonnet |
| IR | Incident Response | incident-responder | sonnet |

> DV defaults to `developer` (platform app code). For plugin worktask-infrastructure scope (`skills/worktask/references/*.sh`, the stage state-machine, `hooks/**`), PL0 routes DV to `workflow-engineer` instead — see `agents/product-manager.md` § Dynamic Worktask Sizing → DV0 routing override. This table keeps the single unconditional default; the conditional rule lives there.

## Model Lookup

Orchestrator MUST pass `model` parameter when spawning stage agents:

| Model | Stages |
|-------|--------|
| fable | AR, DV, SR, TC, PE, ET |
| opus | PL, FN |
| sonnet | TL, DR, QA, ST, IR, DS, WE |
| haiku | DC, RE |

## Support Agents (On-Demand)

| Code | Agent | Model | Invoked By |
|------|-------|-------|------------|
| DS | designer | sonnet | PL, AR, DV, QA |
| TC | technical-lead | fable | AR, TL, DV, QA |
| ET | ethics-reviewer | fable | Any stage |
| PE | prompt-engineer | fable | Agent optimization |
| WE | workflow-engineer | sonnet | Worktask troubleshooting |

Support agents don't own worktask stages but can be invoked on-demand via Task tool.

> Model column uses aliases (`fable`, `opus`, `sonnet`, `haiku`). Full model IDs (e.g., `claude-opus-4-8`) are also supported in agent frontmatter. Use aliases for portability across providers. **Fable 5** = `claude-fable-5`, the Mythos-class top reasoning model (v2.1.170+) — the `fable` alias resolves only on CC ≥ 2.1.170 and degrades to the provider default below that. **Opus 4.8** is the prior top Claude model (v2.1.154+); Opus 4.6 and Opus 4.7 remain supported. Auto mode is available for Max subscribers on Opus 4.8 and no longer requires `--enable-auto-mode` (v2.1.111).

> **Default effort is now `high`** for API-key, Bedrock, Vertex, Foundry, Team, and Enterprise plans (v2.1.94). Only Pro plan retains medium default. Agents with explicit `effort:` frontmatter are unaffected.

## Agent Frontmatter Fields (v2.1.78+)

| Field | Type | Version | Purpose |
|-------|------|---------|---------|
| `effort` | `low`/`medium`/`high`/`xhigh`/`max` | 2.1.78 (xhigh added 2.1.111) | Set default effort level for agent |
| `maxTurns` | number | 2.1.78 | Limit agent turn count |
| `disallowedTools` | comma-separated | 2.1.78 | Block specific tools from agent |
| `initialPrompt` | string | 2.1.83 | Auto-submit first turn on agent start |
| `permissionMode` | string | 2.1.119 (honored under `--agent`) | Controls permission flow for built-in agents launched via `--agent <name>` |
| `mcpServers` | YAML map | 2.1.117 (main-thread) | MCP servers loaded for both subagent and main-thread (`--agent`) sessions |
| `hooks` | YAML map | 2.1.116 (main-thread) | Hooks now also fire for main-thread (`--agent`) runs |

> **`--print` mode honors agent frontmatter** (v2.1.119+): `tools:` and `disallowedTools:` are now enforced in `--print`/SDK runs, matching interactive-mode behavior. Plugin agents shipping a least-privilege `tools:` line keep that contract in non-interactive flows.

### Skill/Command Frontmatter (v2.1.80+)

Skills and slash commands can declare `effort` in YAML frontmatter to set effort level when invoked. As of **v2.1.152**, skills AND slash commands (not just agents) can also set `disallowed-tools` in frontmatter to restrict tool access within that skill/command's scope.

### keep-coding-instructions Frontmatter (v2.1.94+)

The `keep-coding-instructions` field in plugin output style frontmatter preserves coding instructions across style changes.

### Skill Name Resolution (v2.1.94+)

Plugin skills use the frontmatter `name` field for invocation instead of directory basename. Ensure all SKILL.md files have accurate `name:` frontmatter. Skills also honor `context` and `agent` frontmatter fields (fixed v2.1.101).

### paths: Frontmatter (v2.1.84+)

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
quick:     PL → DV → DR → QA
```

## Subject Numbering

Task subjects use `[CODE][N]:` format with 0-based index per stage code:

```
PL0: Planning          ← PL is always 0 only (singleton)
AR0: Architecture
DV0: Development       ← agents can split: DV0, DV1, DV2
DR0: Developer Review  ← always present after DV
QA0: QA Testing        ← agents can split: QA0, QA1
```

- N increments sequentially per `TaskCreate` call for the same stage code
- The `stage` metadata field stays unnumbered (`"DV"`, not `"DV0"`)
- `metadata.agent` specifies which agent executes the task
- `metadata.model` specifies the model alias; orchestrator MUST pass this to the Agent tool

## Stage Artifacts

| Code | Artifact |
|------|----------|
| EX | exploration.md |
| PL | planning-N.md (numbered per `agents/product-manager.md § Plan File & Run Index Naming`) |
| AR | analyzing-N.md |
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

N inherits from PL0's `planning-N.md` (see `agents/product-manager.md § Plan File & Run Index Naming`).
