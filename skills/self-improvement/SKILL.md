---
name: self-improvement
description: Use when the ST stage runs or post-delivery user edits need classifying. Capture user edits at ST stage, classify them, propose scoped updates to agents/skills/commands that participated in the worktask; human-in-the-loop, never auto-applies.
effort: medium
version: 0.1.0
---

# Self-Improvement Skill

Retrospective + diff-based learning at the ST (Stakeholder) stage. Detects user modifications made after the last agent commit, maps each diff to the owning agent/skill/command **only if it participated in this worktask's context**, and writes per-item proposals to `.context/learnings.md` for user approval.

## Invocation

- **Automatic (production path):** mandatory step in `agents/stakeholder.md § Acceptance Review Procedure`, after the Decision step — every ST completion.
- **Manual (tooling/iteration):** `/improve-yourself` (`commands/improve-yourself.md`, `--since` / `--target`) — dry-runs and proposal iteration between worktasks.

Both paths run the same pipeline and produce the same `.context/learnings.md`.

**Pre-conditions:** `.context/complete-summary-N.md` exists (automatic — FN finished, N from `run_index`) OR a `--since <ref>` baseline (manual); plus at least one stage-agent commit (automatic) OR reachable commits in the diff range (manual).

**Post-conditions:** `.context/learnings.md` with N proposals, or short-circuit — log "no learnings", produce no artifact.

## Procedure

Execute the five steps in order. If any step fails, write the failure to `.context/logs/self-improve-<ts>.log` and abort cleanly — never leave a half-written `learnings.md`.

### Step 1 — Build Used-in-Context Set

**Goal:** a deduped list of agents/skills/commands that actually participated in this worktask; Step 4 **filters** proposals against it.

**Sources, in precedence order:** (1) `.context/state.json` `tasks{}` — `metadata.agent` + `metadata.embedded_commands` of every `status: completed` entry; (2) `.context/*.md` artifact metadata (`metadata.agent`, `Agent:` trailers, authorship blocks); (3) commit trailers (`Agent:`, `Stage:`) in `<first-stage-commit>..HEAD`; (4) `.context/logs/audit.jsonl` — hook and helper-script participation. Exact query shapes: `references/target-mapping.md § Data Sources for "Used-in-Context Set"`.

**Output:** one plugin-root-relative path per line under section `## Context Set` of `.context/logs/self-improve-<ts>.log`. Deduplicate on path; skip paths not present on disk.

#### Step 1 — two rules the set depends on

**Source 4 is not optional.** Sources 1–3 name *agents*, so a hook or a bundled script can drive most of a run and still be invisible to the retrospective — the class of participant that most often needs correcting after delivery.

**Paths resolve against the plugin root, never the process cwd.** Every corpflow asset lives under `$CLAUDE_PLUGIN_ROOT` while the pipeline runs from the worktask's own repo. `scripts/build-context-set.sh` resolves the root per `skills/shared/plugin-root-resolution.md`, emits root-relative paths, and reports on stderr when it cannot resolve one.

**Source 4's shapes bind Step 4.** Basenames resolve against `hooks/`, `hooks/lib/`, `scripts/` and `skills/*/scripts/`, so those are the paths hooks and helpers enter the set under. Step 4 must be able to emit each shape as a target; a shape it cannot produce makes that part of the set unmatchable and silently drops every edit to it.

### Step 2 — Detect User Changes

**Goal:** diffs introduced **after** the last stage-agent commit — baseline `$AGENT_SHA` (that commit) → head = working tree (`HEAD` + uncommitted edits merged).

**"Agent commit"** = authored by an agent, or a conventional worktask prefix (`feat`, `fix`, `refactor`, …) **and** `Stage:` / `Agent:` trailers; **fallback** — the newest commit predating any uncommitted user edits.

**Run** `bash ${CLAUDE_PLUGIN_ROOT}/skills/self-improvement/scripts/detect-user-changes.sh`: returns a newline-delimited `path\tlines_added\tlines_removed` table plus a full unified diff piped to `.context/logs/self-improve-<ts>.diff`.

**Short-circuit:** empty table → write the log with `Result: no-changes`, skip to the closing counts call (§ Step 5b — record the four counts), return.

### Step 3 — Classify Each Change

Assign every hunk exactly one of six categories — `tone` (reworded, same meaning), `structure` (sections added/removed/reordered), `accuracy` (fact corrections: numbers, names, technical claims), `completeness` (new content fills a gap), `style` (formatting, naming, indentation), `domain-knowledge` (project-specific rules the agent did not know) — plus `high | medium | low` confidence. Low-confidence items go to Deferred in `learnings.md`, never the active approval list. Decision tree, confidence heuristics, per-category proposal shapes and worked examples: `references/change-categories.md`.

### Step 4 — Map + Filter to Owning Target

**Goal:** every classified change maps to exactly one owning file, **then** is filtered against Step 1's used-in-context set.

#### Canonical Script

```
LOG_OUT=<log_path> bash ${CLAUDE_PLUGIN_ROOT}/skills/self-improvement/scripts/map-and-filter.sh \
  --changes=<step2-tsv> \
  --context-set=<step1-out> \
  [--dv-agent=<resolved-dv-agent-path>]
```

Output: TSV rows `<path>\t<rule_num>\t<target>\t<lines_added>\t<lines_removed>` per KEPT change; discards appended to `$LOG_OUT` under `## Out-of-Context Discards`. `rule_num` (1–17) gives auditability — it matches the row numbers in `references/target-mapping.md`. Rules 5, 13 and 16 need ledger/stage-gate inputs the script cannot reach: pass the resolved DV agent via `--dv-agent`, else it defaults to `agents/developer.md`.

#### Mapping Rules (apply first match)

Happy path: a prompt file (`agents/*.md`, `skills/**/SKILL.md`, `commands/*.md`) maps to itself (self-edit signal); `.context/<stage-artifact>-N.md` to its producing agent (lookup via `skills/shared/stage-contracts.md`); source code to this worktask's DV agent (`metadata.agent` — platform-specific or `developer`); docs (`README.md`, `docs/**`) to `agents/technical-writer.md`; no match discards, logged only. Full 17-rule spec, platform-aware resolution and edge cases: `references/target-mapping.md`.

**Filter:** drop any item whose target is not in the used-in-context set, logging it under `## Out-of-Context Discards`. We only learn from agents that actually worked on this task; an edit to an unrelated file is noise here.

### Step 5 — Emit `.context/learnings.md`

Write it per `references/retrospective-template.md` — header block, What Worked / What the User Changed / Proposed Updates / Deferred / Out-of-Context Discards, approval footer. Follow that template rather than improvising: it fixes proposal ordering and the sub-bullets each numbered, independently tickable `- [ ]` proposal carries.

**Versioning:** a proposal that modifies a file's frontmatter MUST instruct prompt-engineer to bump `version: x.y.z` — semver minor for additions, patch for wording tweaks.

### Step 5b — Append to the label dataset

**Goal:** retain each classified edit as a durable failure label, recorded under plugin data outside the repo and never committed. `learnings.md` lives under the gitignored `.context/`, so labels are otherwise discarded when the run ends — and a user correcting delivered output is domain-expert ground truth, what `evals/failure-taxonomy.md` and any future evaluator get built from.

**Runs regardless of approval:** only the *proposal* is gated on approval; a rejected proposal is still evidence the output needed changing.

#### Step 5b — invocation

**Input:** one TSV row per KEPT change, joining Step 3 (category, confidence) to Step 4 (target) on `path`:

```
<path>\t<target>\t<category>\t<confidence>\t<added>\t<removed>\t<summary>
```

##### Append command

```
bash ${CLAUDE_PLUGIN_ROOT}/skills/self-improvement/scripts/append-labels.sh \
  --worktask-id=<id> --run-index=<n> --changes=<tsv> \
  --plugin-data=${CLAUDE_PLUGIN_DATA} \
  --count-out=.context/logs/self-improve-<ts>.appended
```

Appends to the label dataset, idempotent on a content hash of `(worktask_id, run_index, path, added, removed, summary)`. The same edit recurring in a later worktask appends a new label — recurrence is the frequency signal. `--count-out` receives the appended row count for the closing counts call.

##### Aggregation and statistics

```
bash ${CLAUDE_PLUGIN_ROOT}/skills/self-improvement/scripts/label-stats.sh --plugin-data=${CLAUDE_PLUGIN_DATA} [--min-count=<n>]
```

It flags targets and categories at or above `--min-count` (default 3) and reports progress toward the 100-row `failure-taxonomy.md` gate in `evals/README.md`.

##### Where the dataset lives

`append-labels.sh`, `label-stats.sh` and `pipeline-counts.sh` resolve it in this order:

1. `--dataset=<file>`, as given.
2. `--plugin-data=<dir>`, used only when the value is non-empty, free of `$`, and absolute.
3. The `CLAUDE_PLUGIN_DATA` environment variable, under the same checks. It is set for hooks and tests but absent from the Bash tool environment, which is why the body passes the flag.
4. Fallback: `${CLAUDE_PROJECT_DIR:-.}/evals/failure-labels.jsonl`, with a stderr notice.

An empty value or the unsubstituted literal token counts as unset. Under plugin data the labels go to `<dir>/self-improvement/failure-labels.jsonl` and the counts to `<dir>/self-improvement/pipeline-counts.jsonl`.

##### An empty join is a silent no-op

**A non-empty context set is necessary, not sufficient.** The pipeline is four stages — `build-context-set.sh` → `detect-user-changes.sh` → `map-and-filter.sh` → `append-labels.sh` — and any of three conditions empties the run: zero context paths, zero changed paths, or a join that matches nothing because no mapping rule emits the targets the set actually holds. All three look identical to "the user made no edits". `pipeline-counts.sh` records the surviving count at each of the four stages, so a zero-row result is never read as a clean run.

#### Step 5b — privacy and opt-out

Rows carry counts and the one-line summary only, never diff bodies; redact the summary as you would `learnings.md`. `SELF_IMPROVE_LABELS=0` makes the label append a no-op; the counts call still runs. Labels are recorded under plugin data, outside the repo: tell the user they are being recorded the first time this runs. When the scripts print the fallback notice, the labels land in the repo's `evals/failure-labels.jsonl` instead — relay that notice to the user.

#### Step 5b — record the four counts

Run this last on every path, including short-circuit runs, `SELF_IMPROVE_LABELS=0` runs and runs without `jq`:

##### Counts recording command

```
bash ${CLAUDE_PLUGIN_ROOT}/skills/self-improvement/scripts/pipeline-counts.sh \
  --worktask-id=<id> --run-index=<n> \
  --context-set=<step1-out> --changes=<step2-tsv> --mapped=<step4-tsv> \
  --appended=.context/logs/self-improve-<ts>.appended \
  --plugin-data=${CLAUDE_PLUGIN_DATA}
```

##### Counts semantics and output

The script counts rows in the stage output files, so no count comes from prose. An absent input file counts 0. Under plugin data it appends one `self-improve-counts/v1` row to `pipeline-counts.jsonl` with fields: `ts`, `worktask_id`, `run_index`, `stage`, `context_paths`, `changed_paths`, `mapped_rows`, `appended_rows`, `labels_enabled`, `dataset_source`. On the fallback rung or with `--dry-run`, no row is written. Stderr always carries progress information; the row is the authoritative record.

## Output Contract

### Core output artifacts

| Path | Required? | Purpose |
|------|-----------|---------|
| `.context/learnings.md` | Only if in-scope changes detected | User-approvable proposals |
| `.context/logs/self-improve-<YYYYMMDD-HHMMSS>.log` | Always — including short-circuit runs | Run log: context set, decisions, discards |
| `.context/logs/self-improve-<YYYYMMDD-HHMMSS>.diff` | Only if changes detected | Full unified diff for audit |

### Label dataset outputs

| Path | Required? | Purpose |
|------|-----------|---------|
| `<plugin-data>/self-improvement/failure-labels.jsonl` | Only if in-scope changes detected | Append-only label dataset, outside the repo (Step 5b) |
| `<plugin-data>/self-improvement/pipeline-counts.jsonl` | Always, except on fallback rung or under `--dry-run` | Stage counts per run (Step 5b) |
| `.context/logs/self-improve-<YYYYMMDD-HHMMSS>.appended` | Whenever `append-labels.sh` runs | Appended row count |
| `${CLAUDE_PROJECT_DIR:-.}/evals/failure-labels.jsonl` | Fallback rung only | Repo label dataset; counts to stderr |

Filename grammar follows `skills/logging-conventions/SKILL.md`.

## Hand-off to prompt-engineer

After user approval (orchestrated per `commands/worktask.md`), each checked item goes to `prompt-engineer`, which applies the edit, bumps `version:` in frontmatter, and creates one commit per proposal. Protocol: `agents/prompt-engineer.md § Self-Improvement Patch Application`.

## Constraints (DO NOT)

- DO NOT auto-apply any proposal. Human approval is mandatory.
- DO NOT propose changes to files outside the used-in-context set.
- DO NOT react to low-confidence items — park them in Deferred.
- DO NOT edit the target file directly; this skill only proposes.
- DO NOT commit `.context/learnings.md` (lives under the already-gitignored `.context/`).
- DO NOT put secrets, tokens, or diff bodies in `learnings.md` or the label dataset — counts and a redacted one-line summary only.
- DO NOT skip Step 5b because the user rejected the proposals; the observation stands on its own.

## Cross References

- `skills/shared/stage-contracts.md` — ST output contract; Step 4 producer lookup
- `skills/logging-conventions/SKILL.md` — log path rules
- `skills/shared/five-whys.md` — Deferred items that recur across worktasks
- `commands/optimize-agent.md` — scoring rubric for proposal confidence
- `commands/prompt-audit.md` — health-score format
- `commands/improve-yourself.md` — manual entry point (`--since`, `--target`, `--dry-run`, `--apply`)
- `agents/stakeholder.md` — invokes this skill (automatic path at ST)
- `agents/prompt-engineer.md` — applies approved proposals
- `commands/worktask.md` — orchestrator wires the approval loop after ST
- `tests/shell/skills/{detect-user-changes,build-context-set,map-and-filter,append-labels,label-stats,pipeline-counts}.bats` — executable behavior fixtures for the pipeline scripts
