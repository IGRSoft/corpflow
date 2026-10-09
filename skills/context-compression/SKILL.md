---
name: context-compression
description: Use when writing a stage handoff, sizing an artifact against its stage budget, or recovering a worktask after compaction. Per-stage token budgets, handoff frontmatter and template, and per-content compression techniques.
---

# Context Compression

Keep stage handoffs small without dropping decision-critical information.

## State Ledger as Compression Primitive

The worktask ledger (`.context/state.json`, ≤500 tokens) is the canonical compressed view of every upstream stage. PL0 creates it; each stage patches it atomically on completion (`skills/worktask/references/handoff-protocol.md#atomic-write`). Read it before any artifact to pick which anchors to grep.

- **In the ledger**: stage status, verdict, retry_count, top decisions, open questions, handoff one-liners. No diffs, file contents or test output — fetch those from disk.
- **In artifacts**: full reasoning, tables, code snippets, evidence. The ledger points; the artifact carries.
- **Eviction order on overflow** (`handoff-protocol.md#state-json-schema`): completed-stage artifact paths once handoff strings capture the essentials → resolved open questions → decisions older than 2 stages back.

Cross-stage prompt caching is the orchestrator's job: preamble order, stable-prefix rules and `cache-lint.sh` live in `handoff-protocol.md#cache-prefix`.

## Handoff Frontmatter as Canonical Compression Form

Every stage artifact starts with a `---\nhandoff:\n` YAML block (≤200 tokens, ≤30 lines) carrying verdict, top decisions, and refs. Downstream stages grep it (≈70 tokens) instead of the full artifact (2–5k tokens), and read the full file only for an anchor flagged in `next_stage_focus`. Fields per stage: `handoff-protocol.md#frontmatter-schema`.

```yaml
---
handoff:
  stage: DV
  verdict: ok
  summary: "Implemented ThemeManager + binding. 8 files modified, 3 tests added."
  files_touched: [Source/Theme/ThemeManager.swift]
  next_stage_focus: "DR reviews ThemeManager dependency injection"
  refs: { decisions: architecture.md#decisions, tests: development.md#tests-added }
---
```

## Core Principles

1. **Reference, don't duplicate** — point to artifacts instead of including their content.
2. **Summarize decisions, not deliberation** — capture the why and what, not the discussion.
3. **Use structured formats** — consistent templates compress better than prose.
4. **Write handoff lines per `skills/shared/writing-style.md`** — short, active, one term per meaning.

Worked before/after pairs, reference formats, handoff anti-patterns and the pre-handoff checklist: `references/compression-examples.md`.

## Handoff Template

Stage transitions target 50-100 tokens — five sections, one line each unless noted:

```markdown
## Stage [X] Complete
### Decisions Made          - [decision + rationale in <10 words], one bullet each
### Artifacts Created       - `.context/[artifact].md` - [one-line purpose]
### Open Questions for Next Stage - [question requiring input]
### Constraints Identified  - [technical or business constraint]
### Recommended Focus       [one sentence: what the next stage should prioritize]
```

## Compression Techniques by Content Type

| Content type | Compressed form | Reduction |
|--------------|-----------------|-----------|
| Code · full file | `path/to/file.swift` | 95% |
| Code · function | `ClassName.methodName()` signature only | 80% |
| Code · changes | "Changed 15 lines in 3 functions" | 70% |
| Code · structure | Class diagram reference | 85% |
| Planning · user stories | "As [role], I need [goal]" one-liner | 60% |
| Planning · requirements | Numbered checklist | 50% |
| Planning · acceptance criteria | Checkbox list | 40% |
| Planning · risks | "Risk: [name] - Mitigation: [action]" | 70% |
| Architecture · ADR | "ADR-001: [title] - Status: [accepted]" | 80% |
| Architecture · diagram | "See architecture.md#system-diagram" | 90% |
| Architecture · patterns | "Pattern: Repository + Factory" | 85% |
| Architecture · dependencies | "New deps: [lib1], [lib2]" | 75% |

## Stage Budget Table

Every per-stage budget figure lives here; agents and references point to their row. Inbound is the
most any upstream handoff may pass into the stage, standard / extended (1M). Typical tokens is a
whole-stage run measured on sonnet. `—` means no figure is set.

| Stage | Inbound tokens | Artifact lines | Final return tokens | Tool calls | Typical tokens |
|---|---|---|---|---|---|
| PL | — | ≤350 | ≤250 | — | 5,000-10,000 |
| AR | 500 / 2,000 | ≤250 | ≤250 | — | 10,000-20,000 |
| TL | 400 / 1,600 | — | — | — | 3,000-5,000 |
| DV | 400 / 1,600 | ≤250 | ≤250 | ≤80 | 20,000-50,000 |
| DR | 300 / 1,200 | ≤300 | ≤200 | — | — |
| QA | 300 / 1,200 | ≤250 | ≤250 | ≤35 | 10,000-20,000 |
| DC | 200 / 800 | — | — | — | 5,000-10,000 |
| FN | 200 / 800 | ≤200 | ≤200 | — | 3,000-5,000 |
| ST | 150 / 600 | — | — | — | 2,000-3,000 |

Global caps: every artifact's `handoff:` block ≤200 tokens / ≤30 lines; the ledger ≤500 tokens.

### Per-edge focus areas

What each handoff carries into the stage it feeds:

- PL→AR: requirements, constraints, user needs
- AR→TL: architecture decisions, patterns, risks
- PL→TL (no AR): requirements, workstream split, acceptance criteria
- TL→DV: implementation approach, file assignments, deadlines
- AR→DV (no TL): architecture decisions, integration points, schemas
- PL→DV (no AR/TL): requirements, acceptance criteria, constraints
- DV→DR: what changed, code areas, implementation decisions
- DR→QA: review findings, test focus areas, flagged issues
- QA→DC: test results summary, documentation needs
- DC→FN: doc changes, release items, changelog
- FN→ST: executive summary, approval checklist

### Extended Context Budget (1M Window)

Use the extended inbound figure only on a live 1M window for a genuinely complex run; standard budgets cost less.

- **Credit gate**: without 1M usage credits a 1M session auto-compacts back under the standard limit, so plan against the standard column unless credits are confirmed. **Fable 5.x** (default Fable 5.1) is 1M by default but credit-gated: fable-tier dispatch fails without credits (`skills/shared/model-selection.md`). **Sonnet 5.5** is natively 1M; the release notes do not say whether that window is credit-gated, so the standard column applies until credits are confirmed.
- **Opus 5.5 is the exception**: its 1M window is ungated, so opus-tier stages on the `opus` alias always plan against the extended column.
#### Extended Context Budget — fallback and long sessions

- **`--fallback-model`**: compaction honors it, so a credit-gated 1M Fable compaction degrades to the fallback (e.g. `claude-sonnet-5-5`) instead of failing.
- **Long orchestrator sessions**: set `/autocompact 200k` so a 1M session compacts before the window fills (`skills/cost-optimization/references/token-baselines.md § Session commands`).

## Exploration Cache Budget

Per-content budgets for `.context/exploration.md`. The file-level cap and the template live in `skills/worktask/references/initialization-patterns.md § Pre-Stage Exploration Cache`; these rows split that cap:

| Content Type | Token Budget | Technique |
|-------------|-------------|-----------|
| File inventory | 100-200 | Path + one-line description table |
| Key interfaces | 200-500 | Code snippets for enums/protocols only |
| Patterns | 100-200 | One-liner per pattern with file:line ref |
| External context | 100-300 | Summarized design/Figma/user decisions |

Leave out full file contents (only interfaces/enums under 30 lines), implementation details (use file:line refs), build commands (already in CLAUDE.md) and architecture decisions (they belong in architecture.md).

### Budget Enforcement

Over budget, cut in this order:

1. **Evict lowest-priority** — historical context, rejected alternatives, rationale for obvious decisions.
2. **Compress the rest** — inline content → artifact refs; drop obvious decisions; summarize lists >5 items.
3. **Always keep** — current stage requirements, open questions, error context, user-stated preferences.

## Compression Triggers

| Trigger | Action |
|---------|--------|
| Stage handoff | Compress previous stage to budget |
| Context > 50% window | Summarize completed stages |
| Error retry | Trim non-essential context |
| User request | Manual compression |
| Post-compaction | Deferred tool schemas preserved — no re-fetch needed; a folder's CLAUDE.md is not attached a second time after a compaction or resume |
| Write/Edit or a Bash view in a rule's scope | Path-scoped `.claude/rules` and nested CLAUDE.md load on Write and Edit too, and on a single-file Bash `cat`/`head`/`tail`/`sed -n`/`grep` view (2.1.293), not only on Read — count them in the stage budget of every agent with those Bash grants |
| Context too long for the auto-mode classifier | The conversation is compacted instead of every tool call prompting or failing |
| Last few turns are noise | `/rewind`, not `/compact` (`skills/cost-optimization/references/token-baselines.md § Session commands`) |

## Compact Instructions

Compaction follows a "Compact instructions" block in CLAUDE.md when one exists. Copy this one into the project CLAUDE.md so a worktask survives the summary:

```markdown
# Compact instructions

Preserve: the worktask_id, the ledger path (.context/state.json), the current stage and task id,
any open gate, and every pending user decision with its options.
Drop: raw tool output, build and test logs, and file contents that can be re-read.
```

## PostCompact Recovery

Compaction is silent — a decision that lived only in the conversation can vanish without a trace. The hooks limit the damage; the behavioral re-anchor covers the rest.

### PreCompact & PostCompact hooks

The plugin registers both in `.claude-plugin/plugin.json` (parity pinned by `tests/shell/worktask/manifest-parity.bats`), so no project configuration is needed. `PreCompact` runs `hooks/precompact-checkpoint.sh`, which checkpoints the ledger and never blocks; a project hook of its own can block auto-compaction by exiting 2. `PostCompact` runs `scripts/post-compact-recovery.sh`.

### `scripts/post-compact-recovery.sh`

Reads the `audit.jsonl` tail — the last non-advisory `subagent_stopped` entry, whatever its `result`, not mtime ordering — to resolve the interrupted stage, its Task System handle and its error file, and writes a JSON pointer to `.context/logs/post-compact-<ts>.json`. Only that path is reported, on stderr. Default paths are rooted on `$CLAUDE_PROJECT_DIR`; with the default output directory and no ledger it exits 0 and writes nothing.

```
bash skills/context-compression/scripts/post-compact-recovery.sh
# Optional overrides:
#   --audit-file <path>   (default: $CLAUDE_PROJECT_DIR/.context/logs/audit.jsonl)
#   --out-dir    <path>   (default: $CLAUDE_PROJECT_DIR/.context/logs)
#   --tail-lines <N>      (default: 20)
#   --dry-run             print JSON to stdout instead of writing file
#   --self-test           run fixture tests; exit 0 on pass
```

### Post-recovery resume

The orchestrator's next turn reads the newest `post-compact-*.json`, follows its `resume_guide_ref`, and continues the execution loop from the first incomplete stage. State table and full procedure: `skills/worktask/references/resume.md`.

### Behavioral re-anchor (not hook-driven)

On any compaction signal — sudden loss of earlier context, an explicit `/compact`, or a `PostCompact` pointer file — before the next action:

1. Re-read `.context/state.json` and the active stage artifact. The files are the source of truth; where a fresh read contradicts what you remember, follow the file.
2. Before the next edit, restate the active stage's constraints, restating every acceptance-criterion ID listed in the active stage artifact, so a requirement dropped by compaction resurfaces.

Write decisions into files as they are made, so compaction has nothing load-bearing left to drop.

## Context Size Estimation

1 word ≈ 1.3 tokens; 1 line of code ≈ 10 tokens; 1 paragraph ≈ 50-100 tokens; 1 file ≈ 500-2000 tokens. Per-artifact estimates: `references/compression-examples.md § Token Estimation`.
