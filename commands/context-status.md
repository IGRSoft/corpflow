---
name: context-status
description: Check context window utilization, analyze token distribution, and trigger compression
argument-hint: ''
allowed-tools: Read, Glob
model: haiku
related:
  - skills/context-compression/SKILL.md
  - skills/cost-optimization/SKILL.md
  - commands/cost-report.md
---

# Context Status

Check context window utilization, analyze token distribution, and trigger
compression when needed. Compression canon — principles, techniques, budgets:
`skills/context-compression/SKILL.md`.

## Usage

```
/context-status [--compress] [--summary-only] [--recommend] [--threshold <percent>] [--dry-run] [--by-source]
```

## Options

| Option | Default | Purpose |
|---|---|---|
| `--compress` | off | Generate compressed context and apply compression |
| `--summary-only` | off | Utilization metrics only (no recommendations) |
| `--recommend` | off | Detailed compression recommendations |
| `--threshold <percent>` | 50% | Warning threshold |
| `--dry-run` | off | Show what compression would do without applying |
| `--by-source` | off | Break down by content source |

## Output Format

### Status Report (Default)

```
## Context Status

### Utilization   (Metric | Value — Current Usage, Window Size, Utilization %, Status)
### Distribution  (Source | Tokens | % — system prompt, conversation history,
                   stage artifacts, current context)
### Stage Artifacts (Stage | Artifact | Tokens — one row per stage reached;
                   `-` artifact and 0 tokens for stages not yet run)
### Recommendations (status line + next threshold with tokens remaining)
```

Window Size is 200,000 tokens, or 1,000,000 on Opus 5, Sonnet 5, and Fable 5.
Artifact names follow `skills/task-folder-organization/SKILL.md` (`planning-N.md`,
`architecture.md`, `development.md`, …).

### Compression Report (`--compress`)

```
## Context Compression Applied

### Before/After   (Metric | Before | After | Reduction — total context,
                    stage artifacts, conversation)
### Compression Actions (numbered ✓ lines: what was compressed, before → after tokens)
### Preserved Context   (see § Preservation Rules)
### New Utilization (Metric | Value — Current Usage, Utilization, Headroom)
```

`--dry-run` renders the same report as a projection and applies nothing.

### Recommendations Report (`--recommend`)

Recommendations are grouped by savings — High (> 1,000 tokens), Medium
(500–1,000), Low (< 500) — most impactful first, each entry:

```
N. **[Source]: [Action]**
   - Current: [tokens / count]
   - After: [projected tokens]
   - Method: [technique from skills/context-compression/SKILL.md]
```

Close with a **Recommended Action** line naming the command to run
(`/context-status --compress`) and the estimated new utilization.

### Source Breakdown (`--by-source`)

Four `Component | Tokens | Compressible` tables — Compressible is `No`, `Yes (to
<target>)`, `Partially`, or `N/A`:

| Group | Rows |
|---|---|
| System Components | System prompt, tool definitions, rules/skills (all `No`) |
| Worktask Components | `planning-N.md`, `architecture.md`, `errors/*.md`, other stage artifacts |
| Conversation | Recent (last 5 turns, `No`) vs older turns |
| Current Operation | Active files (`Partially`), in-flight queries (`No`) |

## Compression Strategies

### Automatic Compression Triggers

| Condition | Action |
|-----------|--------|
| Utilization > 50% | Log warning |
| Utilization > 70% | Recommend compression |
| Utilization > 85% | Auto-compress older context |
| Utilization > 95% | Emergency compression |

### Compression Techniques Applied

Stage summarization (completed artifacts → handoff format), conversation
trimming, code references in place of inline code, prose → bullets, decision
deduplication. Per-technique method and expected reduction:
`skills/context-compression/SKILL.md § Compression Techniques by Content Type`.

### Preservation Rules

Always preserve: current stage requirements · active error context · user-stated
preferences · last 5 conversation turns · in-progress work.

## Examples

```
/context-status                            # utilization + basic recommendations
/context-status --compress                 # apply, then show before/after metrics
/context-status --compress --dry-run       # preview without applying
/context-status --by-source --recommend    # full breakdown + actions
/context-status --summary-only             # metrics only
/context-status --threshold 40%            # warn earlier
```

## Integration

Used at stage transitions (before handoff), when context exceeds threshold,
before error retries, when response quality degrades, and by `workflow-engineer`
for diagnostics.
