# Handoff Protocol — Inter-Stage Communication Reference

Canonical specification for worktask inter-stage communication: the `state.json` ledger, the YAML `handoff:` frontmatter contract, the typed-return schemas, the cache-friendly preamble layout, and the documented fallback paths. Single source of truth for every agent, skill and command that cites it — grep `handoff-protocol.md` for the consumers.

---

## #atomic-write

Atomic state.json write: **lock → read → merge → temp → fsync → rename → unlock**. An
mkdir-spinlock serializes the read-merge-rename window (macOS has no `flock(1)`), so legal
sibling overlap (parallel DVN tracks, DC+QA) cannot drop a patch to last-rename-wins.
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
cur=$(cat .context/state.json)                                   # 1. last-known-good
new=$(echo "$cur" | jq --argjson patch "$PATCH_JSON" '. * $patch')  # 2. merge in-memory (idempotent)
tmp=".context/.state.json.$$.${RANDOM}.tmp"                      # 3. temp in same dir ⇒ same FS
printf '%s' "$new" > "$tmp"
sync "$tmp" 2>/dev/null || sync || true                          # 4. fsync (best-effort)
mv -f "$tmp" .context/state.json                                 # 5. POSIX-atomic rename
rmdir "$lockdir" 2>/dev/null                                     # 6. release (also on EXIT trap)
```

`$RANDOM` in the temp name guards against PID reuse inside Task subagents (CR-7).

### Failure semantics

- Crash before step 3 — state.json untouched (last-known-good preserved).
- Crash between 3 and 5 — temp file orphaned. Cleanup on next worktask start: `rm -f .context/.state.json.*.tmp`. state.json untouched.
- Crash after 5 — state.json holds the new value; idempotent, so re-running the same patch is a no-op.
- Crash while holding the lock — the EXIT trap releases it; if the trap is skipped, the next writer breaks the dir once it is older than `STATE_LOCK_STALE_S`.

### Single-writer invariant

**One writer per stage KEY** — not one writer globally. Sibling overlap is legal (two stages,
or two DVN tracks writing distinct keys, may merge concurrently); the spinlock serializes their
windows so neither patch is lost. There is no "exactly one agent `in_progress`" requirement.
**Timeout ⇒ proceed unlocked + WARN**, never a silent exit-0 no-op.

### Lock implementation

`skills/worktask/scripts/state-patch.sh` — `atomic_merge()` plus `_lock_acquire` /
`_lock_release` / `_lock_break_if_stale`; the env knobs mirror the `DISK_MIN_GB` pattern. It is
the single merge implementation, inherited by the SubagentStop hook via delegation; when it is
absent `state-merge.sh` warns and exits 0 without merging.

---

## #frontmatter-schema

Every stage artifact (planning-N.md, architecture-N.md, …) MUST start with a YAML block between `^---$` markers. Token budget ≤200. Line budget ≤30.

**AR** and **TL** are optional (`skills/estimation-methodology/SKILL.md § Stage Inclusion Criteria`), so `architecture-N.md` / `coordination-N.md` may legitimately be absent. A frontmatter field referencing an absent stage's artifact MUST be omitted, never written as a dangling path.

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
        items: { $ref: '#/$defs/SweepStub' }   # closing elicitation sweep, the only item shape
      cross_session_ask:
        type: object
        description: >
          OPTIONAL. Legal only alongside verdict "blocked". Names WHO to ask and WHAT; the stage
          never sends it itself, because a subagent's reply from another session is delivered to
          the parent conversation and would never reach the stage. The orchestrator owns the send
          (resume.md § Reply routing).
        required: [to, question]
        properties:
          to: { type: string, maxLength: 200 }
          question: { type: string, maxLength: 160 }
      refs:
        type: object
        additionalProperties: { type: string }
constraints:
  total_lines: { max: 30 }
  total_tokens: { max: 200, tokenizer: cl100k_base-proxy }
```

### Schema — $defs: SweepItem and SweepStub

Closing elicitation sweep item, defined once for all three transports (contract:
`skills/shared/stage-contracts.md § Closing Elicitation Sweep`). The frontmatter and ledger
arrays carry `SweepStub`; the artifact body and the typed return carry the full `SweepItem`.

#### $defs — SweepItem (full item)

```yaml
# …continued: HandoffFrontmatter.$defs — also referenced by #handoff-schemas
$defs:
  SweepItem:
    type: object
    required: [id, summary, class, options, rationale]
    properties:
      id:        { type: string, pattern: '^sw-[A-Z]{2}[0-9]+-[0-9]+$' }
      summary:   { type: string, maxLength: 160 }
      rationale: { type: string, maxLength: 160 }
      stage:     { type: string }
      class:     { type: string, enum: [decision, escalate] }
      blocks_next_stage: { type: boolean }   # q9 carrier; see $defs/SweepStub
```

##### $defs — SweepItem.options

```yaml
# …continued: $defs.SweepItem.properties
      options:
        type: array
        minItems: 2
        maxItems: 4                 # the ask tool's per-question option ceiling
        items:
          type: object
          required: [label, detail]
          properties:
            label:       { type: string, maxLength: 24 }
            detail:      { type: string, maxLength: 120 }
            recommended: { type: boolean }
        # Exactly one recommended option, as a schema fact rather than prose.
        contains:    { type: object, required: [recommended], properties: { recommended: { const: true } } }
        minContains: 1
        maxContains: 1
```

#### $defs — SweepStub (frontmatter + ledger)

```yaml
# …continued: HandoffFrontmatter.$defs
$defs:
  SweepStub:
    type: object
    # `summary` is optional: the question text is read from the `ref` anchor body,
    # which check_sweep_ref_anchor guarantees exists (q10). `blocks_next_stage` is
    # mandatory — absent-vs-`false` is exactly the ambiguity that let the ledger and the
    # artifact disagree about the same item, so the field is stated, never inferred.
    required: [id, class, ref, blocks_next_stage]
    properties:
      id:      { type: string, pattern: '^sw-[A-Z]{2}[0-9]+-[0-9]+$' }
      summary: { type: string, maxLength: 160 }   # OPTIONAL; the artifact body is canonical
      stage:   { type: string }
      class:   { type: string, enum: [decision, escalate] }
      ref:     { type: string, description: "anchor into the emitting stage's own artifact" }
```

##### $defs — SweepStub, the routing and answer fields

```yaml
# …continued: $defs.SweepStub.properties
      # q9 carrier. Orthogonal to `class`: an escalate item may or may not block.
      # 2-element lattice false < true — the agent self-labels and the orchestrator may
      # raise false→true, never lower (ad4b's monotone idiom, reused). That lattice is over
      # LABELLERS: this stub and its facts.open_questions[] twin have one author and must
      # carry the SAME value, which handoff-harness.sh check_sweep_ledger enforces.
      blocks_next_stage: { type: boolean }
      status:            { type: string, enum: [open, resolved] }
      resolution:        { type: string, maxLength: 160 }
```

### Schema — subagents_spawned (B2 governance)

```yaml
# …continued: handoff.properties
      subagents_spawned:
        type: array
        maxItems: 5
        description: >
          OPTIONAL (B2). Sub-agents this stage dispatched, so DR/orchestrator see the
          fan-out without walking audit.jsonl. The cap of 5 is a policy tripwire — a
          stage needing more should re-split (TL). Nested spawns downshift a model tier
          and never run background-nested in a headless run.
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
          OPTIONAL (B4). Artifacts a fan-in stage (FN primarily) read IN FULL beyond
          their ≤200-token frontmatter, with why. Empty/absent is healthy; a long list
          is the tripwire that a producing stage's frontmatter is under-informative.
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
| PL | next_stage_focus, key_decisions, open_questions | files_touched | ok / blocked / escalate |
| AR | key_decisions, next_stage_focus, open_questions | files_touched, subagents_spawned | ok / blocked / escalate |
| TL | next_stage_focus, open_questions | key_decisions, files_touched | ok / blocked / escalate |
| DV | files_touched, next_stage_focus, open_questions | key_decisions, subagents_spawned | ok / blocked / escalate |
| DR | key_decisions (= findings), open_questions | files_touched | pass / fail |

#### Stages SR–ET

| Stage | Required (beyond base 4) | Optional | Verdict vocabulary |
|-------|--------------------------|----------|--------------------|
| SR | key_decisions (= findings), open_questions | files_touched | pass / fail |
| QA | files_touched (= tests added), key_decisions (= results), open_questions | — | go / no-go |
| DC | files_touched, open_questions | key_decisions | ok / blocked / escalate |
| RE | files_touched, key_decisions (= version), open_questions | — | ok / blocked |
| FN | next_stage_focus, files_touched, open_questions | key_decisions, deep_reads | ok / blocked |
| ST | key_decisions (= rationale), open_questions | — | approve / reject |
| IR | key_decisions (= root cause), next_stage_focus, open_questions | files_touched | ok / escalate |
| ET | key_decisions (= ethics findings), open_questions | — | pass / fail |

### Token budget

Frontmatter is the canonical compression form: downstream stages read this block instead of the full upstream artifact whenever they only need the verdict, decisions, or refs. Over ≤200 tokens, every downstream stage pays.

---

## Handoff Schemas {#handoff-schemas}

Canonical typed-return schemas — the single source of truth for the structured object a stage agent returns from its `Task()` dispatch (`skills/worktask/SKILL.md § Orchestrator Execution Loop` Step 6).

Two parallel channels, neither replacing the other: the typed return is *validated*, the `handoff:` frontmatter is the *cache-friendly on-disk* form. So even on the typed path every stage still mirrors to `state.json facts` and writes its `.context/<stage>-N.md` artifact with frontmatter (durability, human readability, F4 regeneration — `#frontmatter-schema`, `#fallback-paths`).

### Schema conventions

JSON Schema draft 2020-12. **Each stage's `verdict` enum MUST match that stage's row in `#frontmatter-schema § Per-stage required-field matrix`** — one verdict vocabulary per stage across both channels. The `required` set is the typed superset of that stage's frontmatter required fields (DR's `key_decisions (= findings)` becomes the typed `findings`/`blockers` arrays).

#### Conventions — the sweep field

Every stage schema requires `open_questions` — the closing elicitation sweep (`skills/shared/stage-contracts.md § Closing Elicitation Sweep`) is mandatory for all thirteen, and an empty array is the legal form for a stage with nothing to ask. Its `$ref: '#/$defs/SweepItem'` resolves against the single `$defs` block at `#frontmatter-schema § Schema — $defs: SweepItem and SweepStub`.

`cross_session_ask` is optional on every stage on the same terms — one shape, defined once above, legal wherever a stage can return `verdict: "blocked"`. Unlike `open_questions` it has no empty-array form: absent means the stage is not waiting on a peer session. 
###### Conventions — the $defs pointer is an obligation

The stage schemas below are printed without it, so the item shape is never restated per stage. Whatever passes a stage schema to `Task()` must inline that `$defs` block alongside it; **no shipped file implements that step today**, and nothing executes these schemas, so the `$ref` is a specification pointer rather than a live resolution. Stated as an obligation, not as an accomplished fact.

> **Cache-prefix note (binding, PRESERVE §4.1).** The schema is passed as a `Task()`/`agent()` **argument**, never inserted into preamble sections [1][2][4]. Adding schema dispatch therefore does NOT touch cache-prefix byte-identity (`#cache-prefix`).

### PLHandoff

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "PLHandoff",
  "type": "object",
  "required": ["verdict", "summary", "key_decisions", "next_stage_focus", "open_questions"],
  "properties": {
    "verdict": { "type": "string", "enum": ["ok", "blocked", "escalate"] },
    "summary": { "type": "string", "maxLength": 200 },
    "complexity": { "type": "integer", "minimum": 0, "maximum": 50 },
    "key_decisions": { "type": "array", "items": { "type": "string" } },
    "next_stage_focus": { "type": "string" },
    "open_questions": { "type": "array", "items": { "$ref": "#/$defs/SweepItem" } }
  }
}
```

### ARHandoff

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "ARHandoff",
  "type": "object",
  "required": ["verdict", "summary", "key_decisions", "next_stage_focus", "open_questions"],
  "properties": {
    "verdict": { "type": "string", "enum": ["ok", "blocked", "escalate"] },
    "summary": { "type": "string", "maxLength": 200 },
    "key_decisions": { "type": "array", "items": { "type": "string" } },
    "next_stage_focus": { "type": "string" },
    "open_questions": { "type": "array", "items": { "$ref": "#/$defs/SweepItem" } }
  }
}
```

### TLHandoff

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "TLHandoff",
  "type": "object",
  "required": ["verdict", "summary", "next_stage_focus", "open_questions"],
  "properties": {
    "verdict": { "type": "string", "enum": ["ok", "blocked", "escalate"] },
    "summary": { "type": "string", "maxLength": 200 },
    "next_stage_focus": { "type": "string" },
    "fanout": { "type": "array", "items": { "type": "string" } },
    "open_questions": { "type": "array", "items": { "$ref": "#/$defs/SweepItem" } }
  }
}
```

### DVHandoff

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "DVHandoff",
  "type": "object",
  "required": ["verdict", "files_modified", "build_status", "open_questions"],
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
    },
    "open_questions": { "type": "array", "items": { "$ref": "#/$defs/SweepItem" } }
  }
}
```

#### DVHandoff — architecture field notes

`architecture` is optional at the schema level but **required whenever `state.json` has a
`tasks.AR0` entry**, together with `refs.decisions`; both are omitted when AR did not run
(`stage-contracts.md#tpl-dv § Architecture reference contract`). Reference-resolution precedence,
shared by the harness, this schema and the DR rule: `refs.decisions`, then `architecture.ref`.
`handoff-harness.sh --validate-frontmatter <artifact> --state <state.json>` enforces it (warn-only
in 3.42.0, blocking under `--strict`) and its inverse guard warns when an `architecture-*`
reference appears without a `tasks.AR0` entry. `applied` is DV's truthful statement that AR's
decisions were followed; deviations go in `development-N.md ## decisions` with rationale, and DR
fails an undeclared one.

### DRHandoff

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "DRHandoff",
  "type": "object",
  "required": ["verdict", "findings", "blockers", "open_questions"],
  "properties": {
    "verdict": { "type": "string", "enum": ["pass", "fail"] },
    "findings": { "type": "array", "items": { "type": "string" } },
    "blockers": { "type": "array", "items": { "type": "string" } },
    "p2_only": { "type": "boolean" },
    "open_questions": { "type": "array", "items": { "$ref": "#/$defs/SweepItem" } }
  }
}
```

### SRHandoff

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "SRHandoff",
  "type": "object",
  "required": ["verdict", "findings", "blockers", "open_questions"],
  "properties": {
    "verdict": { "type": "string", "enum": ["pass", "fail"] },
    "findings": { "type": "array", "items": { "type": "string" } },
    "blockers": { "type": "array", "items": { "type": "string" } },
    "threat_model": { "type": "string" },
    "open_questions": { "type": "array", "items": { "$ref": "#/$defs/SweepItem" } }
  }
}
```

### QAHandoff

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "QAHandoff",
  "type": "object",
  "required": ["verdict", "tests_passed", "tests_failed", "open_questions"],
  "properties": {
    "verdict": { "type": "string", "enum": ["go", "no-go"] },
    "tests_passed": { "type": "integer", "minimum": 0 },
    "tests_failed": { "type": "integer", "minimum": 0 },
    "blocking_defects": { "type": "array", "items": { "type": "string" } },
    "open_questions": { "type": "array", "items": { "$ref": "#/$defs/SweepItem" } }
  }
}
```

### DCHandoff

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "DCHandoff",
  "type": "object",
  "required": ["verdict", "files_modified", "open_questions"],
  "properties": {
    "verdict": { "type": "string", "enum": ["ok", "blocked", "escalate"] },
    "files_modified": { "type": "array", "items": { "type": "string" } },
    "cross_references": { "type": "array", "items": { "type": "string" } },
    "open_questions": { "type": "array", "items": { "$ref": "#/$defs/SweepItem" } }
  }
}
```

### REHandoff

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "REHandoff",
  "type": "object",
  "required": ["verdict", "version", "files_modified", "open_questions"],
  "properties": {
    "verdict": { "type": "string", "enum": ["ok", "blocked"] },
    "version": { "type": "string" },
    "files_modified": { "type": "array", "items": { "type": "string" } },
    "changelog": { "type": "array", "items": { "type": "string" } },
    "open_questions": { "type": "array", "items": { "$ref": "#/$defs/SweepItem" } }
  }
}
```

### FNHandoff

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "FNHandoff",
  "type": "object",
  "required": ["verdict", "summary", "next_stage_focus", "open_questions"],
  "properties": {
    "verdict": { "type": "string", "enum": ["ok", "blocked"] },
    "summary": { "type": "string", "maxLength": 200 },
    "next_stage_focus": { "type": "string" },
    "files_modified": { "type": "array", "items": { "type": "string" } },
    "pr_url": { "type": "string" },
    "open_questions": { "type": "array", "items": { "$ref": "#/$defs/SweepItem" } }
  }
}
```

### STHandoff

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "STHandoff",
  "type": "object",
  "required": ["verdict", "key_decisions", "open_questions"],
  "properties": {
    "verdict": { "type": "string", "enum": ["approve", "reject"] },
    "key_decisions": { "type": "array", "items": { "type": "string" } },
    "follow_ups": { "type": "array", "items": { "type": "string" } },
    "open_questions": { "type": "array", "items": { "$ref": "#/$defs/SweepItem" } }
  }
}
```

### IRHandoff

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "IRHandoff",
  "type": "object",
  "required": ["verdict", "root_cause", "next_stage_focus", "open_questions"],
  "properties": {
    "verdict": { "type": "string", "enum": ["ok", "escalate"] },
    "root_cause": { "type": "string" },
    "next_stage_focus": { "type": "string" },
    "blast_radius": { "type": "string" },
    "open_questions": { "type": "array", "items": { "$ref": "#/$defs/SweepItem" } }
  }
}
```

### ETHandoff

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "ETHandoff",
  "type": "object",
  "required": ["verdict", "findings", "open_questions"],
  "properties": {
    "verdict": { "type": "string", "enum": ["pass", "fail"] },
    "findings": { "type": "array", "items": { "type": "string" } },
    "mitigations": { "type": "array", "items": { "type": "string" } },
    "open_questions": { "type": "array", "items": { "$ref": "#/$defs/SweepItem" } }
  }
}
```

### #schema-to-state-map

Each schema field maps onto the ledger (`#state-json-schema`) and the artifact anchor
(`#anchor-allow-list`). The map is channel-agnostic: the orchestrator applies it to a typed return
(`skills/worktask/SKILL.md § Orchestrator Execution Loop` Step 6), and populates the same targets
from the artifact's `handoff:` frontmatter when there is none (F2/F3).

#### Map — PL, AR, TL

| Schema field | state.json target | Artifact anchor |
|--------------|-------------------|-----------------|
| `PL.verdict` | `tasks.PL0.verdict` | planning-N.md (frontmatter) |
| `PL.complexity` | `tasks.PL0.complexity` | planning-N.md `## complexity` |
| `PL.key_decisions` | `facts.decisions[]` | planning-N.md `## stages` |
| `AR.verdict` | `tasks.AR0.verdict` | architecture-N.md `## decisions` |
| `AR.key_decisions` | `facts.decisions[]` | architecture-N.md `## decisions` |
| `TL.verdict` | `tasks.TL0.verdict` | coordination-N.md `## fan-out` |
| `TL.fanout` | (DV sub-task prompts; not a ledger field) | coordination-N.md `## fan-out` |

#### Map — DV

| Schema field | state.json target | Artifact anchor |
|--------------|-------------------|-----------------|
| `DV.verdict` | `tasks.DV0.verdict` | development-N.md `## deviations` (summary line) |
| `DV.files_modified` | `facts.files_modified` (union) | development-N.md `## files-changed` |
| `DV.tests_added` | `facts.tests_added` (union) | development-N.md `## tests-added` |
| `DV.build_status` | `tasks.DV0.status` derivation | development-N.md `## deviations` |
| `DV.decisions` | `facts.decisions[]` | development-N.md (inline) |

#### Map — DR, SR, QA, DC, RE

| Schema field | state.json target | Artifact anchor |
|--------------|-------------------|-----------------|
| `DR.verdict` | `tasks.DR0.verdict` + `facts.verdicts.DR` | developer-review-N.md `## verdict` |
| `DR.findings`/`blockers` | `facts.decisions[]` (= findings) | developer-review-N.md `## findings`/`## blockers` |
| `SR.*` | mirrors DR targets (`facts.verdicts.SR`) | security-review-N.md |
| `QA.verdict` | `tasks.QA0.verdict` + `facts.verdicts.QA` | testing-N.md `## verdict` |
| `QA.tests_passed`/`failed` | `facts.verdicts.QA` (count string) | testing-N.md `## results` |
| `DC.verdict` | `tasks.DC0.verdict` | documentation-N.md `## files-changed` |
| `DC.files_modified` | `facts.files_modified` (union) | documentation-N.md `## files-changed` |
| `RE.verdict` | `tasks.RE0.verdict` | release-N.md `## version` |
| `RE.version` | `facts.decisions[]` (version) | release-N.md `## version` |

#### Map — FN, ST, IR, ET, worktree

| Schema field | state.json target | Artifact anchor |
|--------------|-------------------|-----------------|
| `FN.verdict` | `tasks.FN0.verdict` | complete-summary-N.md `## summary` |
| `FN.pr_url` | `handoffs["RE→FN"]`/`DC→FN` (ref pointer) | complete-summary-N.md `## artifacts` |
| `ST.verdict` | `tasks.ST0.verdict` + `facts.verdicts.ST` | retrospective-N.md `## decision` |
| `IR.verdict` | `tasks.IR0.verdict` | incident-N.md `## root-cause` |
| `IR.root_cause` | `facts.decisions[]` | incident-N.md `## root-cause` |
| `ET.verdict` | `tasks.ET0.verdict` + `facts.verdicts.ET` | ethics-review-N.md `## verdict` |
| `DV.worktree_path` | `tasks.DV0.worktree.path` | development-N.md (frontmatter `worktree_path`) |
| `DV.worktree_branch` | `tasks.DV0.worktree.branch` | development-N.md (frontmatter `worktree_branch`) |

#### Additive-field writers

The v1 additive fields have **orchestrator-loop / hook writers**, not schema-mapped stage returns
(`facts.dispatched_agents[]`, `tasks.<ID>.last_error`, `tasks.<ID>.completed_via`,
`facts.capabilities` — `skills/worktask/SKILL.md § Orchestrator Execution Loop` steps 6/6.5).
Only `tasks.<ID>.worktree` maps from a stage artifact — the DV handoff frontmatter
`worktree_path`/`worktree_branch`, applied by `state-patch.sh` (rows above).

#### #facts-union

`facts.decisions[]`, `facts.open_questions[]`, `facts.files_modified` and `facts.tests_added` are
written by `state-patch.sh --facts '<json>'`, passed on the same self-patch call that lands the
stage's ledger row. It is the channel's ONLY scripted writer.

##### #facts-union — who writes open_questions

**`open_questions` is agent-written.** A stage's closing-sweep stubs reach the ledger only if that
stage passes them in its own `--facts` payload; the two are separate transports with
no derivation between them, so a stub written to frontmatter alone never reaches the FN gate.
`handoff-harness.sh --validate-frontmatter --state`, run at each stage completion
(`commands/worktask.md § Step B.1`), fails the stage when a sweep stub is missing from
`facts.open_questions[]`, when a stub present in both transports carries a different `class` or
`blocks_next_stage` in each, and when the ledger is unreadable. Two writers with no derivation
between them means id parity is not agreement: the fields are compared too, and a divergence is
reconciled by the agent rather than joined by the harness.

###### #facts-union — the merge table

The merge is a union, never `. * $patch`: jq object-merge REPLACES arrays, which is exactly how a
downstream stage silently dropped an upstream stage's entries.

| Array | Identity | Collision | Order |
|---|---|---|---|
| `decisions` | `.id` | last writer wins | survivor moves to the TAIL |
| `open_questions` | `.id` | monotone join (`_union_sweep`): `status` `open < resolved`, `resolution` never dropped | survivor moves to the TAIL |
| `files_modified`, `tests_added` | the string itself | duplicate dropped | first-seen position kept |

##### Ordering and idempotency

Tail placement for the keyed arrays is load-bearing: the B3 clamp keeps `.[-8:]`, so appending is
what makes "newest 8 survive" true after a union. Never sort (`unique_by` does) — that hands the
clamp an arbitrary 8.

Both shapes are idempotent: re-merging an already-merged payload leaves `state.json`
byte-identical, so a remediation loop may re-run its self-patch freely. A payload whose shape does
not match the table is rejected before the merge lock is taken. `--facts` applies ahead of the
completion merge, so facts still land when that merge short-circuits as idempotent.

#### Additive-field writers — facts.branch

Two writers, no stage agent among them: the orchestrator at `commands/worktask.md § Step 3c`, and
`refine-branch-target.sh` at § Step A.4b (at most once per run, pre-commit, ledger-only, no git
mutation).

The orchestrator's is an orchestrator-loop write: it parses the final `branch=<name>` stdout line
of `branch-name.sh` and stamps it directly — `branch-name.sh` never writes state.json (single
write chokepoint, `#atomic-write`). When that line is empty or non-conventional and
`target_branch=<name>` is not, the **target** is what gets stamped: the local rename can be
blocked (upstream tracked, target exists, host workspace) while the PR head is still the
pipeline's to name. See field notes — branch above.

---

## #state-json-schema

`.context/state.json` is the worktask ledger. Created by PL0; patched by every stage on completion; read by orchestrator before each delegation; embedded in the preamble as section [3]. Token budget ≤500.

JSON-Schema-style spec:

#### Ledger root

```yaml
$schema: https://json-schema.org/draft/2020-12/schema
title: WorktaskStateLedger
type: object
required: [version, worktask_id, plan_file, platform, run_index, tasks, facts, handoffs]
properties:
  version: { type: integer, const: 2 }
  worktask_id: { type: string, pattern: '^[a-z0-9\-]+$' }
  plan_file: { type: string }
  platform: { type: string, enum: [all, apple, android, web, systems, backend, ai] }  # canonical keys — skills/shared/platform-detection.md
  run_index: { type: integer, minimum: 0, default: 0 }
```

#### plan_file shape boundary

**`plan_file` shape boundary** (canonical statement; every other writer and reader site points
here) — `state.json.plan_file` holds a **workspace-relative path** (`.context/planning-N.md`);
`task.metadata.plan_file` holds a **bare basename** (`planning-N.md`). Both are legal. Every
reader MUST accept either: try the value as given, then its basename resolved against the
directory holding `state.json`.

#### metadata

```yaml
# …continued: WorktaskStateLedger.properties
  metadata:
    type: object
    description: "Mirror of the dispatch fields shell helpers need — they cannot read Task-System metadata."
    properties:
      workspace_path: { type: string, description: "REQUIRED from the seed onward — see field note below" }
      base_ref: { type: string }
      requires_screenshots: { type: boolean }
      test_mode: { type: string }
    additionalProperties: true
```

#### metadata.workspace_path

The absolute root of the tree this worktask is **assigned** to, seeded by
`commands/worktask.md` Step 3a on every run (`git rev-parse --show-toplevel`, else `pwd`) and
overwritten per-issue under `/megatask`. `dv-tree-preflight.sh` `resolve_assigned()` reads it as
rank 2 (after `--assigned`, before `$WORKSPACE_ROOT`).

Its absence is a defect, not a mode: every reader warns-and-proceeds on empty, so an unstamped
ledger disables the whole assigned-tree guard set at once. Rationale and the motivating failure:
`initialization-patterns.md § Seeded workspace_path`.

#### metadata.base_ref

The integration branch, mirrored by PL0 from `task.metadata.base_ref` so shell helpers (which
cannot read Task-System metadata) can reach it. Reader resolution order, highest first:
`$FN_BASE_REF`, `state.json .metadata.base_ref`, `workspace.json .git.base_branch`,
`git symbolic-ref refs/remotes/origin/HEAD`, then **unresolved** — there is no literal fallback;
readers report unresolved and degrade non-blocking. Implemented in
`skills/worktask/scripts/fn-preflight.sh` `resolve_base_ref`.

#### tasks

The **sole** stage ledger, keyed by numbered stage id (`[STAGE][N]` — `PL0`, `DV0`, `DV1`), the
same identity used in artifact names and handoff edges (`skills/shared/state-ledger.md`). Handoff
edges keep bare **stage codes** (`PL→AR`); only the ledger key is numbered.

```yaml
# …continued: WorktaskStateLedger.properties.tasks
  tasks:
    type: object
    propertyNames: { pattern: '^(PL|AR|TL|DV|DR|SR|QA|DC|RE|FN|ST|IR|ET)[0-9]+$' }
    additionalProperties:
      type: object
      required: [status, metadata]
      properties:
        status: { type: string, enum: [pending, in_progress, completed, blocked, skipped] }
```

##### tasks — routing & dependencies

```yaml
# …continued: WorktaskStateLedger.properties.tasks.additionalProperties.properties
        blocked_by:
          type: array
          items: { type: string }
          description: "Stage ids this task waits on, e.g. ['DV0','DV1']. Ready ⇔ every entry is completed."
        metadata:
          type: object
          description: "Routing + dispatch contract — schema in skills/shared/state-ledger.md § JSON Schema."
```

##### tasks — execution results

```yaml
# …continued: WorktaskStateLedger.properties.tasks.additionalProperties.properties
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

#### tasks — completed_via, last_error

```yaml
# …continued: WorktaskStateLedger.properties.tasks.additionalProperties.properties
        completed_via:
          type: string
          enum: [hook, step6_5, f3]
          description: "OPTIONAL — see field notes"
        last_error:
          type: object
          description: "OPTIONAL — see field notes"
          required: [class, at]
          properties:
            class: { type: string, enum: [transient, logic, missing_input, ambiguous_requirements, design_flaw, hard_constraint, exhausted] }
            partial: { type: boolean, description: "partial work was preserved on the errored return" }
            at: { type: string, format: date-time }
            ref: { type: string, description: "pointer into .context/errors/<agent>.md (e.g. #retry-1)" }
```

#### tasks — worktree

```yaml
# …continued: WorktaskStateLedger.properties.tasks.additionalProperties.properties
        worktree:
          type: object
          description: "OPTIONAL (DV primarily) — see field notes"
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

#### facts — open_questions

```yaml
# …continued: WorktaskStateLedger.properties.facts.properties
      open_questions:
        type: array
        maxItems: 12
        description: "Bounded (B3): newest 12 survive, `status: resolved` evicted first. Clamped at the single write chokepoint state-patch.sh atomic_merge() (AD-7) — every stage writes its closing sweep here. Matches eviction-order rule 2."
        items:
          # Mirrors $defs/SweepStub — the sweep stub is the only accepted item shape here
          # too, so the ledger and the frontmatter cannot disagree about what an entry is.
          type: object
          required: [id, class, ref, blocks_next_stage]
          properties:
            id: { type: string, pattern: '^sw-[A-Z]{2}[0-9]+-[0-9]+$' }
            summary: { type: string, maxLength: 160 }   # OPTIONAL; the artifact body is canonical
            stage: { type: string }                     # derived from the id when absent
```

##### facts — open_questions, the ledger-only fields

```yaml
# …continued: facts.open_questions.items.properties
            class: { type: string, enum: [decision, escalate] }
            ref: { type: string }
            # q9 carrier: this item is answered at its own stage boundary, not held
            # to the FN gate. See $defs/SweepStub for the raise-only rule. This value must
            # equal the frontmatter stub's — a divergence fails check_sweep_ledger.
            blocks_next_stage: { type: boolean }
```

###### facts — open_questions, the answer fields

```yaml
# …continued: facts.open_questions.items.properties
            # Read by eviction rule 2 and by the render, so an answered item is not
            # re-prompted on a resumed run. `open < resolved` is a MONOTONE join at
            # the union (state-patch.sh): a later write may raise, never downgrade.
            status: { type: string, enum: [open, resolved] }
            # Where a sweep ANSWER lands. Deliberately not facts.decisions[] —
            # stage-contracts.md § Closing Elicitation Sweep states why.
            resolution: { type: string, maxLength: 160 }
```

#### facts — verdicts, files_read

```yaml
# …continued: WorktaskStateLedger.properties.facts.properties
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
        description: "OPTIONAL (additive) — see field notes. Bounded (B3): 6 survive, launched-survive-first. Clamped in state-patch.sh atomic_merge() (AD-7)."
        items:
          type: object
          required: [stage, task_id, subagent_type, status]
          properties:
            stage: { type: string, description: "stage CODE (DV, DR, …)" }
            task_id: { type: string, description: "Ledger key (e.g. DV0) — the dedupe key" }
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
        description: "OPTIONAL (additive); probe cache for account-level hard-fails — see field notes"
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

Keys are `FROM→TO` stage-code pairs. PL0 sizes the stage set, so several stages have more than one
possible predecessor — the edge written is the one whose when-clause holds. A stage that never ran
never appears in an edge label; a "phantom edge" for an absent stage is a ledger defect.

The tables below are **exhaustive across all three pipelines** (standard, secure/full,
emergency). The emergency pipeline (`IR→DV→DR→QA→RE→FN`) has **no PL, AR or TL stage**, so DV's
predecessor there is `IR` and RE's is `QA`. Any predecessor not listed is not a legal edge; add a
row before writing one.

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
composes the key mechanically and knows none of the when-clauses. `USER` is a predecessor
**only** — it owns no artifact and is never a valid `--stage`.

#### #layer-1-fallback

Every stage agent's State Patch section points here. Three outcomes, in order.

1. **Exit 3** — `--prev` given, `--via` absent, no artifact resolved: the self-patch signature.
   The stage claims an artifact that is not on disk. Write it and re-run. If you cannot, use
   item 2 — `--allow-missing-artifact` only silences the error and patches **nothing**.
2. **The tool cannot run at all** (not granted, denied, not found). Do **NOT** skip silently.
   `Edit` `.context/state.json` directly: write both the `tasks.<ID>` completion entry and the
   `handoffs["<PREV>→<CODE>"]` edge, then record the failure under `metadata.pl_tooling_gaps`.
   The SubagentStop hook is **not** a substitute — it builds its args without `--prev`, so it
   repairs the stage entry and drops the edge.
3. **`jq` or `.context/state.json` genuinely absent** — skipping is correct here, and only here

#### Field notes — progress

OPTIONAL. Budget-aware checkpoint for multi-batch stages (currently DV), written after each sub-batch commit so a budget-exhausted agent leaves a resumable record instead of a progress narration. The orchestrator reads `next_batch` to resume where the stage stopped (`agents/developer.md § Budget-Aware Checkpointing`; `skills/worktask/SKILL.md § Orchestrator Execution Loop` step 4.7). Batch ids only — never diffs, file contents, or test output.

#### Field notes — completed_via

OPTIONAL (additive). Which enforcement layer stamped this stage `completed`: `hook` = SubagentStop delegation (Layer 2, `state-merge.sh` default); `step6_5` = orchestrator synchronous Step-6.5 (`STATE_MERGE_VIA=step6_5`); `f3` = orchestrator F3 minimal-patch fallback. **Absence encodes a Layer-1 agent self-patch** — the hook's idempotency check exits before writing when Layer 1 already landed. Observability only; no consumer branches on it.

#### Field notes — last_error

OPTIONAL (additive). Written by the orchestrator Step-6.5 errored-return branch (errors propagate with partial work) BEFORE routing to the retry matrix. `class` reuses the taxonomy in `agent-coordination § Retry / Escalate Matrix` — no new vocabulary. Dropped once the stage reaches `status: completed` (eviction rules).

#### Field notes — worktree

OPTIONAL (additive; DV primarily). Records WHICH worktree the stage ran in, not just `worktree: true`. Written by mapping the DV handoff frontmatter `worktree_path`/`worktree_branch` (`state-patch.sh`). Lets resume re-enter the exact worktree via `EnterWorktree(path)`, DR/QA run in the right dir, and FN carry PR context. The PR *head* comes from `facts.branch`, not here (disambiguation below). Kept through FN; dropped at archival.

#### Field notes — branch

OPTIONAL (additive). The worktask's **planned** working-branch name — the host-session branch as
`branch-name.sh` left it at the start of PL, whether it renamed it or found it already
conventional. Written at PL start, rewritten at most once at `commands/worktask.md § Step A.4b`
before any commit exists, and never by a **stage** (`skills/shared/git-conventions.md § Once-only
rule`). **This is the field FN uses as the pull-request head.** Reading the ledger rather than
shelling `git rev-parse` at FN time is what stops an external mid-run rename from silently
retargeting the PR: divergence surfaces as a mismatch instead of a differently-named PR. Not the
same field as `tasks.DV0.worktree.branch` (disambiguation below). Kept through FN; dropped at
archival.

##### Field notes — branch, divergence from the local branch name

`facts.branch` may legitimately differ from `git rev-parse --abbrev-ref HEAD` on the
`upstream_tracked` and `target_exists` arms, and inside a linked worktree under
`BRANCH_NAME_WORKTREE_RENAME=0` — there `branch-name.sh` keeps the host's local name and returns
the derived `target_branch=` for the PR head, so the host's branch↔workspace mapping survives
(`workspace-modes.md § Host mapping — updated, not preserved`). On the **default** worktree path
the branch is renamed and the two agree.

Divergence is **observed, not merely tolerated**: `fn-preflight.sh branch-divergence` classes it
`expected` or `third_party` and surfaces only `third_party` at the FN gate; its comparison base is
the `to` of the last `branch_renamed / ok` row, not this field. No reader may "repair" it by
re-deriving from the local branch — the ledger value is the planned name, and the PR head is what
it plans.

##### Field notes — branch, empty value

`branch-name.sh` prints `branch=` (empty) for a detached HEAD or not-a-git-repo — never the
literal `HEAD`, which is not a branch. FN MUST treat an empty `facts.branch` as "no planned name
to push under": skip the `git push -u origin HEAD:refs/heads/<facts.branch>` refspec entirely and
fall back to a plain `git push -u origin HEAD`. **On a detached HEAD that fallback fails loudly**
("The destination you provided is not a full refname") — an acceptable failure: no wrong target,
no silent error.

##### Disambiguation — `facts.branch` vs `tasks.DV0.worktree.branch`

Two fields, disjoint definitions, neither derived from the other:

| | `facts.branch` | `tasks.DV0.worktree.branch` |
|---|---|---|
| Meaning | **planned** host-session branch name | **observed** branch of the worktree DV ran in |
| Writer | orchestrator, from `branch-name.sh` stdout, at PL start; then `refine-branch-target.sh` at Step A.4b | `state-patch.sh`, from DV handoff `worktree_branch` |
| Written when | before any commit exists | after DV completes |
| Rewritten | at most once more, pre-commit (§ Step A.4b); never by a stage | per DV re-dispatch |
| FN uses for | the PR **head** | worktree re-entry context only |

##### Disambiguation — topology note

They are equal in the common topology where the session's workspace **is** the worktree
(`agents/developer.md § worktree_branch`), and differ when DV created a fresh
`.claude/worktrees/` worktree whose branch the tool named itself. **A mismatch is information,
not an error** — it tells FN the commits live somewhere other than the planned branch, exactly
what `fn-preflight.sh continuity` handles. No writer may copy one into the other; that copy is
what would make them a silent duplicate.

#### Field notes — goal

One-sentence worktask intent, populated by PL0 from the task description (or the issue title under `/megatask`). Read by stages needing the original intent without re-reading the plan file (AR sanity-checking architecture against requirements, FN composing the PR title). Single surface for this value — do not introduce a parallel one.

#### Field notes — files_read

Source files read by prior stages. Populated by DV; consumed by DR/QA, which SHOULD use `git diff <base>..HEAD -- <path>` instead of `Read <path>` for any file listed. Full reads stay permitted when the diff is insufficient. Absent ⇒ normal reads (backward-compat).

#### Field notes — dispatched_agents

OPTIONAL (additive). Writer: the orchestrator loop ONLY. One entry per `task_id` (NOT per stage — parallel DVN tracks share the stage code), replaced on re-dispatch; dispatch history stays in `audit.jsonl`. Read by resume (`resume.md` step 0) to reconcile against `claude agents --json --all`. No dispatch timestamp is stored (`claude agents` rows carry their own). Terminal entries (`status: completed|failed`) are eviction candidates.

#### Field notes — capabilities

OPTIONAL (additive). Probe cache for account-level hard-fails, so later stages do not re-hit the same error. Written by the orchestrator on first observed failure; model resolution consults it before any fable-tier dispatch. Example: `{ "fable_dispatch": "credit_blocked", "checked_at": "<ISO>" }` — Fable 5 is 1M-by-default but *dispatch* fails hard without 1M credits (model-selection.md).

### Eviction order on overflow

When state.json approaches the 500-token cap:

1. Drop `tasks.<ID>.artifact` paths for stages with `status=completed` once their `handoffs[FROM→TO]` string captures the essentials.
2. Drop `facts.open_questions` whose status is resolved (the `maxItems: 12` clamp applies the same preference automatically at every write).
3. Drop `facts.decisions` older than 2 stages back (keep current + previous stage decisions).
4. Drop `facts.files_read` entries whose `stage` is older than 2 stages back.

#### Eviction steps 5–8

5. Drop terminal `facts.dispatched_agents[]` entries (`status: completed|failed`) — live-agent reconciliation no longer applies; history persists in `audit.jsonl`.
6. Drop `tasks.<ID>.last_error` + `completed_via` once the stage is `completed` (error resolved; provenance was observability-only).
7. Keep `tasks.<ID>.worktree` through FN (PR context needs the branch); drop at archival.
8. NEVER store diffs, file contents, or test output. Fetch from git/disk on demand.

### PL0 seed (initial state) {#pl0-seed}

PL0 (or `commands/worktask.md` Phase 1) writes the initial ledger. The seed is **re-run aware**:
`plan_file` and `run_index` take the next free planning index `N` computed from any pre-existing
`.context/planning-*.md` (`0` on a fresh `.context/`) — hard-coding `0` would pin an old plan and
make PL0 overwrite `planning-0.md`. Use the canonical executable snippet in
`commands/worktask.md` Phase 1 step 3a verbatim; the JSON below shows only the resulting shape.

#### Seed shape (resulting JSON)

`plan_file` here is the **path** shape; task metadata carries the basename shape. See
the `plan_file` shape boundary under § state.json schema.

```json
{
  "version": 2,
  "worktask_id": "<from task metadata>",
  "plan_file": ".context/planning-${N}.md",
  "platform": "all",
  "run_index": ${N},
  "tasks": {
    "PL0": { "status": "in_progress" }
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

The seed includes `facts.dispatched_agents: []` (additive) so the orchestrator loop
appends/replaces per-`task_id` entries in place instead of lazily creating the array. The other
additive fields (`tasks.<ID>.completed_via`/`last_error`/`worktree`, `facts.capabilities`) are
written on demand and MUST NOT be seeded — their absence is meaningful (Layer-1 self-patch, no
error, no worktree record, no observed capability hard-fail).

**On a new PL run in an existing `.context/`**: the seed sets `run_index = N` up front; PL0 then
atomically resets `stages` to `{PL: in_progress}` and `facts.*` to empty. Historical run data
lives in the on-disk `<stage>-N.md` artifacts, not in state.json.

---

## #fallback-paths

Three documented degradation paths. The ledger itself is NOT one of them: `state.json` is
mandatory, and its absence is a hard failure rather than a recoverable mode.

| Path | Trigger | Behavior |
|------|---------|----------|
| F2 | state.json **present**, agent ignores it | No penalty. Agent reads the anchors it was given and writes its artifact. Orchestrator's hook patches state.json from frontmatter (or return text on F3). |

### Paths F3–F4

| Path | Trigger | Behavior |
|------|---------|----------|
| F3 | Agent writes artifact **without frontmatter** | Orchestrator logs WARN `frontmatter missing in <artifact>`. Derives minimal handoff: `{stage, verdict: ok, summary: <first 200 chars of return>, refs: {artifact: <path>}}`. Worktask proceeds. |
| F4 | state.json **corrupt** (invalid JSON or schema mismatch) | Back up to `.context/state.json.corrupt.<iso-ts>`. Rebuild the **skeleton only**, then recover **exactly the one stage being patched** by delegating to `state-patch.sh` unchanged. Audit row `state_repair` in `.context/logs/audit.jsonl`. Continue. |

#### F4 — partial recovery, by design {#f4-partial}

Three shipped behaviours, upheld on review rather than treated as defects:

- **Backup is `.context/state.json.corrupt.<iso-ts>`**, not `.bad.<unix-ts>` — sorting by name
  sorts by time, and the suffix says what happened.
- **The audit trail is a `state_repair` row in `.context/logs/audit.jsonl`**, not a separate
  `state-recovery.log`. One audit surface.
- **There is no completed-stage frontmatter walk.** The hook rebuilds the skeleton (including an
  empty `tasks: {}`) and recovers only the stage whose patch triggered the repair. A full walk was
  declined: it would be a second, divergent artifact parser alongside `state-patch.sh`'s.

#### F4 — consequences for readers {#f4-consequences}

A repaired ledger can legitimately show **fewer completed stages** than `.context/` contains —
earlier stages are not replayed. Reconstruct history from the artifacts, not the ledger.

**Fail-safe.** If the backup cannot be written (unwritable `.context/`), the repair aborts,
`state.json` is left **byte-identical**, no backup and no audit row are written, and the hook still
exits 0. Corrupt-and-untouched is the designed outcome; an unchanged ledger is not evidence the
hook failed to run.

#### The ledger is mandatory {#f1-fallback}

The handoff mode is anchor-based: a stage reads `.context/state.json` plus the anchors named in
`metadata.context_refs` (≥30% input-token reduction, cache-friendly preamble).

There is no whole-file fallback list. If `state.json` cannot be read, the stage stops and reports
rather than guessing at its inputs — silently losing both the cache benefit and the dependency
graph is worse than failing loudly. A read-only or unwritable `.context/` is an environment defect
to fix, not a mode to accommodate.

### F4 regeneration walk

Manual rebuild only — the hook never walks (`#f4-partial`). Runbook: `agents/workflow-engineer.md`.

1. Glob every canonical artifact basename (`#stage-artifact-map`) as `<basename>-*.md`.
2. Extract `handoff:` frontmatter from each (yq or fallback parser).
3. Sort by stage order: PL, AR, TL, DV, DR, SR, QA, DC, RE, FN, ST, IR, ET.
4. Seed state.json from PL0's frontmatter.
5. Per subsequent stage, merge `tasks.<ID>` and add `handoffs[FROM→TO]`.
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

Under TL fan-out the DV entry agent spawns one sub-agent per workstream; each writes only
`development-N-<stream>.md`, `<stream>` being the kebab slug the coordination plan assigned. The
entry agent alone merges them into the canonical `development-N.md` at fan-in. That merged file
stays the documented DR/QA input and the one the DV0 handoff and state patch describe — the
per-stream files are merge inputs, not handoff carriers.

### Run-index resolution

The same N is shared across all stages within a worktask run. `metadata.plan_file` pins the active plan; `metadata.run_index` (integer ≥ 0) resolves `<basename>-N.md` for every other stage. Full resolver and propagation algorithm: `skills/worktask/references/pl0-procedure.md § Plan File & Run Index Naming`.

### Alias basenames (resolution-only)

`state-patch.sh` accepts a second, search-only basename for three stages — DR `review`, QA `qa`,
FN `finalization` — in a sibling function, so `#stage-artifact-map` stays the single canonical name
per stage. Aliases are accepted, never written, and a canonical match outranks an alias match at
the same run index. Resolution order: primary@run_index → primary highest-N → alias@run_index →
alias highest-N. `AR` has no alias: `analyzing` (a prior naming generation) is deliberately
excluded so a stale file cannot answer for the current one. `USER` is a `--prev` value only — no
artifact, never a `--stage` or basename (edge tables: `USER→PL`, `USER→IR`).

---

## #cache-prefix

Anthropic prompt cache matches by **prefix-prefix equality**, not full-block equality, so the orchestrator builds the preamble in this order to maximize the byte-identical prefix shared across consecutive `Task()` calls within one `worktask_id`.

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

Documented in `skills/cost-optimization/SKILL.md`. Without the 1h flag the default 5-min TTL applies: retries inside a stage still save, cross-stage cache is lost between long-running stages.

### Lint

`skills/worktask/scripts/cache-lint.sh` asserts byte-identity of sections [1]+[2]+[4] across consecutive stages of the same `worktask_id`.

**Fixture-gated, not log-gated.** Prefix-lint consumes a `prompt-log.jsonl` (`{worktask_id, stage, prompt}` per line) that nothing here emits — the live harness assembles prompts in `benchmarklive/dispatch.py` but persists only stage stdout — so it is exercised by `cache-lint.sh --self-test` fixtures. CI runs exactly that mode on every PR (`.github/workflows/test.yml`), which gates the lint's own parser; no captured prompt is checked until an emitter exists. Treat this section as the spec the assembler must satisfy.

---

## #anchor-allow-list

All stage artifacts MUST contain exactly the H2 headings (kebab-case, no underscores, no spaces) listed below plus the one universal anchor. Anchor-lint runs twice: proactively via the managed `PostToolUse` hook (`hooks/anchor-preflight.sh`, shipped default-on in `.claude-plugin/plugin.json`) and again at the DR gate. Neither is a CI check: the lint job runs the four repo lints, and anchor-lint mode is deliberately not among them.

### Anchors — required in every artifact

One anchor is **universal**: mandatory in all thirteen stage artifacts on top of that stage's own row below.

- `## elicitation-sweep` — the closing elicitation sweep's canonical transport (`skills/shared/stage-contracts.md § Closing Elicitation Sweep`), the target the frontmatter and ledger stubs point at by `ref`. It carries either the full items or the explicit empty statement; a stage with nothing to ask still writes the heading. Enforced by `cache-lint.sh --anchor-lint` for all 13 stages, with no grace for older artifacts.

### Anchors — allowed but never required

These anchors are **allowed in every artifact and required in none**, so none retroactively fails an artifact written before it existed and none is reported as unexpected:

- `## rework-<N>` — the scope-addition re-entry section the DR gate reads (`agents/technical-lead.md`).
- `## re-review` — a review stage's second pass over reworked output, recorded beside its original findings rather than overwriting them.
- `## design-preview` — PL's Figma capture block, written only when the task carries a Figma URL (`skills/shared/figma-capture.md`); absent otherwise.
- `## test-strategy` — PL's optional test-strategy section; `pl0-procedure.md` never mandates it.

### Anchors — PL to DR

| Stage | Artifact | Mandatory H2 anchors |
|-------|----------|-----------------------|
| PL | planning-N.md | `## requirements`, `## acceptance-criteria`, `## scope`, `## out-of-scope`, `## risks`, `## complexity`, `## stages`, `## summary` |
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

1. H2 only. H1 is the artifact's title (exempt from anchor lint).
2. Kebab-case. No spaces, no underscores, no camelCase.
3. Anchor IDs come from GitHub-style slugify, but the H2 title MUST already be the kebab-case form — do not rely on slugify.
4. `key_decisions[].anchor` and `refs.*` MUST resolve to a real `## <slug>` heading in the target file. Enforcement is narrower than the rule: the handoff harness validates cross-file resolution **only for the AR→DV edge** (`--validate-frontmatter <development-N.md> --state <state.json>` checks the architecture reference's pattern and that the file exists next to the artifact). Every other `refs.*` entry is checked for key presence only, so a dangling target elsewhere is an author-owned contract violation the harness will not catch.

### Anchor Pre-Flight (PostToolUse hook)

The DR-gate lint is post-hoc — a missing anchor in `planning-N.md` surfaces only after AR/TL/DV have paid the full-file re-read cost. To catch omissions at the producing stage, anchor-lint also runs as a **managed plugin hook (shipped in `.claude-plugin/plugin.json`, default-on)**, not an opt-in registration. The managed PostToolUse `Write|Edit` entry invokes `${CLAUDE_PLUGIN_ROOT}/hooks/anchor-preflight.sh`, which gates on the artifact regex below and delegates matching writes to `skills/worktask/scripts/cache-lint.sh --anchor-lint`:

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

`anchor-preflight.sh` matches only the canonical artifact regex (`\.context/((planning|architecture|coordination|developer-review|security-review|testing|documentation|release|complete-summary|retrospective|incident|ethics-review)-[0-9]+|development-[0-9]+(-[a-z0-9]+)*)\.md$`); any other Write/Edit is a no-op. On a non-zero exit the producing agent sees the diagnostic and amends the file, so no downstream stage pays. `continueOnBlock` follows the same managed-hook discipline as the other entries (diagnostic surfaced; an unrelated write never blocked). In non-hook environments the DR-gate lint is the only safety net — there is no CI counterpart.

**Cost**: O(seconds) per artifact (greps H2 headings), one-shot per Write/Edit; net win once it prevents a single missed-anchor cascade (~2-3K tokens × N downstream stages).

---

## Future work (out of scope for v1)

`version` is the migration hook (currently `2` — the `tasks{}` ledger); future schema additions ship behind it. A relaxed-profile schema for cross-plugin agents is stubbed in `skills/cross-plugin-handoff/SKILL.md`. Compressing `.context/logs/audit.jsonl` and migrating historical `.context/` artifacts are both out of scope.
