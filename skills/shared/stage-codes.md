---
name: stage-codes
---

# Stage Codes Reference

Single source of truth for worktask stage codes.

## Agent Model Matrix

Single source of truth for every agent's default model/effort, one row per `agents/*.md`.
§ Primary/Support Stages map a code to its agent; the pair lives only here (removes
`technical-lead`'s DR/TC duplicate). Extracted by `model-matrix-lib.sh`, resolved via
`model_resolve` with `CORPFLOW.md § Models` override. No `Stages` column — see § Model and
Effort Lookup.

| Agent | Model | Effort |
|-------|-------|--------|
| designer | sonnet | medium |
| developer | opus | high |
| ethics-reviewer | opus | xhigh |
| incident-responder | opus | high |
| product-manager | opus | high |
| project-manager | sonnet | medium |
| prompt-engineer | opus | xhigh |
| qa-engineer | sonnet | medium |
| release-engineer | sonnet | low |
| security-reviewer | opus | xhigh |
| software-architector | opus | high |
| stakeholder | sonnet | low |
| team-lead | sonnet | medium |
| technical-lead | opus | high |
| technical-writer | haiku | low |
| workflow-engineer | sonnet | medium |

## Primary Stages (11-Stage)

| Code | Stage | Agent |
|------|-------|-------|
| PL | Planning | product-manager |
| AR | Architecture | software-architector |
| TL | Team Lead | team-lead |
| DV | Development | developer |
| DR | Developer Review | technical-lead |
| SR | Security Review | security-reviewer |
| QA | QA Testing | qa-engineer |
| DC | Documentation | technical-writer |
| RE | Release Engineering | release-engineer |
| FN | Finalization | project-manager |
| ST | Stakeholder | stakeholder |
| IR | Incident Response | incident-responder |

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

## Model and Effort Lookup

The orchestrator MUST pass **both** `model` and `effort` when spawning a stage agent, and stamp
both onto `tasks.<ID>.metadata`. Two-hop join: § Primary/Support Stages resolves a code to its
agent, § Agent Model Matrix resolves that agent to its pair. PL0 performs the join itself via
`model-matrix.sh --resolve <agent>` and pastes the pair into `--task-create`'s `--metadata`
(`sw-AR0-1` reversed the mechanically-enforced auto-fill) — `--task-create` no longer reads
either table for PL0. § Secure overrides replaces a resolved pair under `--secure`/`--full`
**outright** (`sw-AR0-2`, also reversed — a `CORPFLOW.md`-raised pair can be silently lowered).

> `effort` is also stamped because the Step C.0a resolver dispatches one rung above the item
> that raised it (`stage-contracts.md § Blocking items are resolved, not asked`) — only the
> ledger holds the tier that actually ran.

### Secure overrides

> Under `--secure` or `--full`, a row here replaces its stage's resolved model and effort
> (§ Agent Model Matrix, via the stage's agent) **outright** — a pair a project raised
> through `CORPFLOW.md § Models` IS silently lowered back to this row if this row is lower
> (`sw-AR0-2`, reversed at the FN-gate sweep from the raise-only design `dv3` shipped with).
> A stage with no row keeps its resolved pair. PL0 stamps the override through its
> default-writer rows (`skills/worktask/references/pl0-procedure.md § Default writer rules`)
> via a plain `--task-meta` write — no `--raise-only`. DC is here because a secure run's DC
> turns option-gate findings into typed corrections, which takes judgement the default tier
> is not sized for.

| Code | Condition | Model | Effort |
|------|-----------|-------|--------|
| DC | `--secure` / `--full` | sonnet | medium |

## Support Agents (On-Demand)

| Code | Agent | Invoked By |
|------|-------|------------|
| DS | designer | PL, AR, DV, QA |
| TC | technical-lead | AR, TL, DV, QA |
| ET | ethics-reviewer | Any stage |
| PE | prompt-engineer | Agent optimization |
| WE | workflow-engineer | Worktask troubleshooting |

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

> The Model column uses aliases (`opus`, `sonnet`, `haiku`); a full model id would also be
> valid there, but aliases stay portable across providers. No agent file carries its own
> `model:`/`effort:` any more — the matrix row above is the only place either is set. Which
> model an alias resolves to, the Fable 5 credit gate, managed-allowlist resolution, and the
> default effort tier are canonical in `skills/shared/model-selection.md`.

## Agent Frontmatter Fields

| Field | Type | Purpose |
|-------|------|---------|
| `maxTurns` | number | Limit agent turn count |
| `disallowedTools` | comma-separated | Block specific tools from the agent |
| `initialPrompt` | string | Auto-submit first turn on agent start |

### Agent Frontmatter Fields (continued)

| Field | Type | Purpose |
|-------|------|---------|
| `permissionMode` | string | Permission flow for built-in agents launched via `--agent <name>` |
| `mcpServers` | YAML map | MCP servers loaded for subagent and main-thread (`--agent`) sessions |
| `hooks` | YAML map | Hooks fire for subagent and main-thread (`--agent`) runs |
| `paths` | YAML list of globs | Path-based activation (e.g. `- "src/**/*.swift"`) |
| `experimental.cacheTtl` | `"5m"` / `"1h"` | Per-agent prompt-cache TTL, applied only when no subagent TTL setting is configured (`skills/cost-optimization/SKILL.md § Finer-grained TTL controls`) |

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
