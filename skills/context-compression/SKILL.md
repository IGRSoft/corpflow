---
name: context-compression
description: Apply for efficient stage transitions and context window management. Techniques for compressing context between agent handoffs while preserving critical information.
---

# Context Compression

Systematic approaches for managing context across agent handoffs, optimizing token usage while preserving decision-critical information.

## State Ledger as Compression Primitive

The worktask state ledger (`.context/state.json`, ≤500 tokens) is the single most effective compression technique, and supersedes ad-hoc summary patterns: every stage reads it as the canonical compressed view of all upstream stages.

- **In the ledger**: stage status, verdict, retry_count, top decisions, open questions, handoff one-liners. NEVER diffs, file contents, or test output (fetch those from disk).
- **In artifacts**: full reasoning, tables, code snippets, evidence. The ledger points; the artifact carries.
- **Eviction order on overflow** (`skills/worktask/references/handoff-protocol.md#state-json-schema`): completed-stage artifact paths once handoff strings capture the essentials → resolved open questions → decisions older than 2 stages back.

PL0 creates it; each stage patches it atomically (`#atomic-write`) on completion. Downstream stages read it FIRST, before any artifact, to decide which anchors to grep.

## Cache-Friendly Prompt Layout

Second-most-effective: prefix-prefix equality with the Anthropic prompt cache turns repeated cross-stage tokens into free cache reads. Binding order (`handoff-protocol.md#cache-prefix`):

```
[1] Plugin/agent contract reminder         ← stable across ALL stages
[2] Worktask header (id, plan, exploration)← stable across ALL stages
[3] Ledger pointer + readiness digest (from ledger-digest.sh) ← evolves per stage
[4] Stage contract excerpt                 ← stable WITHIN stage type
[4b] Model discipline block                ← stable WITHIN stage type
─────── (cache prefix boundary) ───────
[5] task.description                       ← dynamic
[6] retry hints                            ← dynamic
[7] Stage-specific banners (DR/FN/MCP)     ← suffix, dynamic
```

### Prefix stability rules

Each section opens with its `<<<marker>>>` and runs to the next one; the full marker set and why `[3]` needs one are normative in `skills/worktask/references/handoff-protocol.md#cache-prefix`. `[4b]` carries the per-model discipline block from `skills/shared/model-prompting.md`, selected by `task.metadata.model`.

Forbidden in [1][2][4][4b]: timestamps, ENV expansions, random IDs, retry counters, file mtimes, agent-specific names beyond `worktask_id`. `skills/worktask/scripts/cache-lint.sh` asserts byte-stability. CI runs it in `--self-test` mode on every PR (`.github/workflows/test.yml`), which gates the parser and its fixtures; asserting a real captured `prompt-log.jsonl` is still a manual run, because nothing in this repo emits one.

Expected `cache_read_input_tokens`: ≈20% on cross-stage transitions, ≈80% on retries within a stage, ≈60% cross-stage average — meets AC-14 threshold of `≥60%` for stages 2–N.

## Handoff Frontmatter as Canonical Compression Form

Every stage artifact starts with a `---\nhandoff:\n` YAML block (≤200 tokens, ≤30 lines) carrying verdict, top decisions, and refs. Downstream stages grep it (≈70 tokens) instead of the full artifact (2–5k tokens) — >95% compression on the upstream-summary path; the full file is read only for an anchor flagged in `next_stage_focus`. Fields per stage: `skills/worktask/references/handoff-protocol.md#frontmatter-schema`.

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
2. **Summarize decisions, not deliberation** — capture the WHY and WHAT, not the discussion.
3. **Use structured formats** — consistent templates compress better than prose.

Worked before/after pairs (typically 5-10x on each principle), reference formats, and handoff anti-patterns: `references/compression-examples.md`.

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

Filled PL- and AR-stage examples: `references/compression-examples.md`.

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

Per-context summary-block formats: `references/compression-examples.md § Reference Formats`.

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

The extended (1M) inbound figure needs a live 1M window and suits genuinely complex runs only — standard budgets stay preferred for cost, and compression is a best practice at any window size.

#### 1M credit caveats

- **Credit gate**: a 1M session on an account **without 1M usage credits** auto-compacts back under the standard limit, so a nominal 1M window does not guarantee extended budgets — plan against the **standard** column unless credits are confirmed. **Fable 5.x** (Fable 5.1 is the default Fable model) is 1M by default but credit-gated: fable-tier *dispatch* fails outright without credits (`skills/shared/model-selection.md`). **Sonnet 5** is natively 1M under the same account caveat.
- **Opus 5 is the exception**: its 1M window is ungated (default Opus, no plan qualifier), so opus-tier stages on the `opus` alias plan against the extended column unconditionally.

#### Compaction fallback & thinking

- **`--fallback-model`**: compaction honors it, so a credit-gated 1M Fable compaction degrades to the fallback (e.g. `claude-sonnet-5`) instead of failing.
- **Thinking inheritance**: compaction inherits the session's extended-thinking configuration — a high-effort session compacts with its own thinking budget, improving summary fidelity and PostCompact recovery.
- **Auto-compact near 1M**: Opus and Fable 1M sessions auto-compact shortly before the 1M-token limit, and recovery compaction on a very large context does not time out at 10 minutes.

## Exploration Cache Budget

Per-content budgets for `.context/exploration.md` (template and file-level size budget: `skills/worktask/references/initialization-patterns.md § Pre-Stage Exploration Cache`):

| Content Type | Token Budget | Technique |
|-------------|-------------|-----------|
| File inventory | 100-200 | Path + one-line description table |
| Key interfaces | 200-500 | Code snippets for enums/protocols only |
| Patterns | 100-200 | One-liner per pattern with file:line ref |
| External context | 100-300 | Summarized design/Figma/user decisions |
| **Total** | **500-1200** | |

### Anti-Patterns for exploration.md

| Anti-Pattern | Problem | Fix |
|-------------|---------|-----|
| Full file contents | 500-2000 tokens/file | Include only interfaces/enums (< 30 lines) |
| Implementation details | Low reuse across stages | Use file:line references |
| Build commands | Already in CLAUDE.md | Don't duplicate |
| Architecture decisions | Belongs in architecture.md | Only include patterns/facts |

### Budget Enforcement

Over budget, cut in this order:

1. **Evict lowest-priority** — historical context, rejected alternatives, rationale for obvious decisions.
2. **Compress the rest** — inline content → artifact refs; drop obvious decisions; summarize lists >5 items.
3. **Never evict** — current stage requirements, open questions, error context, user-stated preferences.

## Compression Triggers

| Trigger | Action |
|---------|--------|
| Stage handoff | Compress previous stage to budget |
| Context > 50% window | Summarize completed stages |
| Error retry | Trim non-essential context |
| User request | Manual compression |
| Post-compaction | Deferred tool schemas preserved — no re-fetch needed |
| Auto-compact thrash | CC errors out after 3 immediate refills instead of burning API calls |
| Focus mode | Focus view (Ctrl+O) generates self-contained summaries |
| Compaction duplicates | Compaction produces no duplicate transcript entries |
| 1M without credits | Credit-gated 1M session auto-compacts under the standard limit — standing on Fable 5.x, never on Opus 5 |
| Context overflow | `/context` warns past the window; a failed `/compact` errors instead of silently no-op'ing |

## PostCompact Recovery

Compaction is silent — any decision that lived only in the conversation can vanish without a trace. The hooks limit the damage; the behavioral re-anchor covers the rest.

### PreCompact & PostCompact hooks

`PreCompact` fires **before** automatic compaction — return exit code 2 to block it (critical stage work in flight that cannot afford summarization). `PostCompact` fires **after** it completes and drives context recovery.

```json
{
  "hooks": {
    "PreCompact": [
      {
        "hooks": [
          { "type": "command", "command": "./tools/pre-compact-guard.sh" }
        ]
      }
    ],
    "PostCompact": [
      {
        "hooks": [
          { "type": "command", "command": "bash skills/context-compression/scripts/post-compact-recovery.sh" }
        ]
      }
    ]
  }
}
```

Use cases: gate compaction during critical multi-stage handoffs (PreCompact); re-inject task state, log compression metrics, recover worktask context in long sessions (PostCompact).

#### Managed registration

The example above is the project-local form. Installing the plugin already registers both events in `.claude-plugin/plugin.json` — `hooks/precompact-checkpoint.sh` and `scripts/post-compact-recovery.sh` — so no project configuration is required to get the managed behaviour. Registration parity is pinned by `tests/shell/worktask/manifest-parity.bats`.

### `scripts/post-compact-recovery.sh` — canonical implementation

Parses the `audit.jsonl` tail (non-advisory `subagent_stopped` entries only — NOT mtime/ls ordering, which is unreliable) to resolve the interrupted stage, its Task System handle, and its per-agent error file, then writes a compact JSON pointer to `.context/logs/post-compact-<ts>.json`. With the default output directory and no `$CLAUDE_PROJECT_DIR/.context/state.json`, it exits 0 and writes nothing: without a ledger there is no worktask to recover, and creating `.context/logs` would plant a `.context/` in a clean checkout. The selector does not filter on `result`: the last stage that stopped is the interrupted one whatever its outcome. Both default paths are rooted on `$CLAUDE_PROJECT_DIR`, never on the hook's cwd. Only that path is reported, on stderr; the body is never echoed, keeping the hook's token footprint near zero.

#### Invocation

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

The orchestrator's next turn reads the newest `post-compact-*.json`, follows its `resume_guide_ref`, and continues the execution loop from the first incomplete stage. State table and full procedure: `skills/worktask/references/resume.md` (stub: `skills/worktask/SKILL.md § Resume After Interruption`).

### Behavioral re-anchor (not hook-driven)

On any compaction signal — sudden loss of earlier context, an explicit `/compact`, or a `PostCompact` pointer file — before the next action:

1. **Re-read `.context/state.json` and the active stage artifact FIRST.** The file-mediated ledger ([State Ledger as Compression Primitive](#state-ledger-as-compression-primitive)) is the source of truth; post-compaction conversational memory is not.
2. **Recite the active stage's constraints and acceptance criteria** before the next edit, so a requirement dropped by compaction resurfaces instead of being silently skipped.
3. **Trust but verify cached reads.** If a fresh re-read contradicts what you "remember" reading, the recollection is the stale copy — follow the file.

Durable fix, upstream: write decisions into files as they are made, never only into the conversation, so compaction has nothing load-bearing left to drop.

### Session Recap

Claude Code auto-generates a session recap at key moments (also `/recap`, or `--recap` on resume). Recaps are self-contained, survive compaction, and serve as handoff context between worktask sessions — telemetry-disabled users included.

## Context Size Estimation

1 word ≈ 1.3 tokens; 1 line of code ≈ 10 tokens; 1 paragraph ≈ 50-100 tokens; 1 file ≈ 500-2000 tokens. Per-artifact estimates and the pre-handoff compression checklist: `references/compression-examples.md`.
