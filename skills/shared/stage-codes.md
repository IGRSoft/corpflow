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

> Who may **execute** tests (vs. build-only) is a separate axis from `test_mode` breadth
> and is canonical in `skills/shared/testing-strategy.md § Test-Execution Authority`. Not
> restated here — this table stays the stage/agent/model reference only.

### DV routing note

> DV defaults to `developer` (platform app code). For plugin worktask-infrastructure scope
> (`skills/worktask/scripts/*.sh`, the stage state-machine, `hooks/**`), PL0 routes DV to
> `workflow-engineer` — see `skills/worktask/references/pl0-procedure.md` § DV0 routing
> override. This table keeps the unconditional default; the conditional rule lives there.

### Side-effect-bearing stages

> Canonical list. These two act **outside** the ledger when they complete, so re-running
> one is not a free retry: it can produce a second commit, PR or tag for one unit of work.
> `state-patch.sh --task-replay --cascade` traverses them but never resets them **as
> dependents**, and mirrors this list as one constant (bash cannot read the table; the bats
> parity test asserts the two agree). A directly named `--task-replay FN0` is still reset,
> with or without `--cascade` — an explicit id is the user's instruction — but warns.

| Code | External side effect on completion |
|------|------------------------------------|
| FN | Commits, pushes, and opens the pull request |
| RE | Tags the release and publishes artifacts |

## Model Lookup

The orchestrator MUST pass `model` when spawning a stage agent. The **Model** column in
§ Primary Stages is that lookup; support agents use § Support Agents below. Deliberately no
third copy — a duplicate table had already drifted from the agents' shipped frontmatter.

## Support Agents (On-Demand)

| Code | Agent | Model | Invoked By |
|------|-------|-------|------------|
| DS | designer | sonnet | PL, AR, DV, QA |
| TC | technical-lead | opus | AR, TL, DV, QA |
| ET | ethics-reviewer | opus | Any stage |
| PE | prompt-engineer | opus | Agent optimization |
| WE | workflow-engineer | sonnet | Worktask troubleshooting |

Support agents own no worktask stage but can be invoked on-demand via the Task tool.

### Handoff Protocol exemption

> Owning no stage artifact means owning no ledger write, so `designer` and
> `prompt-engineer` carry **no** `## Handoff Protocol` / `### State Patch` section — that
> absence is correct, not drift. Three rows are not exempt: `technical-lead` also owns DR
> and `workflow-engineer` takes DV0 under the routing override above, so both carry the
> section; `ethics-reviewer` writes `ethics-review-N.md` and patches state like a stage
> owner. Canonical rule and full exemption list: `commands/create-agent.md § Handoff
> Protocol`.

### Model alias notes

> The Model column uses aliases (`opus`, `sonnet`, `haiku`); full model ids are also valid
> in agent frontmatter, but aliases stay portable across providers. Which model an alias
> resolves to, the Fable 5 credit gate, managed-allowlist resolution, and the default
> effort tier are canonical in `skills/shared/model-selection.md` — agents with explicit
> `effort:` frontmatter are unaffected by the plan default.

## Agent Frontmatter Fields

| Field | Type | Purpose |
|-------|------|---------|
| `effort` | `low`/`medium`/`high`/`xhigh`/`max` | Default effort level for the agent |
| `maxTurns` | number | Limit agent turn count |
| `disallowedTools` | comma-separated | Block specific tools from the agent |
| `initialPrompt` | string | Auto-submit first turn on agent start |
| `permissionMode` | string | Permission flow for built-in agents launched via `--agent <name>` |
| `mcpServers` | YAML map | MCP servers loaded for subagent and main-thread (`--agent`) sessions |
| `hooks` | YAML map | Hooks fire for subagent and main-thread (`--agent`) runs |
| `paths` | YAML list of globs | Path-based activation (e.g. `- "src/**/*.swift"`) |

> **`--print` mode honors agent frontmatter**: `tools:` and `disallowedTools:` are enforced
> in `--print`/SDK runs, matching interactive mode. Plugin agents shipping a least-privilege
> `tools:` line keep that contract in non-interactive flows.

### Skill, command, and output-style frontmatter

- Skills and slash commands may declare `effort` and `disallowed-tools`, scoped to that
  skill/command's invocation.
- Plugin skills invoke by frontmatter `name`, not directory basename — every `SKILL.md`
  needs an accurate `name:`. Skills also honor `context` and `agent`.
- Output styles honor `keep-coding-instructions`, which preserves coding instructions
  across style changes.

## Worktask Pipelines

```
9-stage:   PL → AR → TL → DV → DR → QA → DC → FN → ST
11-stage:  PL → AR → TL → DV → DR → SR → QA → DC → RE → FN → ST
Emergency: IR → DV → DR → QA → RE → FN
```

AR and TL are the optional members: AR is a tier default PL0 may override in either
direction, TL runs only when PL0 splits work across ≥2 developers. See
`skills/estimation-methodology/SKILL.md § Stage Inclusion Criteria (PL0 authority)`.

## Subject Numbering

Task subjects use `[CODE][N]:` format with a 0-based index per stage code — `PL0`, `AR0`,
`DV0`/`DV1`/`DV2` when developers split, `DR0` (always present after DV), `QA0`/`QA1`. PL is
a singleton and is always `PL0`.

- N increments sequentially per seeded task for the same stage code
- The `stage` metadata field stays unnumbered (`"DV"`, not `"DV0"`)
- `metadata.agent` specifies which agent executes the task
- `metadata.model` specifies the model alias; the orchestrator MUST pass it to the Agent tool

## Stage Artifacts

| Code | Artifact |
|------|----------|
| EX | exploration.md |
| PL | planning-N.md |
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

N inherits from PL0's `planning-N.md` — see `skills/worktask/references/pl0-procedure.md`
§ Plan File & Run Index Naming.
