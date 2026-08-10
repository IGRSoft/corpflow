# Handoff Protocol — Inter-Stage Communication Reference

Canonical specification for worktask inter-stage communication. Defines the `state.json` ledger, the YAML `handoff:` frontmatter contract, the cache-friendly preamble layout, and four documented backward-compat fallback paths.

## Referenced by

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

### Lock acquisition (step 0)

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
```

### Merge, write, rename (steps 1–6)

```bash
# …continued: same script, after lock acquisition
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

### Failure semantics

- Crash before step 3 — state.json untouched (last-known-good preserved).
- Crash between 3 and 5 — temp file orphaned in `.context/`. Cleanup on next worktask start: `rm -f .context/.state.json.*.tmp`. state.json untouched.
- Crash after 5 — state.json contains new value. Idempotent (re-running merge with same patch is a no-op).
- Crash while holding the lock — the EXIT trap releases it; a crash that skips the trap leaves a lock dir that the next writer breaks once it is older than `STATE_LOCK_STALE_S`.

### Single-writer invariant

Single-writer invariant (revised): **one writer per stage KEY**. Sibling overlap is legal —
two stages (or two parallel DVN tracks writing distinct keys) may merge concurrently; the
mkdir-spinlock serializes their read-merge-rename windows so neither patch is lost. There is
no global "exactly one agent `in_progress`" requirement. **Timeout ⇒ proceed unlocked + WARN**,
which is never worse than the pre-lock lockless path (an exit-0 no-op would instead let a
leaked lock silently swallow merges). The lock lives only in `state-patch.sh`'s `atomic_merge()`;
the SubagentStop hook inherits it by delegation. `state-patch.sh` is the single merge
implementation — when it is absent `state-merge.sh` logs a warning and exits 0 without merging.

### Lock implementation

The lock implementation is `skills/worktask/scripts/state-patch.sh` (`_lock_acquire` /
`_lock_release` / `_lock_break_if_stale`); the two env knobs mirror the `DISK_MIN_GB` pattern.

`$RANDOM` suffix on the temp filename guards against hypothetical PID reuse inside Task subagents (CR-7).

---

## #frontmatter-schema

Every stage artifact (planning-N.md, architecture-N.md, coordination-N.md, development-N.md, …) MUST start with a YAML block between `^---$` markers. Token budget ≤200. Line budget ≤30.

Not every stage runs on every worktask: **AR** and **TL** are optional (AR is a tier default PL0
may override in either direction; TL runs only when PL0 splits the work across ≥2 developers —
`skills/estimation-methodology/SKILL.md § Stage Inclusion Criteria`), so `architecture-N.md` and
`coordination-N.md` may legitimately be absent. Frontmatter fields that reference an absent
stage's artifact MUST be omitted rather than written with a dangling path.

JSON-Schema-style spec:

### Schema — handoff base

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
```

### Schema — key_decisions, files_touched, next_stage_focus

```yaml
# …continued: handoff.properties
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
```

### Schema — open_questions, refs, constraints

```yaml
# …continued: handoff.properties
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

### Schema — subagents_spawned (B2 governance)

```yaml
# …continued: handoff.properties
      subagents_spawned:
        type: array
        maxItems: 5
        description: >
          OPTIONAL (B2). Sub-agents this stage dispatched, so DR/orchestrator see the
          fan-out without walking audit.jsonl. The cap of 5 is a policy tripwire: a stage
          needing more should re-split (TL), not fan out unbounded. Nested spawns downshift
          a model tier by default and never run background-nested in a headless run.
        items:
          type: object
          required: [agent, task]
          properties:
            agent: { type: string, description: "resolved plugin:agent id" }
            task: { type: string, maxLength: 120 }
```

### Schema — deep_reads (B4 FN fan-in tripwire)

```yaml
# …continued: handoff.properties
      deep_reads:
        type: array
        description: >
          OPTIONAL (B4). Artifacts a fan-in stage (FN primarily) read IN FULL beyond their
          ≤200-token frontmatter, each with why the frontmatter was insufficient. Empty/
          absent is healthy (frontmatter-first sufficed); a long list is the tripwire that
          a producing stage's frontmatter is under-informative.
        items:
          type: object
          required: [artifact, reason]
          properties:
            artifact: { type: string }
            reason: { type: string, enum: [anchor-miss, flagged-verdict, retry, ambiguous] }
```

### Per-stage required-field matrix

#### Stages PL–DR

| Stage | Required (beyond base 4) | Optional | Verdict vocabulary |
|-------|--------------------------|----------|--------------------|
| PL | next_stage_focus, key_decisions | files_touched, open_questions | ok / blocked / escalate |
| AR | key_decisions, next_stage_focus, open_questions | files_touched, subagents_spawned | ok / blocked / escalate |
| TL | next_stage_focus | key_decisions, files_touched | ok / blocked / escalate |
| DV | files_touched, next_stage_focus | key_decisions, open_questions, subagents_spawned | ok / blocked / escalate |
| DR | key_decisions (= findings) | files_touched, open_questions | pass / fail |

#### Stages SR–ET

| Stage | Required (beyond base 4) | Optional | Verdict vocabulary |
|-------|--------------------------|----------|--------------------|
| SR | key_decisions (= findings) | files_touched | pass / fail |
| QA | files_touched (= tests added), key_decisions (= results) | open_questions | go / no-go |
| DC | files_touched | key_decisions | ok / blocked / escalate |
| RE | files_touched, key_decisions (= version) | open_questions | ok / blocked |
| FN | next_stage_focus, files_touched | key_decisions, deep_reads | ok / blocked |
| ST | key_decisions (= rationale) | open_questions | approve / reject |
| IR | key_decisions (= root cause), next_stage_focus | files_touched | ok / escalate |
| ET | key_decisions (= ethics findings) | open_questions | pass / fail |

### Token budget

Frontmatter is the canonical compression form: every downstream stage reads this block instead of the full upstream artifact when it only needs the verdict, decisions, or refs. Keep ≤200 tokens or downstream stages incur unnecessary cost.

---

## Handoff Schemas {#handoff-schemas}

Canonical typed-return schemas. These are the single source of truth for the structured object a stage agent returns from its `Task()` dispatch in the manual orchestrator loop (`skills/worktask/SKILL.md § Orchestrator Execution Loop` Step 6).

Typed `schema` returns replace prose-frontmatter scraping **on the typed path**, but each stage STILL mirrors its result to `state.json facts` and writes its `.context/<stage>-N.md` artifact with `handoff:` frontmatter (durability, human readability, F4 regeneration — see `#frontmatter-schema`, `#fallback-paths`). The typed return is a *parallel, validated* channel; the frontmatter is the *cache-friendly compressed on-disk* channel. Neither replaces the other.

### Schema conventions

Schemas are JSON Schema (draft 2020-12). **Each stage's `verdict` enum MUST match that stage's row in `#frontmatter-schema § Per-stage required-field matrix`** — the typed return and the frontmatter share one verdict vocabulary per stage. The `required` field set is the typed superset of that stage's frontmatter required fields (e.g. DR's `key_decisions (= findings)` becomes the typed `findings`/`blockers` arrays).

> **Cache-prefix note (binding, PRESERVE §4.1).** The schema is passed as a `Task()`/`agent()` **argument**, never inserted into preamble sections [1][2][4]. Adding schema dispatch therefore does NOT touch cache-prefix byte-identity (`#cache-prefix`).

### PLHandoff

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

### ARHandoff

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

### TLHandoff

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

### DVHandoff

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
    "decisions": { "type": "array", "items": { "type": "string" } },
    "architecture": {
      "type": "object",
      "properties": {
        "ref": { "type": "string", "pattern": "^architecture-[0-9]+\\.md(#[a-z-]+)?$" },
        "applied": { "type": "boolean" }
      },
      "required": ["ref", "applied"]
    }
  }
}
```

#### DVHandoff — architecture field notes

`architecture` is optional at the schema level but **required whenever `state.json` has a
`stages.AR` entry**, together with `refs.decisions` — both are written when AR ran and both are
omitted when it did not (`stage-contracts.md#tpl-dv § Architecture reference contract`). The gate
resolves the reference in one precedence shared by the harness, this schema and the DR rule:
`refs.decisions`, then `architecture.ref`. `handoff-harness.sh --validate-frontmatter <artifact>
--state <state.json>` enforces it (warn-only in 3.42.0, blocking under `--strict`). When AR was
excluded the object MUST be omitted;
the harness's inverse guard warns if an `architecture-*` reference appears without a `stages.AR`
entry. `applied` is DV's truthful statement that AR's recorded decisions were followed;
deviations are declared in `development-N.md ## decisions` with rationale, and DR fails an
undeclared one.

### DRHandoff

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

### SRHandoff

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

### QAHandoff

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

### DCHandoff

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

### REHandoff

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

### FNHandoff

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

### STHandoff

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

### IRHandoff

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

### ETHandoff

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

#### Map — PL, AR, TL

| Schema field | state.json target | Artifact anchor |
|--------------|-------------------|-----------------|
| `PL.verdict` | `stages.PL.verdict` | planning-N.md (frontmatter) |
| `PL.complexity` | `stages.PL.complexity` | planning-N.md `## complexity` |
| `PL.key_decisions` | `facts.decisions[]` | planning-N.md `## stages` |
| `AR.verdict` | `stages.AR.verdict` | architecture-N.md `## decisions` |
| `AR.key_decisions` | `facts.decisions[]` | architecture-N.md `## decisions` |
| `TL.verdict` | `stages.TL.verdict` | coordination-N.md `## fan-out` |
| `TL.fanout` | (DV sub-task prompts; not a ledger field) | coordination-N.md `## fan-out` |

#### Map — DV

| Schema field | state.json target | Artifact anchor |
|--------------|-------------------|-----------------|
| `DV.verdict` | `stages.DV.verdict` | development-N.md `## deviations` (summary line) |
| `DV.files_modified` | `facts.files_modified` (union) | development-N.md `## files-changed` |
| `DV.tests_added` | `facts.tests_added` (union) | development-N.md `## tests-added` |
| `DV.build_status` | `stages.DV.status` derivation | development-N.md `## deviations` |
| `DV.decisions` | `facts.decisions[]` | development-N.md (inline) |

#### Map — DR, SR, QA, DC, RE

| Schema field | state.json target | Artifact anchor |
|--------------|-------------------|-----------------|
| `DR.verdict` | `stages.DR.verdict` + `facts.verdicts.DR` | developer-review-N.md `## verdict` |
| `DR.findings`/`blockers` | `facts.decisions[]` (= findings) | developer-review-N.md `## findings`/`## blockers` |
| `SR.*` | mirrors DR targets (`facts.verdicts.SR`) | security-review-N.md |
| `QA.verdict` | `stages.QA.verdict` + `facts.verdicts.QA` | testing-N.md `## verdict` |
| `QA.tests_passed`/`failed` | `facts.verdicts.QA` (count string) | testing-N.md `## results` |
| `DC.verdict` | `stages.DC.verdict` | documentation-N.md `## files-changed` |
| `DC.files_modified` | `facts.files_modified` (union) | documentation-N.md `## files-changed` |
| `RE.verdict` | `stages.RE.verdict` | release-N.md `## version` |
| `RE.version` | `facts.decisions[]` (version) | release-N.md `## version` |

#### Map — FN, ST, IR, ET, worktree

| Schema field | state.json target | Artifact anchor |
|--------------|-------------------|-----------------|
| `FN.verdict` | `stages.FN.verdict` | complete-summary-N.md `## summary` |
| `FN.pr_url` | `handoffs["RE→FN"]`/`DC→FN` (ref pointer) | complete-summary-N.md `## artifacts` |
| `ST.verdict` | `stages.ST.verdict` + `facts.verdicts.ST` | retrospective-N.md `## decision` |
| `IR.verdict` | `stages.IR.verdict` | incident-N.md `## root-cause` |
| `IR.root_cause` | `facts.decisions[]` | incident-N.md `## root-cause` |
| `ET.verdict` | `stages.ET.verdict` + `facts.verdicts.ET` | ethics-review-N.md `## verdict` |
| `DV.worktree_path` | `stages.DV.worktree.path` | development-N.md (frontmatter `worktree_path`) |
| `DV.worktree_branch` | `stages.DV.worktree.branch` | development-N.md (frontmatter `worktree_branch`) |

#### Additive-field writers

The v1 additive fields have **orchestrator-loop / hook writers**, not schema-mapped stage returns
(`facts.dispatched_agents[]`, `stages.<CODE>.last_error`, `stages.<CODE>.completed_via`,
`facts.capabilities` — see `skills/worktask/SKILL.md § Orchestrator Execution Loop` steps 6/6.5).
Only `stages.<CODE>.worktree` maps from a stage artifact — the DV handoff frontmatter
`worktree_path`/`worktree_branch`, applied by `state-patch.sh` (rows above).

#### Additive-field writers — facts.branch

`facts.branch` has **two** writers: the orchestrator at `commands/worktask.md § Step 3c`, and
`refine-branch-target.sh` at § Step A.4b (at most once per run, pre-commit, ledger-only, no git
mutation). No stage agent ever writes it.

The orchestrator's write is an orchestrator-loop write, not a schema-mapped stage return: it
parses the final `branch=<name>` stdout line of `branch-name.sh`
(`commands/worktask.md § Step 3c`) and stamps it directly — `branch-name.sh` itself never
writes state.json (single write chokepoint, `#atomic-write`). When that line is empty or
non-conventional and the script's `target_branch=<name>` line is not, the **target** is what
gets stamped: the local rename can be blocked (upstream tracked, target exists, host
workspace) while the PR head is still the pipeline's to name. See field notes — branch above.

---

## #state-json-schema

`.context/state.json` is the worktask ledger. Created by PL0; patched by every stage on completion; read by orchestrator before each delegation; embedded in the preamble as section [3]. Token budget ≤500.

JSON-Schema-style spec:

#### Ledger root

```yaml
$schema: https://json-schema.org/draft/2020-12/schema
title: WorktaskStateLedger
type: object
required: [version, worktask_id, plan_file, platform, run_index, stages, facts, handoffs]
properties:
  version: { type: integer, const: 1 }
  worktask_id: { type: string, pattern: '^[a-z0-9\-]+$' }
  plan_file: { type: string }
  platform: { type: string, enum: [all, apple, android, web, systems, backend, ai] }  # canonical keys — skills/shared/platform-detection.md
  run_index: { type: integer, minimum: 0, default: 0 }
```

#### plan_file shape boundary

**`plan_file` shape boundary** — `state.json.plan_file` holds a **workspace-relative
path** (`.context/planning-N.md`); `task.metadata.plan_file` holds a **bare
basename** (`planning-N.md`). Both shapes are legal. Every reader MUST accept
either: try the value as given, then its basename resolved against the directory
holding `state.json`.

This paragraph is the canonical statement; every other writer and reader site
points here rather than restating the rule.

#### metadata.base_ref

The integration branch, mirrored by PL0 from `task.metadata.base_ref` so shell
helpers (which cannot read Task-System metadata) can reach it. Resolution order for
any reader, highest first: `$FN_BASE_REF`, `state.json .metadata.base_ref`,
`workspace.json .git.base_branch`,
`git symbolic-ref refs/remotes/origin/HEAD`, then **unresolved**. There is no literal
fallback: readers report unresolved and degrade non-blocking. Implemented in
`skills/worktask/scripts/fn-preflight.sh` `resolve_base_ref`.

#### stages

```yaml
# …continued: WorktaskStateLedger.properties.stages
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
          description: "OPTIONAL. Budget-aware checkpoint — see field notes"
          properties:
            completed_batches: { type: array, items: { type: string } }
            next_batch: { type: string, description: "id of the next pending sub-batch, or absent when done" }
            updated_at: { type: string, format: date-time }
```

#### stages — completed_via, last_error

```yaml
# …continued: WorktaskStateLedger.properties.stages.additionalProperties.properties
        completed_via:
          type: string
          enum: [hook, step6_5, f3]
          description: "OPTIONAL (additive, version:1) — see field notes"
        last_error:
          type: object
          description: "OPTIONAL (additive, version:1) — see field notes"
          required: [class, at]
          properties:
            class: { type: string, enum: [transient, logic, missing_input, ambiguous_requirements, design_flaw, hard_constraint, exhausted] }
            partial: { type: boolean, description: "partial work was preserved on the errored return" }
            at: { type: string, format: date-time }
            ref: { type: string, description: "pointer into .context/errors/<agent>.md (e.g. #retry-1)" }
```

#### stages — worktree

```yaml
# …continued: WorktaskStateLedger.properties.stages.additionalProperties.properties
        worktree:
          type: object
          description: "OPTIONAL (additive, version:1; DV primarily) — see field notes"
          properties:
            path: { type: string }
            branch: { type: string }
```

#### facts

```yaml
# …continued: WorktaskStateLedger.properties
  facts:
    type: object
    required: [files_modified, tests_added, decisions, open_questions, verdicts]
    properties:
      goal:
        type: string
        maxLength: 240
        description: "One-sentence worktask intent, populated by PL0 — see field notes"
      branch:
        type: string
        maxLength: 120
        description: "Working branch named once at PL start — see field notes"
      files_modified: { type: array, items: { type: string } }
      tests_added: { type: array, items: { type: string } }
```

#### facts — decisions

```yaml
# …continued: WorktaskStateLedger.properties.facts.properties
      decisions:
        type: array
        maxItems: 8
        description: "Bounded (B3): newest 8 survive. Clamped at the single write chokepoint state-patch.sh atomic_merge() (AD-7), not by producers — matches eviction-order rule 3."
        items:
          type: object
          required: [id, summary, ref]
          properties:
            id: { type: string }
            summary: { type: string, maxLength: 160 }
            ref: { type: string }
```

#### facts — open_questions, verdicts, files_read

```yaml
# …continued: WorktaskStateLedger.properties.facts.properties
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
        description: "Source files read by prior stages; DR/QA prefer git diff — see field notes"
        items:
          type: object
          required: [path, stage]
          properties:
            path: { type: string }
            stage: { type: string, enum: [PL, AR, TL, DV, DR, SR, QA, DC, RE, FN, ST, IR, ET] }
            lines: { type: string, description: "'all' or '<start>-<end>'" }
```

#### facts — dispatched_agents

```yaml
# …continued: WorktaskStateLedger.properties.facts.properties
      dispatched_agents:
        type: array
        maxItems: 6
        description: "OPTIONAL (additive, version:1); writer: the orchestrator loop ONLY — see field notes. Bounded (B3): 6 survive, launched-survive-first (live agents resume needs are kept ahead of terminal rows). Clamped in state-patch.sh atomic_merge() (AD-7)."
        items:
          type: object
          required: [stage, task_id, subagent_type, status]
          properties:
            stage: { type: string, description: "stage CODE (DV, DR, …)" }
            task_id: { type: string, description: "Task System id — the dedupe key" }
            subagent_type: { type: string, description: "resolved plugin:agent id" }
```

#### facts — dispatched_agents (continued)

```yaml
# …continued: dispatched_agents.items.properties
            agent_id: { type: string, description: "OPTIONAL launch-ack id when the runtime surfaces one (background-default dispatch); resume degrades to best-effort subagent_type match when absent" }
            name: { type: string, description: "OPTIONAL named-spawn handle (megatask lanes); readable default names, /rename persists across restarts" }
            model_requested: { type: string, description: "OPTIONAL — metadata.model alias at dispatch" }
            model_resolved: { type: string, description: "OPTIONAL best-effort — model that actually ran (claude agents --json / audit); omit when unknown" }
            status: { type: string, enum: [launched, completed, failed] }
```

#### facts — capabilities

```yaml
# …continued: WorktaskStateLedger.properties.facts.properties
      capabilities:
        type: object
        description: "OPTIONAL (additive, version:1); probe cache for account-level hard-fails — see field notes"
        additionalProperties: true
```

#### handoffs

```yaml
# …continued: WorktaskStateLedger.properties
  handoffs:
    type: object
    additionalProperties:
      type: string
      maxLength: 300
      pattern: '.*ref:.*'
```

#### Field notes — handoffs (edge registry)

Keys are `FROM→TO` stage-code pairs. Because PL0 sizes the stage set, several stages have more
than one possible predecessor — the edge that gets written is the one whose when-clause holds, so
a stage that never ran never appears in an edge label. Writing an edge for an absent stage
(a "phantom edge") is a ledger defect.

The table below is **exhaustive across all three pipelines** — standard, secure/full, and
emergency. The emergency pipeline (`IR→DV→DR→QA→RE→FN`) has **no PL, AR or TL stage at all**, so
DV's predecessor there is `IR`, and RE's is `QA` rather than `DC`. Any predecessor not listed here
is not a legal edge; add a row before writing one.

##### Edge table — standard and secure pipelines

| Edge | When | Written by |
|------|------|-----------|
| `USER→PL` | always (standard/secure) | PL |
| `PL→AR` | AR is in the plan | AR |
| `AR→TL` | TL is in the plan AND AR ran | TL |
| `PL→TL` | TL is in the plan AND AR was excluded | TL |
| `TL→DV` | TL ran | DV |
| `AR→DV` | AR ran AND TL did not | DV |
| `PL→DV` | neither AR nor TL ran | DV |
| `DV→DR` | always (DR is a floor stage) | DR |
| `DR→SR` | SR is in the plan | SR |
| `SR→QA` / `DR→QA` | SR ran / SR was excluded | QA |
| `QA→DC` | DC is in the plan | DC |
| `DC→RE` | RE is in the plan AND DC ran | RE |
| `RE→FN` / `DC→FN` | RE ran / RE was excluded | FN |
| `FN→ST` | ST is in the plan | ST |

##### Edge table — emergency pipeline and the ethics gate

| Edge | When | Written by |
|------|------|-----------|
| `USER→IR` | always (emergency pipeline) | IR |
| `IR→DV` | emergency pipeline — no PL/AR/TL stage exists | DV |
| `QA→RE` | emergency pipeline (RE's predecessor is QA, not DC) | RE |
| `<invoker>→ET` | the ethics gate fired; `<invoker>` is whichever stage triggered it | ET |

The writer passes its predecessor to `state-patch.sh --stage <CODE> --prev <PREV>`; the script
composes the key mechanically and does not itself know the when-clauses. `USER` is accepted as a
predecessor **only** — it owns no artifact and is never a valid `--stage`.

#### #layer-1-fallback

Every stage agent's State Patch section points here. Three outcomes, in order.

1. **Exit 3** — `--prev` given, `--via` absent, no artifact resolved: the self-patch signature.
   The stage claims an artifact that is not on disk. Write it and re-run. If you cannot, use
   item 2 — `--allow-missing-artifact` only silences the error and patches **nothing**.
2. **The tool cannot run at all** — not granted, denied, or not found. Do **NOT** skip silently.
   Patch `.context/state.json` with `Edit`: write both the `stages.<CODE>` completion entry and
   the `handoffs["<PREV>→<CODE>"]` edge, then record the failure under
   `metadata.pl_tooling_gaps`. The SubagentStop hook is **not** a substitute — it builds its
   args without `--prev`, so it repairs the stage entry and drops the edge.
3. **`jq` or `.context/state.json` genuinely absent** — skipping is correct here, and only here
   (F1 fallback).

#### Field notes — progress

OPTIONAL. Budget-aware checkpoint for multi-batch stages (currently DV). Written after each sub-batch commit so a budget-exhausted agent leaves a resumable record instead of a progress narration. The orchestrator reads `next_batch` to resume the stage from where it stopped (see `agents/developer.md § Budget-Aware Checkpointing` and `skills/worktask/SKILL.md § Orchestrator Execution Loop` step 4.7). Stores batch ids only — never diffs, file contents, or test output.

#### Field notes — completed_via

OPTIONAL (additive, version:1). Which enforcement layer stamped this stage `completed`. `hook` = SubagentStop delegation (Layer 2, `state-merge.sh` default); `step6_5` = orchestrator synchronous Step-6.5 (`STATE_MERGE_VIA=step6_5`); `f3` = orchestrator F3 minimal-patch fallback. **Absence encodes a Layer-1 agent self-patch** — the hook's idempotency check exits before writing when Layer 1 already landed, so no value is stamped. Observability only; no consumer behavior branches on it.

#### Field notes — last_error

OPTIONAL (additive, version:1). Written by the orchestrator Step-6.5 errored-return branch (errors propagate with partial work) BEFORE routing to the retry matrix. `class` reuses the EXISTING taxonomy from `agent-coordination § Retry / Escalate Matrix` — no new vocabulary. Dropped once the stage reaches `status: completed` (see eviction rules).

#### Field notes — worktree

OPTIONAL (additive, version:1; DV primarily). Records WHICH worktree the stage ran in — not just `worktree: true` semantics. Written by mapping the DV handoff frontmatter `worktree_path`/`worktree_branch` (`state-patch.sh`). Lets resume re-enter the exact worktree via `EnterWorktree(path)` and DR/QA run in the right dir, and FN carry PR context. The PR *head* comes from `facts.branch`, not from here — see the disambiguation note below. Kept through FN for PR context; dropped at archival.

#### Field notes — branch

OPTIONAL (additive, version:1). The worktask's **planned** working-branch name — the
host-session branch as `branch-name.sh` left it at the start of PL, whether it renamed the
branch or found it already conventional. Written at PL start and rewritten at most once, at
`commands/worktask.md § Step A.4b`, before any commit exists — never rewritten by a **stage**
(the once-only rule — `skills/shared/git-conventions.md § Once-only rule`). **This is the field FN uses as the
pull-request head.** Reading the ledger instead of shelling `git rev-parse` at FN time is
what makes an external mid-run rename unable to silently retarget the PR: the PR opens
against the name the worktask committed to, and divergence surfaces as a mismatch rather
than as a differently-named PR. Not the same field as `stages.DV.worktree.branch` — see the
disambiguation note below. Kept through FN; dropped at archival.

##### Field notes — branch, divergence from the local branch name

`facts.branch` may legitimately differ from `git rev-parse --abbrev-ref HEAD` on the
`upstream_tracked` and `target_exists` arms, and inside a linked worktree when
`BRANCH_NAME_WORKTREE_RENAME=0` is set — there `branch-name.sh` keeps the host's local name
and returns the derived `target_branch=` for the PR head instead, so the host's
branch↔workspace mapping survives (`workspace-modes.md § Host mapping — updated, not
preserved`). On the **default** worktree path the branch is renamed and the two agree.

Divergence is now **observed, not merely tolerated**: `fn-preflight.sh branch-divergence`
classes it `expected` or `third_party` and surfaces only `third_party` at the FN gate. Its
comparison base is the `to` of the last `branch_renamed / ok` row, not this field. No reader may "repair" it by re-deriving from the local branch — the ledger value is
the planned name and the PR head is what it plans.

##### Field notes — branch, empty value

`branch-name.sh` prints `branch=` (empty) for a detached HEAD or a not-a-git-repo outcome —
never the literal token `HEAD`, which is not a branch. FN MUST treat an empty `facts.branch`
as "no planned name to push under" and skip the `git push -u origin
HEAD:refs/heads/<facts.branch>` refspec entirely, falling back to a plain
`git push -u origin HEAD` (or the current branch's own name) instead. **On a detached HEAD,
this fallback fails loudly** with "The destination you provided is not a full refname" —
an acceptable failure (no wrong target, no silent error).

##### Disambiguation — `facts.branch` vs `stages.DV.worktree.branch`

Two fields, disjoint definitions, neither derived from the other:

| | `facts.branch` | `stages.DV.worktree.branch` |
|---|---|---|
| Meaning | **planned** host-session branch name | **observed** branch of the worktree DV ran in |
| Writer | orchestrator, from `branch-name.sh` stdout, at PL start; then `refine-branch-target.sh` at Step A.4b | `state-patch.sh`, from DV handoff `worktree_branch` |
| Written when | before any commit exists | after DV completes |
| Rewritten | at most once more, pre-commit (§ Step A.4b); never by a stage | per DV re-dispatch |
| FN uses for | the PR **head** | worktree re-entry context only |

##### Disambiguation — topology note

They are equal in the common topology where the session's workspace **is** the worktree
(`agents/developer.md § worktree_branch`), and differ when DV created a fresh
`.claude/worktrees/` worktree whose branch the tool named itself. **A mismatch is
information, not an error** — it tells FN the commits live somewhere other than the
planned branch, exactly the condition `fn-preflight.sh continuity` handles. No writer may
copy one into the other; that copy is what would make them a silent duplicate.

#### Field notes — goal

One-sentence statement of the worktask's intent, populated by PL0 from the user-supplied task description (or the issue title under a `/megatask` per-issue run). Read by stage agents that need the original intent without re-reading the plan file (e.g. AR sanity-checking architecture against requirements, FN composing the PR title). It is the single surface for this value — do not introduce a parallel one.

#### Field notes — files_read

Source files read by prior stages. Populated by DV; consumed by DR/QA to prefer `git diff` over full re-reads. When a file appears here, downstream stages SHOULD use `git diff <base>..HEAD -- <path>` instead of `Read <path>`. Full reads are still permitted when the diff is insufficient (e.g., reviewing surrounding context of a complex change). If absent, downstream stages fall back to normal reads (backward-compat).

#### Field notes — dispatched_agents

OPTIONAL (additive, version:1). Writer: the orchestrator loop ONLY. One entry per `task_id` (NOT per stage — parallel DVN tracks share the stage code), replaced on re-dispatch; dispatch history stays in `audit.jsonl`. Read by resume (`resume.md` step 0) to reconcile against `claude agents --json --all` under background-default dispatch. No dispatch-timestamp field is stored (no consumer; `claude agents` rows carry their own start time). Terminal entries (`status: completed|failed`) are eviction candidates.

#### Field notes — capabilities

OPTIONAL (additive, version:1). Probe cache for account-level hard-fails so every later stage does not re-hit the same error. Written by the orchestrator on first observed failure; model resolution consults it before any fable-tier dispatch. Example: `{ "fable_dispatch": "credit_blocked", "checked_at": "<ISO>" }` — Fable 5 is 1M-by-default but *dispatch* fails hard without 1M credits (observed live per model-selection.md).

### Eviction order on overflow

When state.json approaches the 500-token cap:

1. Drop `stages.<CODE>.artifact` paths for stages with `status=completed` once their `handoffs[FROM→TO]` string captures the essentials.
2. Drop `facts.open_questions` whose status is resolved.
3. Drop `facts.decisions` older than 2 stages back (keep current + previous stage decisions).
4. Drop `facts.files_read` entries whose `stage` is older than 2 stages back.

#### Eviction steps 5–8

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

#### Seed shape (resulting JSON)

`plan_file` here is the **path** shape; task metadata carries the basename shape. See
the `plan_file` shape boundary under § state.json schema.

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

#### Additive-field seeding

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
| F1 | state.json **absent** | Fall back to `metadata.context_files` mode. Read listed files in full. No cache-friendly preamble. Log INFO `state.json not found, context_files mode`. |
| F2 | state.json **present**, agent ignores it | No penalty. Agent reads listed files and writes its artifact. Orchestrator's hook patches state.json from frontmatter (or return text on F3). |

### Paths F3–F4

| Path | Trigger | Behavior |
|------|---------|----------|
| F3 | Agent writes artifact **without frontmatter** | Orchestrator logs WARN `frontmatter missing in <artifact>`. Derives minimal handoff: `{stage, verdict: ok, summary: <first 200 chars of return>, refs: {artifact: <path>}}`. Worktask proceeds. |
| F4 | state.json **corrupt** (invalid JSON or schema mismatch) | Back up to `.context/state.json.corrupt.<iso-ts>`. Rebuild the **skeleton only**, then recover **exactly the one stage being patched** by delegating to `state-patch.sh` unchanged. Audit row `state_repair` in `.context/logs/audit.jsonl`. Continue. |

#### F4 — partial recovery, by design {#f4-partial}

This table previously described a fuller contract than the hook implements. The divergences are the
shipped behaviour, upheld on review rather than treated as defects.

- **Backup is `.context/state.json.corrupt.<iso-ts>`**, not `.bad.<unix-ts>` — sorting by name sorts
  by time, and the suffix says what happened.
- **The audit trail is a `state_repair` row in `.context/logs/audit.jsonl`**, not a separate
  `state-recovery.log`. One audit surface, not two.
- **There is no completed-stage frontmatter walk.** The hook rebuilds the skeleton (including an
  empty `stages: {}`) and recovers only the stage whose patch triggered the repair.

#### F4 — consequences for readers {#f4-consequences}

A repaired ledger can legitimately show **fewer completed stages** than `.context/` contains, since
earlier stages are not replayed from their artifacts. When reconstructing history after a repair,
read the artifacts, not the ledger.

The full walk was considered and declined: it would make the hook a second, divergent implementation
of the artifact parser that `state-patch.sh` already owns.

**Fail-safe.** If the backup itself cannot be written (e.g. unwritable `.context/`), the repair
aborts, `state.json` is left **byte-identical**, no backup and no audit row are written, and the hook
still exits 0. Corrupt-and-untouched is the designed outcome; the repair never destroys the original.
An unchanged ledger is therefore not evidence the hook failed to run.

#### F1 — `context_files` mode {#f1-fallback}

The preferred handoff mode is anchor-based: a stage reads `.context/state.json` plus the anchors
named in `metadata.context_refs` (≥30% input-token reduction, cache-friendly preamble).

When `state.json` is absent (or `context_refs` is missing), stages fall back to reading every
`metadata.context_files` path in full — **`context_files` mode**. There is no cache-friendly
preamble in this mode, so the prompt-cache benefit collapses; the degradation is silent to the
worktask but surfaced via the `#f1-telemetry` log consumed by `/cost-report`.

##### F1 is required behavior, not compatibility

This path is **required** (AC-16/AC-17): a worktask MUST complete even
when `state.json` is absent — e.g. on a read-only filesystem, where the seed write fails. Both
metadata forms are dual-written by current code. `context_refs` wins when `state.json` is present;
`context_files` is the safety net. The F1 telemetry snippet lives in
`skills/shared/stage-contracts.md#f1-telemetry`.

### F4 regeneration walk

1. Glob `.context/{planning-*,architecture-*,coordination-*,development-*,developer-review-*,security-review-*,testing-*,documentation-*,release-*,complete-summary-*,retrospective-*,incident-*,ethics-review-*}.md`.
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
| AR | `architecture-N.md` | yes |
| TL | `coordination-N.md` | yes |
| DV | `development-N.md` (per-stream: `development-N-<stream>.md`) | yes |
| DR | `developer-review-N.md` | yes |
| SR | `security-review-N.md` | yes |
| QA | `testing-N.md` | yes |
| DC | `documentation-N.md` | yes |
| RE | `release-N.md` | yes |
| FN | `complete-summary-N.md` | yes |
| ST | `retrospective-N.md` | yes |
| IR | `incident-N.md` | yes |
| ET | `ethics-review-N.md` | yes |

### Per-stream DV artifacts

Under TL fan-out the DV entry agent spawns one sub-agent per
workstream; each writes only `development-N-<stream>.md`, where `<stream>` is the kebab slug the
coordination plan assigned. The entry agent alone merges them into the canonical
`development-N.md` at fan-in. `development-N.md` remains the documented DR/QA input and the file
the DV0 handoff and state patch describe — the per-stream files are inputs to the merge, not
handoff carriers.

### Run-index resolution

The same N is shared across all stages within a worktask run. `metadata.plan_file` pins the active plan; `metadata.run_index` (integer ≥ 0) resolves `<basename>-N.md` for every other stage. See `agents/product-manager.md § Plan File & Run Index Naming` for the full resolver and propagation algorithm.

### Alias basenames (resolution-only)

`state-patch.sh` accepts a second, search-only basename for three stages — DR `review`, QA
`qa`, FN `finalization` — living in a sibling function so `#stage-artifact-map` above stays the
single canonical name per stage. Aliases are accepted, never written: the canonical name is
always what gets emitted, and a canonical match outranks an alias match at the same run index.
Resolution order: primary@run_index → primary highest-N → alias@run_index → alias highest-N.
`AR` has no alias — `analyzing` is deliberately excluded (a prior naming generation used it; an
alias would let a stale file answer for the current one). `USER` is a valid `--prev` value only
— no artifact, never a `--stage` or basename (edge table above: `USER→PL`, `USER→IR`).

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

`skills/worktask/scripts/cache-lint.sh` asserts byte-identity of sections [1]+[2]+[4] across consecutive stages of the same `worktask_id`. Runs in CI on PRs touching `skills/worktask/`, `skills/shared/`, or `agents/`.

---

## #anchor-allow-list

All stage artifacts MUST contain exactly the H2 headings (kebab-case, no underscores, no spaces) listed below. DR runs anchor-lint on every produced artifact; CI runs the same lint on PRs touching `skills/` or `agents/`.

### Anchors — PL to DR

| Stage | Artifact | Mandatory H2 anchors |
|-------|----------|-----------------------|
| PL | planning-N.md | `## requirements`, `## acceptance-criteria`, `## scope`, `## out-of-scope`, `## risks`, `## complexity`, `## stages` |
| AR | architecture-N.md | `## decisions`, `## trade-offs`, `## patterns`, `## integration-points`, `## schemas`, `## open-questions`, `## risks` |
| TL | coordination-N.md | `## fan-out`, `## shared-snippets`, `## sequence`, `## risks` |
| DV | development-N.md | `## files-changed`, `## tests-added`, `## deviations`, `## follow-ups` |
| DR | developer-review-N.md | `## findings`, `## verdict`, `## blockers`, `## follow-ups` |

### Anchors — SR to ET

| Stage | Artifact | Mandatory H2 anchors |
|-------|----------|-----------------------|
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
4. `key_decisions[].anchor` and `refs.*` MUST resolve to a real `## <slug>` heading in the target file. Enforcement is narrower than the rule: the handoff harness validates cross-file resolution **only for the AR→DV edge** (`--validate-frontmatter <development-N.md> --state <state.json>` checks the architecture reference's pattern and that the file exists next to the artifact). Every other `refs.*` entry is checked for key presence only — a dangling target elsewhere is a contract violation the harness will not catch, so authors remain responsible for it.

### Anchor Pre-Flight (PostToolUse hook)

Anchor-lint also runs at the DR gate, but that is post-hoc — a missing anchor in `planning-N.md` only surfaces after AR/TL/DV have already paid the full-file re-read cost. To catch omissions at the producing stage, anchor-lint runs as a **managed plugin hook (shipped in `.claude-plugin/plugin.json`, default-on)** — it is no longer an optional, opt-in registration. The managed PostToolUse `Write|Edit` entry invokes `${CLAUDE_PLUGIN_ROOT}/hooks/anchor-preflight.sh`, which gates on the `.context/*-N.md` artifact regex below and delegates matching writes to `skills/worktask/scripts/cache-lint.sh --anchor-lint`:

#### Managed hook entry (plugin.json)

```jsonc
// .claude-plugin/plugin.json → hooks.PostToolUse (managed entry, alongside audit-tooluse)
{
  "matcher": "Write|Edit",
  "hooks": [
    { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/anchor-preflight.sh", "continueOnBlock": true }
  ]
}
```

#### Preflight behavior and cost

`anchor-preflight.sh` matches only the canonical artifact regex (`\.context/((planning|architecture|coordination|developer-review|security-review|testing|documentation|release|complete-summary|retrospective|incident|ethics-review)-[0-9]+|development-[0-9]+(-[a-z0-9]+)*)\.md$`); any other Write/Edit is a no-op. When the lint fails (non-zero exit), the agent that produced the artifact sees the diagnostic and amends the file before continuing — no downstream stages incur the cost. `continueOnBlock` follows the same managed-hook discipline as the other entries (the diagnostic is surfaced; an unrelated write is never blocked). The DR-gate lint plus the CI lint (PRs touching `skills/` or `agents/`) remain as the safety net for non-hook environments.

**Cost**: lint runs in O(seconds) per artifact (greps H2 headings), one-shot per Write/Edit; net win once it prevents a single missed-anchor cascade (~2-3K tokens × N downstream stages).

---

## Future work (out of scope for v1)

- `version: 1` is the migration hook. v2 schema additions ship behind that field.
- A relaxed-profile schema for cross-plugin agents (apple-developer:*) is documented as a stub in `skills/cross-plugin-handoff/SKILL.md` for future negotiation.
- Compression of `.context/logs/audit.jsonl` is out of scope.
- Migration of historical `.context/` artifacts is out of scope.
