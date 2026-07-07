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

Atomic state.json write: **lock → read → merge → temp → fsync → rename → unlock**. The
read-merge-rename window is serialized by an mkdir-spinlock (macOS has no `flock(1)`), so
legal sibling overlap (parallel DVN tracks, DC+QA) cannot drop a patch to last-rename-wins.
POSIX-shell pseudocode:

```bash
# 0. Acquire the merge lock (mkdir is atomic on POSIX). Env knobs:
#    STATE_LOCK_TIMEOUT_S (default 5), STATE_LOCK_STALE_S (default 60).
lockdir=".context/state.json.lock.d"; waited=0
until mkdir "$lockdir" 2>/dev/null; do
  # Break a leaked lock older than STATE_LOCK_STALE_S (by dir mtime).
  age=$(( $(date +%s) - $(stat -f %m "$lockdir" 2>/dev/null || stat -c %Y "$lockdir") ))
  (( age >= STATE_LOCK_STALE_S )) && { rmdir "$lockdir" 2>/dev/null; continue; }
  # Timeout ⇒ proceed UNLOCKED + WARN (never a silent no-op). break_unlocked=1.
  (( waited >= STATE_LOCK_TIMEOUT_S )) && { echo "WARN: lock timeout — unlocked" >&2; break_unlocked=1; break; }
  sleep 1; waited=$(( waited + 1 ))
done
trap 'rmdir "$lockdir" 2>/dev/null' EXIT   # release on process end/failure

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

# 6. Release the lock (also released by the EXIT trap above).
rmdir "$lockdir" 2>/dev/null
```

Failure semantics:

- Crash before step 3 — state.json untouched (last-known-good preserved).
- Crash between 3 and 5 — temp file orphaned in `.context/`. Cleanup on next worktask start: `rm -f .context/.state.json.*.tmp`. state.json untouched.
- Crash after 5 — state.json contains new value. Idempotent (re-running merge with same patch is a no-op).
- Crash while holding the lock — the EXIT trap releases it; a crash that skips the trap leaves a lock dir that the next writer breaks once it is older than `STATE_LOCK_STALE_S`.

Single-writer invariant (revised): **one writer per stage KEY**. Sibling overlap is legal —
two stages (or two parallel DVN tracks writing distinct keys) may merge concurrently; the
mkdir-spinlock serializes their read-merge-rename windows so neither patch is lost. There is
no global "exactly one agent `in_progress`" requirement. **Timeout ⇒ proceed unlocked + WARN**,
which is never worse than the pre-lock lockless path (an exit-0 no-op would instead let a
leaked lock silently swallow merges). The lock lives only in `state-patch.sh`'s `atomic_merge()`;
the SubagentStop hook inherits it by delegation. The legacy `_inline_merge` fallback in
`state-merge.sh` (used only when `state-patch.sh` is absent) stays unlocked — a documented
transitional residual.

The lock implementation is `skills/worktask/scripts/state-patch.sh` (`_lock_acquire` /
`_lock_release` / `_lock_break_if_stale`); the two env knobs mirror the `DISK_MIN_GB` pattern.

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

## Handoff Schemas {#handoff-schemas}

Canonical typed-return schemas. These are the single source of truth for the structured object a stage agent returns from its `Task()` dispatch in the manual orchestrator loop (`skills/worktask/SKILL.md § Orchestrator Execution Loop` Step 6).

Typed `schema` returns replace prose-frontmatter scraping **on the typed path**, but each stage STILL mirrors its result to `state.json facts` and writes its `.context/<stage>-N.md` artifact with `handoff:` frontmatter (durability, human readability, F4 regeneration — see `#frontmatter-schema`, `#fallback-paths`). The typed return is a *parallel, validated* channel; the frontmatter is the *cache-friendly compressed on-disk* channel. Neither replaces the other.

Schemas are JSON Schema (draft 2020-12). **Each stage's `verdict` enum MUST match that stage's row in `#frontmatter-schema § Per-stage required-field matrix`** — the typed return and the frontmatter share one verdict vocabulary per stage. The `required` field set is the typed superset of that stage's frontmatter required fields (e.g. DR's `key_decisions (= findings)` becomes the typed `findings`/`blockers` arrays).

> **Cache-prefix note (binding, PRESERVE §4.1).** The schema is passed as a `Task()`/`agent()` **argument**, never inserted into preamble sections [1][2][4]. Adding schema dispatch therefore does NOT touch cache-prefix byte-identity (`#cache-prefix`).

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "PLHandoff",
  "type": "object",
  "required": ["verdict", "summary", "key_decisions", "next_stage_focus"],
  "properties": {
    "verdict": { "type": "string", "enum": ["ok", "blocked", "escalate"] },
    "summary": { "type": "string", "maxLength": 200 },
    "complexity": { "type": "integer", "minimum": 0, "maximum": 50 },
    "key_decisions": { "type": "array", "items": { "type": "string" } },
    "next_stage_focus": { "type": "string" },
    "open_questions": { "type": "array", "items": { "type": "string" } }
  }
}
```

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "ARHandoff",
  "type": "object",
  "required": ["verdict", "summary", "key_decisions", "next_stage_focus"],
  "properties": {
    "verdict": { "type": "string", "enum": ["ok", "blocked", "escalate"] },
    "summary": { "type": "string", "maxLength": 200 },
    "key_decisions": { "type": "array", "items": { "type": "string" } },
    "next_stage_focus": { "type": "string" },
    "open_questions": { "type": "array", "items": { "type": "string" } }
  }
}
```

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "TLHandoff",
  "type": "object",
  "required": ["verdict", "summary", "next_stage_focus"],
  "properties": {
    "verdict": { "type": "string", "enum": ["ok", "blocked", "escalate"] },
    "summary": { "type": "string", "maxLength": 200 },
    "next_stage_focus": { "type": "string" },
    "fanout": { "type": "array", "items": { "type": "string" } }
  }
}
```

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "DVHandoff",
  "type": "object",
  "required": ["verdict", "files_modified", "build_status"],
  "properties": {
    "verdict": { "type": "string", "enum": ["ok", "blocked", "escalate"] },
    "files_modified": { "type": "array", "items": { "type": "string" } },
    "tests_added": { "type": "array", "items": { "type": "string" } },
    "build_status": { "type": "string", "enum": ["pass", "fail", "skipped"] },
    "decisions": { "type": "array", "items": { "type": "string" } }
  }
}
```

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "DRHandoff",
  "type": "object",
  "required": ["verdict", "findings", "blockers"],
  "properties": {
    "verdict": { "type": "string", "enum": ["pass", "fail"] },
    "findings": { "type": "array", "items": { "type": "string" } },
    "blockers": { "type": "array", "items": { "type": "string" } },
    "p2_only": { "type": "boolean" }
  }
}
```

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "SRHandoff",
  "type": "object",
  "required": ["verdict", "findings", "blockers"],
  "properties": {
    "verdict": { "type": "string", "enum": ["pass", "fail"] },
    "findings": { "type": "array", "items": { "type": "string" } },
    "blockers": { "type": "array", "items": { "type": "string" } },
    "threat_model": { "type": "string" }
  }
}
```

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "QAHandoff",
  "type": "object",
  "required": ["verdict", "tests_passed", "tests_failed"],
  "properties": {
    "verdict": { "type": "string", "enum": ["go", "no-go"] },
    "tests_passed": { "type": "integer", "minimum": 0 },
    "tests_failed": { "type": "integer", "minimum": 0 },
    "blocking_defects": { "type": "array", "items": { "type": "string" } }
  }
}
```

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "DCHandoff",
  "type": "object",
  "required": ["verdict", "files_modified"],
  "properties": {
    "verdict": { "type": "string", "enum": ["ok", "blocked", "escalate"] },
    "files_modified": { "type": "array", "items": { "type": "string" } },
    "cross_references": { "type": "array", "items": { "type": "string" } }
  }
}
```

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "REHandoff",
  "type": "object",
  "required": ["verdict", "version", "files_modified"],
  "properties": {
    "verdict": { "type": "string", "enum": ["ok", "blocked"] },
    "version": { "type": "string" },
    "files_modified": { "type": "array", "items": { "type": "string" } },
    "changelog": { "type": "array", "items": { "type": "string" } }
  }
}
```

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "FNHandoff",
  "type": "object",
  "required": ["verdict", "summary", "next_stage_focus"],
  "properties": {
    "verdict": { "type": "string", "enum": ["ok", "blocked"] },
    "summary": { "type": "string", "maxLength": 200 },
    "next_stage_focus": { "type": "string" },
    "files_modified": { "type": "array", "items": { "type": "string" } },
    "pr_url": { "type": "string" }
  }
}
```

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "STHandoff",
  "type": "object",
  "required": ["verdict", "key_decisions"],
  "properties": {
    "verdict": { "type": "string", "enum": ["approve", "reject"] },
    "key_decisions": { "type": "array", "items": { "type": "string" } },
    "follow_ups": { "type": "array", "items": { "type": "string" } }
  }
}
```

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "IRHandoff",
  "type": "object",
  "required": ["verdict", "root_cause", "next_stage_focus"],
  "properties": {
    "verdict": { "type": "string", "enum": ["ok", "escalate"] },
    "root_cause": { "type": "string" },
    "next_stage_focus": { "type": "string" },
    "blast_radius": { "type": "string" }
  }
}
```

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "ETHandoff",
  "type": "object",
  "required": ["verdict", "findings"],
  "properties": {
    "verdict": { "type": "string", "enum": ["pass", "fail"] },
    "findings": { "type": "array", "items": { "type": "string" } },
    "mitigations": { "type": "array", "items": { "type": "string" } }
  }
}
```

### #schema-to-state-map

Each schema field maps onto the canonical `state.json` ledger (`#state-json-schema`) and the
artifact anchor (`#anchor-allow-list`). The orchestrator applies this map when a typed return is
present (`skills/worktask/SKILL.md § Orchestrator Execution Loop` Step 6). When no typed return is present, the same targets are
populated from the artifact's `handoff:` frontmatter instead (F2/F3) — the map is channel-agnostic.

| Schema field | state.json target | Artifact anchor |
|--------------|-------------------|-----------------|
| `PL.verdict` | `stages.PL.verdict` | planning-N.md (frontmatter) |
| `PL.complexity` | `stages.PL.complexity` | planning-N.md `## complexity` |
| `PL.key_decisions` | `facts.decisions[]` | planning-N.md `## stages` |
| `AR.verdict` | `stages.AR.verdict` | analyzing-N.md `## decisions` |
| `AR.key_decisions` | `facts.decisions[]` | analyzing-N.md `## decisions` |
| `TL.verdict` | `stages.TL.verdict` | coordination-N.md `## fan-out` |
| `TL.fanout` | (DV sub-task prompts; not a ledger field) | coordination-N.md `## fan-out` |
| `DV.verdict` | `stages.DV.verdict` | development-N.md `## deviations` (summary line) |
| `DV.files_modified` | `facts.files_modified` (union) | development-N.md `## files-changed` |
| `DV.tests_added` | `facts.tests_added` (union) | development-N.md `## tests-added` |
| `DV.build_status` | `stages.DV.status` derivation | development-N.md `## deviations` |
| `DV.decisions` | `facts.decisions[]` | development-N.md (inline) |
| `DR.verdict` | `stages.DR.verdict` + `facts.verdicts.DR` | developer-review-N.md `## verdict` |
| `DR.findings`/`blockers` | `facts.decisions[]` (= findings) | developer-review-N.md `## findings`/`## blockers` |
| `SR.*` | mirrors DR targets (`facts.verdicts.SR`) | security-review-N.md |
| `QA.verdict` | `stages.QA.verdict` + `facts.verdicts.QA` | testing-N.md `## verdict` |
| `QA.tests_passed`/`failed` | `facts.verdicts.QA` (count string) | testing-N.md `## results` |
| `DC.verdict` | `stages.DC.verdict` | documentation-N.md `## files-changed` |
| `DC.files_modified` | `facts.files_modified` (union) | documentation-N.md `## files-changed` |
| `RE.verdict` | `stages.RE.verdict` | release-N.md `## version` |
| `RE.version` | `facts.decisions[]` (version) | release-N.md `## version` |
| `FN.verdict` | `stages.FN.verdict` | complete-summary-N.md `## summary` |
| `FN.pr_url` | `handoffs["RE→FN"]`/`DC→FN` (ref pointer) | complete-summary-N.md `## artifacts` |
| `ST.verdict` | `stages.ST.verdict` + `facts.verdicts.ST` | retrospective-N.md `## decision` |
| `IR.verdict` | `stages.IR.verdict` | incident-N.md `## root-cause` |
| `IR.root_cause` | `facts.decisions[]` | incident-N.md `## root-cause` |
| `ET.verdict` | `stages.ET.verdict` + `facts.verdicts.ET` | ethics-review-N.md `## verdict` |
| `DV.worktree_path` | `stages.DV.worktree.path` | development-N.md (frontmatter `worktree_path`) |
| `DV.worktree_branch` | `stages.DV.worktree.branch` | development-N.md (frontmatter `worktree_branch`) |

The v1 additive fields have **orchestrator-loop / hook writers**, not schema-mapped stage returns
(`facts.dispatched_agents[]`, `stages.<CODE>.last_error`, `stages.<CODE>.completed_via`,
`facts.capabilities` — see `skills/worktask/SKILL.md § Orchestrator Execution Loop` steps 6/6.5).
Only `stages.<CODE>.worktree` maps from a stage artifact — the DV handoff frontmatter
`worktree_path`/`worktree_branch`, applied by `state-patch.sh` (rows above).

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
        completed_via:
          type: string
          enum: [hook, step6_5, f3]
          description: |
            OPTIONAL (additive, version:1). Which enforcement layer stamped this stage
            `completed`. `hook` = SubagentStop delegation (Layer 2, `state-merge.sh` default);
            `step6_5` = orchestrator synchronous Step-6.5 (`STATE_MERGE_VIA=step6_5`);
            `f3` = orchestrator F3 minimal-patch fallback. **Absence encodes Layer-1 agent
            self-patch OR a pre-upgrade run** — the hook's idempotency check exits before
            writing when Layer 1 already landed, so no value is stamped. Observability only;
            no consumer behavior branches on it.
        last_error:
          type: object
          description: |
            OPTIONAL (additive, version:1). Written by the orchestrator Step-6.5 errored-return
            branch (CC ≥ 2.1.199/2.1.200 propagate errors with partial work) BEFORE routing to
            the retry matrix. `class` reuses the EXISTING taxonomy from
            `agent-coordination § Retry / Escalate Matrix` — no new vocabulary. Dropped once the
            stage reaches `status: completed` (see eviction rules).
          required: [class, at]
          properties:
            class: { type: string, enum: [transient, logic, missing_input, ambiguous_requirements, design_flaw, hard_constraint, exhausted] }
            partial: { type: boolean, description: "partial work was preserved on the errored return" }
            at: { type: string, format: date-time }
            ref: { type: string, description: "pointer into .context/errors/<agent>.md (e.g. #retry-1)" }
        worktree:
          type: object
          description: |
            OPTIONAL (additive, version:1; DV primarily). Records WHICH worktree the stage ran
            in — not just `worktree: true` semantics. Written by mapping the DV handoff
            frontmatter `worktree_path`/`worktree_branch` (`state-patch.sh`). Lets resume
            re-enter the exact worktree via `EnterWorktree(path)` (CC ≥ 2.1.157), DR/QA run in
            the right dir, and fn-gate read the branch without shelling `git rev-parse`. Kept
            through FN for PR context; dropped at archival.
          properties:
            path: { type: string }
            branch: { type: string }
  facts:
    type: object
    required: [files_modified, tests_added, decisions, open_questions, verdicts]
    properties:
      goal:
        type: string
        maxLength: 240
        description: |
          One-sentence statement of the worktask's intent, populated by PL0 from the user-supplied task
          description (or the issue title under a `/megatask` per-issue run). Read by stage agents that need the
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
      dispatched_agents:
        type: array
        description: |
          OPTIONAL (additive, version:1). Writer: the orchestrator loop ONLY. One entry per
          `task_id` (NOT per stage — parallel DVN tracks share the stage code), replaced on
          re-dispatch; dispatch history stays in `audit.jsonl`. Read by resume (`resume.md`
          step 0) to reconcile against `claude agents --json --all` under background-default
          dispatch (CC ≥ 2.1.198). No dispatch-timestamp field is stored (no consumer; `claude agents`
          rows carry their own start time). Terminal entries (`status: completed|failed`) are eviction candidates.
        items:
          type: object
          required: [stage, task_id, subagent_type, status]
          properties:
            stage: { type: string, description: "stage CODE (DV, DR, …)" }
            task_id: { type: string, description: "Task System id — the dedupe key" }
            subagent_type: { type: string, description: "resolved plugin:agent id" }
            agent_id: { type: string, description: "OPTIONAL launch-ack id when the runtime surfaces one (bg-default CC ≥ 2.1.198); resume degrades to best-effort subagent_type match when absent" }
            name: { type: string, description: "OPTIONAL named-spawn handle (megatask lanes); readable default names CC ≥ 2.1.196, /rename persists CC ≥ 2.1.202" }
            model_requested: { type: string, description: "OPTIONAL — metadata.model alias at dispatch" }
            model_resolved: { type: string, description: "OPTIONAL best-effort — model that actually ran (claude agents --json / audit); omit when unknown" }
            status: { type: string, enum: [launched, completed, failed] }
      capabilities:
        type: object
        description: |
          OPTIONAL (additive, version:1). Probe cache for account-level hard-fails so every
          later stage does not re-hit the same error. Written by the orchestrator on first
          observed failure; model resolution consults it before any fable-tier dispatch.
          Example: `{ "fable_dispatch": "credit_blocked", "checked_at": "<ISO>" }` — Fable 5 is
          1M-by-default (CC 2.1.170/2.1.173) but *dispatch* fails hard without 1M credits
          (CC 2.1.172; observed live per model-selection.md).
        additionalProperties: true
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
```

### Eviction order on overflow

When state.json approaches the 500-token cap:

1. Drop `stages.<CODE>.artifact` paths for stages with `status=completed` once their `handoffs[FROM→TO]` string captures the essentials.
2. Drop `facts.open_questions` whose status is resolved.
3. Drop `facts.decisions` older than 2 stages back (keep current + previous stage decisions).
4. Drop `facts.files_read` entries whose `stage` is older than 2 stages back.
5. Drop `facts.dispatched_agents[]` entries in a terminal state (`status: completed|failed`) — the live-agent reconciliation they exist for no longer applies; audit history persists in `audit.jsonl`.
6. Drop `stages.<CODE>.last_error` and `stages.<CODE>.completed_via` for stages that have reached `status: completed` (the error is resolved; provenance was observability-only).
7. Keep `stages.<CODE>.worktree` through FN (PR context needs the branch); drop it only at archival.
8. NEVER store diffs, file contents, or test output. Fetch from git/disk on demand.

### PL0 seed (initial state) {#pl0-seed}

PL0 (or `commands/worktask.md` Phase 1) writes the initial ledger. The seed is
**re-run aware** — `plan_file` and `run_index` use the next free planning index
`N` computed from any pre-existing `.context/planning-*.md` (`0` on a fresh
`.context/`). Hard-coding `0` would pin an old plan on a re-run and cause PL0 to
overwrite `planning-0.md`. The canonical executable snippet (with the bash `N`
computation) lives in `commands/worktask.md` Phase 1 step 3a — use it verbatim;
the JSON below shows the resulting shape:

```json
{
  "version": 1,
  "worktask_id": "<from task metadata>",
  "plan_file": ".context/planning-${N}.md",
  "platform": "all",
  "run_index": ${N},
  "stages": {
    "PL": { "status": "in_progress" }
  },
  "facts": {
    "goal": "<one-sentence intent — first 240 chars of task.description or issue title>",
    "files_modified": [],
    "tests_added": [],
    "decisions": [],
    "open_questions": [],
    "verdicts": {},
    "dispatched_agents": []
  },
  "handoffs": {}
}
```

The seed includes `facts.dispatched_agents: []` (additive, version:1) so the orchestrator loop
appends/replaces per-`task_id` dispatch entries in place rather than lazily creating the array on
first dispatch. The other additive fields (`stages.<CODE>.completed_via`/`last_error`/`worktree`,
`facts.capabilities`) are written on demand by their writers and MUST NOT be seeded — their absence
is meaningful (Layer-1 self-patch, no error, no worktree record, no observed capability hard-fail).

**On a new PL run in an existing `.context/`**: the seed sets `run_index = N`
(next free index) up front; PL0 then atomically resets `stages` to
`{PL: in_progress}` and resets `facts.*` to empty arrays/objects. Historical run
data lives in the on-disk `<stage>-N.md` artifacts, not in state.json.

---

## #fallback-paths

Four documented degradation paths. Worktask MUST complete in all four (AC-16, AC-17).

| Path | Trigger | Behavior |
|------|---------|----------|
| F1 | state.json **absent** | Fall back to legacy `metadata.context_files` mode. Read listed files in full. No cache-friendly preamble. Log INFO `state.json not found, legacy mode`. |
| F2 | state.json **present**, agent ignores it | No penalty. Agent reads listed files and writes its artifact. Orchestrator's hook patches state.json from frontmatter (or return text on F3). |
| F3 | Agent writes artifact **without frontmatter** | Orchestrator logs WARN `frontmatter missing in <artifact>`. Derives minimal handoff: `{stage, verdict: ok, summary: <first 200 chars of return>, refs: {artifact: <path>}}`. Worktask proceeds. |
| F4 | state.json **corrupt** (invalid JSON or schema mismatch) | Quarantine to `.context/state.json.bad.<unix-ts>`. Regenerate from PL0 + completed-stage frontmatter walk. Audit log to `.context/logs/state-recovery.log`. Continue. |

> F1 rationale (legacy `context_files` mode, cache-degradation tradeoff): see `skills/shared/legacy-fallback-f1.md`. This matrix is the canonical operational spec.

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

Anchor-lint also runs at the DR gate, but that is post-hoc — a missing anchor in `planning-N.md` only surfaces after AR/TL/DV have already paid the full-file re-read cost. To catch omissions at the producing stage, anchor-lint runs as a **managed plugin hook (shipped in `.claude-plugin/plugin.json`, default-on)** — it is no longer an optional, opt-in registration. The managed PostToolUse `Write|Edit` entry invokes `${CLAUDE_PLUGIN_ROOT}/hooks/anchor-preflight.sh`, which gates on the `.context/*-N.md` artifact regex below and delegates matching writes to `skills/worktask/references/cache-lint.sh --anchor-lint`:

```jsonc
// .claude-plugin/plugin.json → hooks.PostToolUse (managed entry, alongside audit-tooluse)
{
  "matcher": "Write|Edit",
  "hooks": [
    { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/anchor-preflight.sh", "continueOnBlock": true }
  ]
}
```

`anchor-preflight.sh` matches only the canonical artifact regex (`\.context/(planning|analyzing|coordination|development|developer-review|security-review|testing|documentation|release|complete-summary|retrospective|incident|ethics-review)-[0-9]+\.md$`); any other Write/Edit is a no-op. When the lint fails (non-zero exit), the agent that produced the artifact sees the diagnostic and amends the file before continuing — no downstream stages incur the cost. `continueOnBlock` follows the same managed-hook discipline as the other entries (the diagnostic is surfaced; an unrelated write is never blocked). The DR-gate lint plus the CI lint (PRs touching `skills/` or `agents/`) remain as the safety net for non-hook environments.

**Cost**: lint runs in O(seconds) per artifact (greps H2 headings), one-shot per Write/Edit; net win once it prevents a single missed-anchor cascade (~2-3K tokens × N downstream stages).

---

## Future work (out of scope for v1)

- `version: 1` is the migration hook. v2 schema additions ship behind that field.
- A relaxed-profile schema for cross-plugin agents (apple-developer:*) is documented as a stub in `skills/cross-plugin-handoff/SKILL.md` for future negotiation.
- Compression of `.context/logs/audit.jsonl` is out of scope.
- Migration of historical `.context/` artifacts is out of scope.
