---
name: context-compression
description: Techniques for compressing context between agent handoffs while preserving critical information. Apply for efficient stage transitions and context window management.
effort: medium
---

# Context Compression

Systematic approaches for managing context across agent handoffs, optimizing token usage while preserving decision-critical information.

## State Ledger as Compression Primitive

The single most effective compression technique is the workflow state ledger (`.context/state.json`, ≤500 tokens). It supersedes most ad-hoc summary patterns: every stage reads the ledger as the canonical compressed view of all upstream stages.

- **What lives in the ledger**: stage status, verdict, retry_count, top decisions, open questions, handoff one-liners. NEVER diffs, file contents, or test output (fetch from disk).
- **What stays in artifacts**: full reasoning, tables, code snippets, evidence. The ledger points; the artifact carries.
- **Eviction order on overflow** (defined in `skills/workflow/references/handoff-protocol.md#state-json-schema`): drop completed-stage artifact paths once handoff strings capture essentials → drop resolved open questions → drop decisions older than 2 stages back.

The ledger is created by PL0 and patched atomically (`#atomic-write`) by every stage on completion. Downstream stages read it FIRST, before any artifact, and use it to decide which anchors to grep.

## Cache-Friendly Prompt Layout

The orchestrator's prompt layout is the second-most-effective compression: prefix-prefix equality with the Anthropic prompt cache turns repeated cross-stage tokens into cache reads (free).

Binding order (per `handoff-protocol.md#cache-prefix`):

```
[1] Plugin/agent contract reminder         ← stable across ALL stages
[2] Workflow header (id, plan, exploration)← stable across ALL stages
[3] state.json blob (inlined JSON)         ← evolves per stage
[4] Stage contract excerpt                 ← stable WITHIN stage type
─────── (cache prefix boundary) ───────
[5] task.description                       ← dynamic
[6] retry hints                            ← dynamic
[7] Stage-specific banners (DR/FN/MCP)     ← suffix, dynamic
```

Forbidden in [1][2][4]: timestamps, ENV expansions, random IDs, retry counters, file mtimes, agent-specific names beyond `workflow_id`. CI lint (`skills/workflow/references/cache-lint.sh`) asserts byte-stability.

Expected `cache_read_input_tokens`: ≈20% on cross-stage transitions, ≈80% on retries within a stage, ≈60% on cross-stage average — meets AC-14 threshold of `≥60%` for stages 2–N.

## Handoff Frontmatter as Canonical Compression Form

Every stage artifact starts with a `---\nhandoff:\n` YAML block (≤200 tokens, ≤30 lines) that summarizes the artifact's verdict, top decisions, and refs. Downstream stages grep this block instead of the full artifact when they only need the verdict, decisions, or refs.

Example (DV stage):

```yaml
---
handoff:
  stage: DV
  verdict: ok
  summary: "Implemented ThemeManager + binding. 8 files modified, 3 tests added."
  files_touched:
    - Source/Theme/ThemeManager.swift
    - Source/Settings/ThemeToggleViewModel.swift
  next_stage_focus: "DR reviews ThemeManager dependency injection"
  refs: { decisions: analyzing.md#decisions, tests: development.md#tests-added }
---
```

DR reads this block (≈70 tokens) instead of the full `development.md` (often 2–5k tokens) — a >95% compression on the upstream-summary path. Full file is read only when DR needs to inspect a specific anchor flagged in `next_stage_focus`.

## Core Principles

### 1. Reference, Don't Duplicate

**Rule**: Point to artifacts instead of including their content.

```
Before (1,200 tokens):
"The authentication implementation includes the following code:
[entire 50-line function pasted here]
which handles JWT validation..."

After (45 tokens):
Auth implementation: `src/auth/jwt.swift:validateToken()`
Key behavior: Validates JWT, returns decoded payload or throws AuthError
```

### 2. Summarize Decisions, Not Deliberation

**Rule**: Capture the WHY and WHAT, not the full discussion.

```
Before (800 tokens):
"After considering several authentication approaches including
session-based auth, API keys, OAuth, and JWT, we analyzed the
tradeoffs of each. Session-based requires server state which
conflicts with our microservice architecture. API keys lack
rotation capabilities. OAuth adds complexity for our use case.
Therefore, we selected JWT because..."

After (120 tokens):
## Auth Decision: JWT
**Selected**: JWT tokens
**Rejected**: Sessions (stateful), API keys (no rotation), OAuth (overkill)
**Rationale**: Stateless, rotatable, fits microservice architecture
**ADR**: .context/analyzing.md#adr-001
```

### 3. Use Structured Formats

**Rule**: Consistent templates compress better than prose.

```
Before (400 tokens): Free-form paragraph about requirements
After (150 tokens): Bulleted acceptance criteria checklist
```

## Handoff Template

Standard format for stage transitions (target: 50-100 tokens):

```markdown
## Stage [X] Complete

### Decisions Made
- [Key decision 1 with rationale in <10 words]
- [Key decision 2]

### Artifacts Created
- `.context/[artifact].md` - [one-line purpose]

### Open Questions for Next Stage
- [Question requiring input]

### Constraints Identified
- [Technical or business constraint]

### Recommended Focus
[One sentence: what the next stage should prioritize]
```

### Example Handoff: PL→AR

```markdown
## Stage PL Complete

### Decisions Made
- Feature scope: Dark mode for settings screen only (MVP)
- Priority: P1 - user-requested, affects 40% of users

### Artifacts Created
- `.context/<plan_file>` (e.g. `planning-0.md`) - Requirements and acceptance criteria

### Open Questions for A Stage
- Should dark mode respect system preference or be independent toggle?

### Constraints Identified
- Must support iOS 15+ (no newer APIs)
- Cannot change existing color constants (breaking change)

### Recommended Focus
Design color abstraction layer that supports both themes without breaking existing UI.
```

## Compression Techniques by Content Type

### For Code Context

| Content Type | Before | After | Reduction |
|--------------|--------|-------|-----------|
| Full file | Paste entire file | `path/to/file.swift` | 95% |
| Function | Paste function body | `ClassName.methodName()` signature only | 80% |
| Changes | Full diff | "Changed 15 lines in 3 functions" | 70% |
| Structure | Describe all classes | Class diagram reference | 85% |

**Code Reference Format**:
```
File: src/auth/AuthManager.swift
Functions modified: validateToken(), refreshToken()
Lines changed: 45 additions, 12 deletions
Key change: Added token expiry validation
Tests: AuthManagerTests.swift (3 new cases)
```

### For Planning Context

| Content Type | Before | After | Reduction |
|--------------|--------|-------|-----------|
| User stories | Full Gherkin format | "As [role], I need [goal]" one-liner | 60% |
| Requirements | Paragraphs | Numbered checklist | 50% |
| Acceptance criteria | Prose | Checkbox list | 40% |
| Risks | Full analysis | "Risk: [name] - Mitigation: [action]" | 70% |

**Planning Reference Format**:
```
## Requirements Summary
- REQ-1: User can toggle dark mode in settings
- REQ-2: Theme persists across app restarts
- REQ-3: Respects system appearance preference (configurable)

Acceptance: 5 criteria in <plan_file>#acceptance
Risks: 2 identified (compatibility, migration) - see <plan_file>#risks
```

### For Architecture Context

| Content Type | Before | After | Reduction |
|--------------|--------|-------|-----------|
| ADR | Full document | "ADR-001: [title] - Status: [accepted]" | 80% |
| Diagram | ASCII/Mermaid inline | "See analyzing.md#system-diagram" | 90% |
| Patterns | Full explanation | "Pattern: Repository + Factory" | 85% |
| Dependencies | Full analysis | "New deps: [lib1], [lib2]" | 75% |

**Architecture Reference Format**:
```
## Architecture Summary
Pattern: MVVM with Coordinator
Key components: ThemeManager (new), ColorPalette (modified)
Dependencies: None added
ADRs: ADR-001 (theme abstraction) - ACCEPTED

Details: .context/analyzing.md
```

## Context Budget by Handoff

Maximum tokens to pass between stages:

| Handoff | Max Tokens | Focus Areas |
|---------|------------|-------------|
| **PL→AR** | 500 | Requirements, constraints, user needs |
| **AR→TL** | 300 | Architecture decisions, patterns, risks |
| **TL→DV** | 400 | Implementation approach, file assignments, deadlines |
| **DV→DR** | 300 | What changed, code areas, implementation decisions |
| **DR→QA** | 300 | Review findings, test focus areas, flagged issues |
| **QA→DC** | 200 | Test results summary, documentation needs |
| **DC→FN** | 200 | Doc changes, release items, changelog |
| **FN→ST** | 150 | Executive summary, approval checklist |

### Extended Context Budget (1M Window)

When running on Opus 4.6/4.7 with Max/Team/Enterprise plans, the context window is 1M tokens. Handoff budgets scale proportionally:

| Handoff | Standard Budget | Extended Budget (1M) |
|---------|----------------|---------------------|
| **PL→AR** | 500 | 2,000 |
| **AR→TL** | 300 | 1,200 |
| **TL→DV** | 400 | 1,600 |
| **DV→DR** | 300 | 1,200 |
| **DR→QA** | 300 | 1,200 |
| **QA→DC** | 200 | 800 |
| **DC→FN** | 200 | 800 |
| **FN→ST** | 150 | 600 |

> Use extended budgets only when complexity warrants it — standard budgets are still preferred for cost efficiency. Compression remains a best practice regardless of window size.

## Exploration Cache Budget

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
| Architecture decisions | Belongs in analyzing.md | Only include patterns/facts |

### Budget Enforcement

When context exceeds budget:

1. **Identify lowest-priority content**
   - Historical context (why we're here)
   - Alternative approaches considered
   - Detailed rationale for obvious decisions

2. **Apply aggressive compression**
   - Replace inline content with artifact references
   - Remove "obvious" decisions (keep non-obvious ones)
   - Summarize lists longer than 5 items

3. **Preserve critical context**
   - Current stage requirements
   - Open questions
   - Error context (if any)
   - User-stated preferences

## Compression Triggers

### Automatic Compression Points

| Trigger | Action |
|---------|--------|
| Stage handoff | Compress previous stage to budget |
| Context > 50% window | Summarize completed stages |
| Error retry | Trim non-essential context |
| User request | Manual compression |
| Post-compaction | Deferred tool schemas preserved — no need to re-fetch after compaction |
| Auto-compact thrash | v2.1.89 detects when context refills immediately after compaction 3 times and stops with actionable error instead of burning API calls |
| Focus mode | Focus view (Ctrl+O) generates self-contained summaries; v2.1.101 improves completeness |
| Compaction duplicates | Compaction no longer produces duplicate transcript entries (fixed v2.1.97) |

### PreCompact & PostCompact Hooks

The `PreCompact` hook (v2.1.105+) fires **before** automatic context compaction begins. Return exit code 2 to block compaction (useful when critical stage work is in-flight and cannot afford summarization). The `PostCompact` hook (v2.1.76+) fires **after** compaction completes and is used for context recovery.

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
          { "type": "command", "command": "./tools/post-compact-recovery.sh" }
        ]
      }
    ]
  }
}
```

Use cases: gate compaction during critical multi-stage handoffs (PreCompact), re-inject critical task state, log compression metrics, recover workflow context in long multi-stage sessions (PostCompact).

#### Example: `tools/post-compact-recovery.sh`

Minimal recovery script that re-injects the audit tail, the in-progress task
ID, and a pointer to `stage-contracts.md` so the orchestrator can resume.

```bash
#!/usr/bin/env bash
# PostCompact recovery: emit a JSON blob that the orchestrator can read on
# first turn after compaction. Written to .context/logs/post-compact-<ts>.json.

set -euo pipefail
mkdir -p .context/logs
TS=$(date -u +%Y%m%d-%H%M%S)
OUT=".context/logs/post-compact-${TS}.json"

# 1. Audit tail — last 20 lines are enough to reconstruct stage transitions
AUDIT_TAIL=$(tail -n 20 .context/logs/audit.jsonl 2>/dev/null | jq -sc '.' || echo '[]')

# 2. In-progress task (if any)
# NOTE: mtime ordering of error files is unreliable — file timestamps do not
# correlate with task state. Correct approach: query the Task System via
# TaskList for status=in_progress, or parse the tail of audit.jsonl to find
# the most recent `subagent_stopped` entry without a matching `completed`.
# Then derive the owning agent/stage and read `.context/errors/<agent>.md`.
# The line below is a best-effort fallback for reference only.
IN_PROGRESS=$(ls -t .context/errors/*.md 2>/dev/null | head -n 1 || echo "")

# 3. Emit recovery blob
jq -n \
  --argjson audit "$AUDIT_TAIL" \
  --arg active_error "$IN_PROGRESS" \
  --arg contracts "skills/shared/stage-contracts.md" \
  --arg resume_guide "skills/workflow/SKILL.md#resume-after-interruption" \
  '{
    recovery: {
      audit_tail: $audit,
      active_error_file: $active_error,
      stage_contracts_ref: $contracts,
      resume_guide_ref: $resume_guide,
      instruction: "Read active_error_file and audit_tail, then resume per resume_guide_ref. Do NOT replay completed stages."
    }
  }' > "$OUT"

echo "PostCompact recovery written to $OUT" >&2
```

After compaction, the orchestrator's next turn reads the most recent
`post-compact-*.json`, follows the `resume_guide_ref`, and continues the
execution loop from the first incomplete stage.

See `skills/workflow/SKILL.md § Resume After Interruption` for the full state
table and procedure.

### Session Recap (v2.1.108+)

Claude Code auto-generates a session recap at key moments (also available via `/recap` or `--recap` on resume). Recaps are self-contained summaries that survive compaction and can be used as handoff context between workflow sessions. Telemetry-disabled users also receive recaps (fixed v2.1.110).

### Context Size Estimation

Rough token counts:
- 1 word ≈ 1.3 tokens
- 1 line of code ≈ 10 tokens
- 1 paragraph ≈ 50-100 tokens
- 1 file ≈ 500-2000 tokens

See references/ for detailed before/after compression examples, anti-patterns, and quick reference card.
