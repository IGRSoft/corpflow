---
name: stage-codes
description: Reference table of all workflow stage codes (PL/AR/TL/DV/DR/SR/QA/DC/RE/FN/ST/IR). Use when looking up stage codes, agents, or workflow stage sequences.
---

# Stage Codes Reference

Single source of truth for workflow stage codes.

## Primary Stages (11-Stage)

| Code | Stage | Agent | Model |
|------|-------|-------|-------|
| PL | Planning | product-manager | opus |
| AR | Architecture | software-architector | opus |
| TL | Team Lead | team-lead | sonnet |
| DV | Development | developer | opus |
| DR | Developer Review | technical-lead | sonnet |
| SR | Security Review | security-reviewer | opus |
| QA | QA Testing | qa-engineer | haiku |
| DC | Documentation | technical-writer | haiku |
| RE | Release Engineering | release-engineer | haiku |
| FN | Finalization | project-manager | opus |
| ST | Stakeholder | stakeholder | sonnet |
| IR | Incident Response | incident-responder | sonnet |

## Model Lookup

Orchestrator MUST pass `model` parameter when spawning stage agents:

| Model | Stages |
|-------|--------|
| opus | PL, AR, DV, SR, FN, TC, PE, ET |
| sonnet | TL, DR, ST, IR, DS, WE |
| haiku | QA, DC, RE |

## Support Agents (On-Demand)

| Code | Agent | Model | Invoked By |
|------|-------|-------|------------|
| DS | designer | sonnet | PL, AR, DV, QA |
| TC | technical-lead | opus | AR, TL, DV, QA |
| ET | ethics-reviewer | opus | Any stage |
| PE | prompt-engineer | opus | Agent optimization |
| WE | workflow-engineer | sonnet | Workflow troubleshooting |

Support agents don't own workflow stages but can be invoked on-demand via Task tool.

> Model column uses aliases (`opus`, `sonnet`, `haiku`). Full model IDs (e.g., `claude-opus-4-7`) are also supported in agent frontmatter. Use aliases for portability across providers. **Opus 4.7** is the latest Claude model (v2.1.111+); Opus 4.6 remains supported. Auto mode is available for Max subscribers on Opus 4.7 and no longer requires `--enable-auto-mode` (v2.1.111).

> **Default effort is now `high`** for API-key, Bedrock, Vertex, Foundry, Team, and Enterprise plans (v2.1.94). Only Pro plan retains medium default. Agents with explicit `effort:` frontmatter are unaffected.

## Agent Frontmatter Fields (v2.1.78+)

| Field | Type | Version | Purpose |
|-------|------|---------|---------|
| `effort` | `low`/`medium`/`high`/`xhigh`/`max` | 2.1.78 (xhigh added 2.1.111) | Set default effort level for agent |
| `maxTurns` | number | 2.1.78 | Limit agent turn count |
| `disallowedTools` | comma-separated | 2.1.78 | Block specific tools from agent |
| `initialPrompt` | string | 2.1.83 | Auto-submit first turn on agent start |

### Skill/Command Frontmatter (v2.1.80+)

Skills and slash commands can declare `effort` in YAML frontmatter to set effort level when invoked.

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

## Workflow Pipelines

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
| PL | planning.md |
| AR | analyzing.md |
| TL | coordination.md |
| DV | development.md |
| DR | developer-review.md |
| SR | security-review.md |
| QA | testing.md |
| DC | documentation.md |
| RE | release-prep.md |
| FN | complete.md |
| ST | approval.md |
| IR | incident-report.md |
