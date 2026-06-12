# Handoff Protocol — Inter-Stage Communication Reference

Canonical specification for worktask inter-stage communication. Defines the `state.json` ledger, the YAML `handoff:` frontmatter contract, the cache-friendly preamble layout, and four documented backward-compat fallback paths.

This file is the single source of truth referenced by:

- `skills/shared/stage-contracts.md` — Required Inputs / Required Outputs vocabulary
- `skills/shared/task-system.md` — `metadata.context_refs` + `metadata.state_file` semantics
- `skills/worktask/SKILL.md` — Orchestrator Execution Loop reads ledger + builds preamble
- `skills/worktask/references/initialization-patterns.md` — PL0 seeds state.json
- `skills/context-compression/SKILL.md` — frontmatter as canonical compression form
- `skills/cross-plugin-handoff/SKILL.md` — cross-plugin agents adopt full schema
- `skills/cost-optimization/SKILL.md` — `ENABLE_PROMPT_CACHING_1H` + hook
- `agents/{product-manager,software-architector,team-lead,developer,technical-lead,security-reviewer,qa-engineer,technical-writer,release-engineer,project-manager,stakeholder,incident-responder}.md` — Required Inputs / Completion Verification
- `commands/worktask.md` — Phase 1 ledger seed

---

## #atomic-write

Atomic state.json write: read → merge → temp → fsync → rename. POSIX-shell pseudocode:

```bash
# 1. Read current state (last-known-good)
cur=$(cat .context/state.json)

# 2. Merge in-memory (jq * patch is idempotent on identical patches)
new=$(echo "$cur" | jq --argjson patch "$PATCH_JSON" '. * $patch')

# 3. Write to temp file in same directory (same filesystem → atomic rename guaranteed)
tmp=".context/.state.json.$$.${RANDOM}.tmp"
printf '%s' "$new" > "$tmp"

# 4. fsync the temp file (best-effort)
sync "$tmp" 2>/dev/null || sync || true

# 5. Atomic rename — POSIX guarantees same-FS rename is atomic
mv -f "$tmp" .context/state.json
```

Failure semantics:

- Crash before step 3 — state.json untouched (last-known-good preserved).
- Crash between 3 and 5 — temp file orphaned in `.context/`. Cleanup on next worktask start: `rm -f .context/.state.json.*.tmp`. state.json untouched.
- Crash after 5 — state.json contains new value. Idempotent (re-running merge with same patch is a no-op).

Single-writer invariant: at any moment exactly one stage agent is `in_progress`. No `flock` required.

`$RANDOM` suffix on the temp filename guards against hypothetical PID reuse inside Task subagents (CR-7).

---

## #frontmatter-schema

Every stage artifact (planning-N.md, analyzing-N.md, coordination-N.md, development-N.md, …) MUST start with a YAML block between `^---$` markers. Token budget ≤200. Line budget ≤30.

JSON-Schema-style spec:

```yaml
$schema: https://json-schema.org/draft/2020-12/schema
title: HandoffFrontmatter
type: object
required: [handoff]
properties:
  handoff:
    type: object
    required: [stage, verdict, summary, refs]
    properties:
      stage:
        type: string
        enum: [PL, AR, TL, DV, DR, SR, QA, DC, RE, FN, ST, IR, ET]
      verdict:
        type: string
        enum: [ok, blocked, escalate, pass, fail, go, no-go, approve, reject]
      summary:
        type: string
        maxLength: 200
      key_decisions:
        type: array
        maxItems: 8
        items:
          type: object
          required: [id, summary, anchor]
          properties:
            id: { type: string, pattern: '^[a-z]{1,3}[0-9]+$' }
            summary: { type: string, maxLength: 160 }
            anchor: { type: string, pattern: '^[a-z0-9.\-/]+\.md#[a-z0-9\-]+$' }
      files_touched:
        type: array
        items: { type: string }
      next_stage_focus:
        type: string
        maxLength: 240
      open_questions:
        type: array
        items:
          oneOf:
            - type: string
            - type: object
              required: [id, summary]
              properties:
                id: { type: string }
                summary: { type: string }
                stage: { type: string }
      refs:
        type: object
        additionalProperties: { type: string }
constraints:
  total_lines: { max: 30 }
  total_tokens: { max: 200, tokenizer: cl100k_base-proxy }
```

### Per-stage required-field matrix

| Stage | Required (beyond base 4) | Optional | Verdict vocabulary |
|-------|--------------------------|----------|--------------------|
| PL | next_stage_focus, key_decisions | files_touched, open_questions | ok / blocked / escalate |
| AR | key_decisions, next_stage_focus, open_questions | files_touched | ok / blocked / escalate |
| TL | next_stage_focus | key_decisions, files_touched | ok / blocked / escalate |
| DV | files_touched, next_stage_focus | key_decisions, open_questions | ok / blocked / escalate |
| DR | key_decisions (= findings) | files_touched, open_questions | pass / fail |
| SR | key_decisions (= findings) | files_touched | pass / fail |
| QA | files_touched (= tests added), key_decisions (= results) | open_questions | go / no-go |
| DC | files_touched | key_decisions | ok / blocked / escalate |
| RE | files_touched, key_decisions (= version) | open_questions | ok / blocked |
| FN | next_stage_focus, files_touched | key_decisions | ok / blocked |
| ST | key_decisions (= rationale) | open_questions | approve / reject |
| IR | key_decisions (= root cause), next_stage_focus | files_touched | ok / escalate |
| ET | key_decisions (= ethics findings) | open_questions | pass / fail |

### Token budget

Frontmatter is the canonical compression form: every downstream stage reads this block instead of the full upstream artifact when it only needs the verdict, decisions, or refs. Keep ≤200 tokens or downstream stages incur unnecessary cost.

---

## #state-json-schema

`.context/state.json` is the worktask ledger. Created by PL0; patched by every stage on completion; read by orchestrator before each delegation; embedded in the preamble as section [3]. Token budget ≤500.

JSON-Schema-style spec:

```yaml
$schema: https://json-schema.org/draft/2020-12/schema
title: WorktaskStateLedger
type: object
required: [version, worktask_id, plan_file, platform, run_index, stages, facts, handoffs]
properties:
  version: { type: integer, const: 1 }
  worktask_id: { type: string, pattern: '^[a-z0-9\-]+$' }
  plan_file: { type: string }
  platform: { type: string, enum: [all, apple, ios, macos, watchos, tvos, visionos, web, server] }
  run_index: { type: integer, minimum: 0, default: 0 }
  stages:
    type: object
    additionalProperties:
      type: object
      required: [status]
      properties:
        status: { type: string, enum: [pending, in_progress, completed, blocked, skipped] }
        artifact: { type: string }
        complexity: { type: integer, minimum: 0, maximum: 50 }
        verdict: { type: string }
        retry_count: { type: integer, minimum: 0, default: 0 }
        error_file: { type: string }
        progress:
          type: object
          description: |
            OPTIONAL. Budget-aware checkpoint for multi-batch stages (currently DV).
            Written after each sub-batch commit so a budget-exhausted agent leaves a
            resumable record instead of a progress narration. The orchestrator reads
            `next_batch` to resume the stage from where it stopped (see
            `agents/developer.md § Budget-Aware Checkpointing` and
            `skills/worktask/SKILL.md § Orchestrator Execution Loop` step 4.7).
            Stores batch ids only — never diffs, file contents, or test output.
          properties:
            completed_batches: { type: array, items: { type: string } }
            next_batch: { type: string, description: "id of the next pending sub-batch, or absent when done" }
            updated_at: { type: string, format: date-time }
  facts:
    type: object
    required: [files_modified, tests_added, decisions, open_questions, verdicts]
    properties:
      goal:
        type: string
        maxLength: 240
        description: |
          One-sentence statement of the worktask's intent, populated by PL0 from the user-supplied task
          description (or the issue title in `--milestone:N` mode). Read by stage agents that need the
          original intent without re-reading the plan file (e.g. AR sanity-checking architecture against
          requirements, FN composing the PR title). Supersedes the `/goal` slash directive — the directive
          would have been a second, drift-prone surface for the same value (v3.10.1).
      files_modified: { type: array, items: { type: string } }
      tests_added: { type: array, items: { type: string } }
      decisions:
        type: array
        items:
          type: object
          required: [id, summary, ref]
          properties:
            id: { type: string }
            summary: { type: string, maxLength: 160 }
            ref: { type: string }
      open_questions:
        type: array
        items:
          type: object
          required: [id, summary]
          properties:
            id: { type: string }
            summary: { type: string }
            stage: { type: string }
      verdicts:
        type: object
        additionalProperties: { type: string }
      files_read:
        type: array
        maxItems: 30
        description: |
          Source files read by prior stages. Populated by DV; consumed by DR/QA
          to prefer `git diff` over full re-reads. When a file appears here,
          downstream stages SHOULD use `git diff <base>..HEAD -- <path>` instead
          of `Read <path>`. Full reads are still permitted when the diff is
          insufficient (e.g., reviewing surrounding context of a complex change).
          If absent, downstream stages fall back to normal reads (backward-compat).
        items:
          type: object
          required: [path, stage]
          properties:
            path: { type: string }
            stage: { type: string, enum: [PL, AR, TL, DV, DR, SR, QA, DC, RE, FN, ST, IR, ET] }
            lines: { type: string, description: "'all' or '<start>-<end>'" }
  mcp_session:
    type: object
    description: |
      Cached XcodeBuildMCP session state. Written by orchestrator warmup (step 5c);
      read by DV/DR/QA to skip redundant session_show_defaults / list_schemes /
      list_sims calls. If absent or stale (>30min), agents fall back to live calls.
    properties:
      xcode_defaults: { type: object, description: "Result of session_show_defaults" }
      schemes: { type: array, items: { type: string } }
      simulators: { type: array, items: { type: object } }
      warmed_at: { type: string, format: date-time }
  handoffs:
    type: object
    additionalProperties:
      type: string
      maxLength: 300
      pattern: '.*ref:.*'
  workflow:
    type: object
    description: |
      OPTIONAL. Present only in `--dynamic` execution mode (CC native Workflow engine).
      Additive and version-1-compatible: absent in manual mode and ignored by readers that predate it,
      so adding it never breaks an existing reader. The native `run_id` is a RESUME POINTER only —
      `state.json` + the Task System remain the source of truth. Written by the orchestrator at launch
      and on return; mutated mid-span only by the workflow script (single writer at phase boundaries).
      Full semantics: `skills/worktask/references/dynamic-workflow.md#state-workflow-block`.
    properties:
      run_id: { type: string, description: "Native Workflow runId; maps to resumeFromRunId on resume" }
      mode: { type: string, enum: [dynamic] }
      launched_at_stage: { type: string, enum: [PL, AR, TL, DV, DR, SR, QA, DC, RE, FN, ST, IR, ET] }
      stops_before: { type: string, enum: [FN, ST], description: "FN in interactive mode; ST in bypass modes" }
      budget:
        type: object
        properties:
          estimate_usd: { type: number, minimum: 0, description: "PL0-emitted span estimate" }
          ceiling_usd: { type: number, minimum: 0, description: "operator-tunable headroom ceiling passed to the engine" }
      status: { type: string, enum: [running, returned] }
```

### Eviction order on overflow

When state.json approaches the 500-token cap:

1. Drop `stages.<CODE>.artifact` paths for stages with `status=completed` once their `handoffs[FROM→TO]` string captures the essentials.
2. Drop `facts.open_questions` whose status is resolved.
3. Drop `facts.decisions` older than 2 stages back (keep current + previous stage decisions).
4. Drop `facts.files_read` entries whose `stage` is older than 2 stages back.
5. NEVER store diffs, file contents, or test output. Fetch from git/disk on demand.

### PL0 seed (initial state)

PL0 (or `commands/worktask.md` Phase 1) writes the initial ledger:

```json
{
  "version": 1,
  "worktask_id": "<from task metadata>",
  "plan_file": ".context/planning-0.md",
  "platform": "all",
  "run_index": 0,
  "stages": {
    "PL": { "status": "in_progress" }
  },
  "facts": {
    "goal": "<one-sentence intent — first 240 chars of task.description or issue title>",
    "files_modified": [],
    "tests_added": [],
    "decisions": [],
    "open_questions": [],
    "verdicts": {}
  },
  "handoffs": {}
}
```

**On a new PL run in an existing `.context/`**: PL0 atomically resets `stages` to `{PL: in_progress}`, resets `facts.*` to empty arrays/objects, and sets `run_index` to the new N. Historical run data lives in the on-disk `<stage>-N.md` artifacts, not in state.json.

---

## #fallback-paths

Five documented degradation paths. Worktask MUST complete in all five (AC-16, AC-17).

| Path | Trigger | Behavior |
|------|---------|----------|
| F1 | state.json **absent** | Fall back to legacy `metadata.context_files` mode. Read listed files in full. No cache-friendly preamble. Log INFO `state.json not found, legacy mode`. |
| F2 | state.json **present**, agent ignores it | No penalty. Agent reads listed files and writes its artifact. Orchestrator's hook patches state.json from frontmatter (or return text on F3). |
| F3 | Agent writes artifact **without frontmatter** | Orchestrator logs WARN `frontmatter missing in <artifact>`. Derives minimal handoff: `{stage, verdict: ok, summary: <first 200 chars of return>, refs: {artifact: <path>}}`. Worktask proceeds. |
| F4 | state.json **corrupt** (invalid JSON or schema mismatch) | Quarantine to `.context/state.json.bad.<unix-ts>`. Regenerate from PL0 + completed-stage frontmatter walk. Audit log to `.context/logs/state-recovery.log`. Continue. |
| F5 | **Dynamic mode**: the workflow script cannot patch state.json mid-span (e.g. the script crashed before merging a stage return, or `SubagentStop` did not fire for an `agent()` child and no script merge ran) | On workflow **return**, the orchestrator reconciles from the typed `schema` returns the script *did* produce; for any stage still missing from the ledger, fall through to the **F4 frontmatter walk** over `.context/<stage>-N.md`. Reconciliation is idempotent (re-applying an identical patch is a no-op). Manual-mode resume is always available if the run crashed entirely. See `dynamic-workflow.md#boundary-reconciliation` and `#fallback`. |

### F4 regeneration walk

1. Glob `.context/{planning-*,analyzing-*,coordination-*,development-*,developer-review-*,security-review-*,testing-*,documentation-*,release-*,complete-summary-*,retrospective-*,incident-*,ethics-review-*}.md`.
2. For each file, extract `handoff:` frontmatter (yq or fallback parser).
3. Sort by stage order: PL, AR, TL, DV, DR, SR, QA, DC, RE, FN, ST, IR, ET.
4. Build state.json from PL0's frontmatter as seed.
5. For each subsequent stage, merge `stages.<CODE>` from its frontmatter + add to `handoffs[FROM→TO]`.
6. Atomic-write per `#atomic-write`.

---

## #stage-artifact-map

Canonical mapping from stage code to artifact filename (used by orchestrator, hook, and F4 regeneration walk).

All stage artifacts are numbered; N is allocated by PL0 (same value as `planning-N.md`) and propagated via `task.metadata.run_index`. Readers fall back to newest-glob (`<basename>-*.md`).

| Stage code | Artifact filename | Plural? |
|------------|-------------------|---------|
| PL | `planning-N.md` (N starts at 0) | yes |
| AR | `analyzing-N.md` | yes |
| TL | `coordination-N.md` | yes |
| DV | `development-N.md` | yes |
| DR | `developer-review-N.md` | yes |
| SR | `security-review-N.md` | yes |
| QA | `testing-N.md` | yes |
| DC | `documentation-N.md` | yes |
| RE | `release-N.md` | yes |
| FN | `complete-summary-N.md` | yes |
| ST | `retrospective-N.md` | yes |
| IR | `incident-N.md` | yes |
| ET | `ethics-review-N.md` | yes |

The same N is shared across all stages within a worktask run. `metadata.plan_file` pins the active plan; `metadata.run_index` (integer ≥ 0) resolves `<basename>-N.md` for every other stage. See `agents/product-manager.md § Plan File & Run Index Naming` for the full resolver and propagation algorithm.

---

## #cache-prefix

Anthropic prompt cache matches by **prefix-prefix equality**, not full-block equality. The orchestrator builds the preamble in this order to maximize the byte-identical prefix shared across consecutive `Task()` calls within the same `worktask_id`.

### Preamble layout (binding)

```
[1] Plugin/agent contract reminder         ← stable across ALL stages
[2] Worktask header (id, plan, exploration)← stable across ALL stages
[3] state.json blob (inlined JSON)         ← evolves per stage
[4] Stage contract excerpt (this stage)    ← stable WITHIN stage type
─────── (cache prefix boundary for sections 1+2+4 sharing) ───────
[5] task.description                       ← dynamic per delegation
[6] retry hints (if retry_count > 0)       ← dynamic per delegation
[7] Stage-specific banners (DR Skill, FN Conductor, MCP fallback) ← suffix only
```

### Forbidden tokens in sections [1], [2], [4]

Anything below collapses cache-hit rate:

- Timestamps (`date`, `now`, ISO-8601 strings)
- ENV expansions that vary per call (`$HOSTNAME`, `$USER`, `$PWD` if it differs)
- Random IDs (UUIDs, `$RANDOM`, request IDs)
- Retry counters (move to section [6])
- File mtimes
- Agent-specific names beyond `worktask_id` (don't bake `software-architector` into [1] or [2]; that goes in [4])
- Conversation message IDs

### Required tokens in sections [1], [2], [4]

- `worktask_id` (string literal in [2])
- `plan_file` path (string literal in [2])
- Static contract reminder text (section [1])
- Stage contract excerpt for this stage type (section [4]) — drawn from `skills/shared/stage-contracts.md`, copied verbatim

### Expected cache_read_input_tokens ratio

- Stage 1 (PL): 0% (cold cache).
- Stage 2..N, no retry: ≈ 20% (cross-stage prefix [1]+[2] cached).
- Stage 2..N, retry within same stage with state.json unchanged: ≈ 80% (full preamble cached).
- Cross-stage average: ≈ 60% (meets AC-14).

### Settings

```json
{ "env": { "ENABLE_PROMPT_CACHING_1H": "1" } }
```

Documented in `skills/cost-optimization/SKILL.md`. Without 1h flag, default 5-min TTL applies; users still see savings on retries inside the same stage but lose cross-stage cache between long-running stages.

### Lint

`skills/worktask/references/cache-lint.sh` asserts byte-identity of sections [1]+[2]+[4] across consecutive stages of the same `worktask_id`. Runs in CI on PRs touching `skills/worktask/`, `skills/shared/`, or `agents/`.

---

## #anchor-allow-list

All stage artifacts MUST contain exactly the H2 headings (kebab-case, no underscores, no spaces) listed below. DR runs anchor-lint on every produced artifact; CI runs the same lint on PRs touching `skills/` or `agents/`.

| Stage | Artifact | Mandatory H2 anchors |
|-------|----------|-----------------------|
| PL | planning-N.md | `## requirements`, `## acceptance-criteria`, `## scope`, `## out-of-scope`, `## risks`, `## complexity`, `## stages` |
| AR | analyzing-N.md | `## decisions`, `## trade-offs`, `## patterns`, `## integration-points`, `## schemas`, `## open-questions`, `## risks` |
| TL | coordination-N.md | `## fan-out`, `## shared-snippets`, `## sequence`, `## risks` |
| DV | development-N.md | `## files-changed`, `## tests-added`, `## deviations`, `## follow-ups` |
| DR | developer-review-N.md | `## findings`, `## verdict`, `## blockers`, `## follow-ups` |
| SR | security-review-N.md | `## findings`, `## verdict`, `## blockers`, `## threat-model` |
| QA | testing-N.md | `## results`, `## coverage`, `## regressions`, `## verdict` |
| DC | documentation-N.md | `## files-changed`, `## cross-references`, `## follow-ups` |
| RE | release-N.md | `## artifacts`, `## version`, `## rollback-plan` |
| FN | complete-summary-N.md | `## summary`, `## artifacts`, `## followups`, `## metrics` |
| ST | retrospective-N.md | `## decision`, `## learnings`, `## followups` |
| IR | incident-N.md | `## root-cause`, `## fix-plan`, `## blast-radius` |
| ET | ethics-review-N.md | `## findings`, `## verdict`, `## mitigations` |

### Convention rules

1. H2 only. H1 is reserved for the artifact's title (exempt from anchor lint).
2. Kebab-case. No spaces, no underscores, no camelCase.
3. Anchor IDs are derived by GitHub-style slugify (lowercase, spaces→hyphens, strip punctuation). The H2 title MUST be the kebab-case form already; we don't rely on slugify.
4. `key_decisions[].anchor` and `refs.*` MUST resolve to a real `## <slug>` heading in the target file. The handoff harness validates this.

### Anchor Pre-Flight (PostToolUse hook)

By default, anchor-lint runs at the DR gate. That is post-hoc — a missing anchor in `planning-N.md` only surfaces after AR/TL/DV have already paid the full-file re-read cost. To catch omissions at the producing stage, register a PostToolUse hook on `Write`/`Edit` of `.context/*-N.md` artifacts:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "command": "if [[ \"$CLAUDE_TOOL_INPUT_FILE_PATH\" =~ \\.context/(planning|analyzing|coordination|development|developer-review|security-review|testing|documentation|release|complete-summary|retrospective|incident|ethics-review)-[0-9]+\\.md$ ]]; then skills/worktask/references/cache-lint.sh --anchor-lint \"$CLAUDE_TOOL_INPUT_FILE_PATH\"; fi"
      }
    ]
  }
}
```

When the hook fails (non-zero exit), the agent that produced the artifact sees the diagnostic and amends the file before continuing — no downstream stages incur the cost. The DR-gate lint remains as a CI safety net for non-hook environments.

**Cost**: lint runs in O(seconds) per artifact (greps H2 headings), one-shot per Write/Edit; net win once it prevents a single missed-anchor cascade (~2-3K tokens × N downstream stages).

---

## Future work (out of scope for v1)

- `version: 1` is the migration hook. v2 schema additions ship behind that field.
- A relaxed-profile schema for cross-plugin agents (apple-developer:*) is documented as a stub in `skills/cross-plugin-handoff/SKILL.md` for future negotiation.
- Compression of `.context/logs/audit.jsonl` is out of scope.
- Migration of historical `.context/` artifacts is out of scope.
