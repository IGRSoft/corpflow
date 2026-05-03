---
name: self-improvement
description: Capture user post-delivery edits at ST stage, classify them, and propose scoped updates to agents/skills/commands that participated in the workflow. Human-in-the-loop; never auto-applies.
effort: medium
---

# Self-Improvement Skill

Retrospective + diff-based learning invoked automatically at the ST (Stakeholder) stage. Detects user modifications made after the last agent commit, maps each diff to the owning agent/skill/command **only if it participated in this workflow's context**, and writes per-item proposals to `.context/learnings.md` for user approval.

## Invocation

Two entry points:

1. **Automatic (production path):** mandatory step in `agents/stakeholder.md § Acceptance Review Procedure` after the Decision step. Runs on every ST completion.
2. **Manual (tooling/iteration):** via `/improve-yourself` command (see `commands/improve-yourself.md`). Useful between workflows, for dry-runs, or to iterate on proposals with `--since <ref>` and `--target` flags.

Both paths execute the same pipeline and produce the same `.context/learnings.md`.

Pre-conditions:
- `.context/complete-summary-N.md` exists (automatic path — FN stage finished; N from `run_index`) OR a `--since <ref>` baseline (manual path)
- Current branch has at least one commit authored by a stage agent (automatic) OR reachable commits in the diff range (manual)

Post-conditions:
- Either `.context/learnings.md` written with N proposals, or
- Short-circuit: skill logs "no learnings" and returns without producing an artifact

## Procedure

Execute the five steps in order. Each step has explicit inputs and outputs. If any step fails, write the failure to `.context/logs/self-improve-<ts>.log` and abort cleanly — never leave a half-written `learnings.md`.

### Step 1 — Build Used-in-Context Set

**Goal:** produce a deduped list of agents/skills/commands that actually participated in this workflow. Proposals will be **filtered** against this list in Step 4.

**Data sources (precedence order):**
1. `TaskList` → for each task with `status: completed`, read `metadata.agent` + `metadata.embedded_commands`
2. `.context/*.md` artifact metadata sections (look for `metadata.agent`, `Agent:` trailers, authorship blocks written by upstream stages)
3. Commit trailers on commits in range `<first-stage-commit>..HEAD` (look for `Agent:`, `Stage:` trailers if present)

**Output:** write to `.context/logs/self-improve-<ts>.log` under section `## Context Set`:
```
agents/product-manager.md
agents/developer.md
agents/qa-engineer.md
skills/workflow/SKILL.md
skills/logging-conventions/SKILL.md
commands/workflow.md
```

**Tie-breaker:** deduplicate on file path. Skip any path not present on disk.

### Step 2 — Detect User Changes

**Goal:** identify diffs introduced **after** the last stage-agent commit.

**Definition of "agent commit":** a commit whose author is an agent or whose message begins with one of the conventional workflow prefixes (`feat`, `fix`, `refactor`, etc.) **and** whose trailer chain includes `Stage:` / `Agent:` metadata, **or** — fallback — the most recent commit on the branch that predates any uncommitted user edits.

**Range to diff:**
- Baseline: SHA of the last agent commit (call it `$AGENT_SHA`)
- Head: working tree (`HEAD` + uncommitted edits merged)

**Run:** `scripts/detect-user-changes.sh` returns a newline-delimited `path\tlines_added\tlines_removed` table plus a full unified diff piped to `.context/logs/self-improve-<ts>.diff`.

**Short-circuit:** if table is empty → write `.context/logs/self-improve-<ts>.log` with `Result: no-changes`, skip remaining steps, return.

### Step 3 — Classify Each Change

**Goal:** assign a category to every hunk in the diff so proposals can be grouped and explained.

**Taxonomy (see `references/change-categories.md` for examples):**

| Category | Signal | Proposal shape |
|----------|--------|----------------|
| `tone` | Reworded sentences with same meaning | Prompt wording change |
| `structure` | Added/removed/reordered sections | Add/remove section in agent template |
| `accuracy` | Fact corrections (numbers, names, technical claims) | Add constraint or example |
| `completeness` | New content added that fills a gap | Add capability/responsibility |
| `style` | Formatting, naming, indentation | Style-guide reference or constraint |
| `domain-knowledge` | Introduces project-specific rules the agent did not know | Add domain reference or glossary |

**Confidence:** assign `high | medium | low`. Low-confidence items go into a "Deferred" section in `learnings.md`, not the active approval list.

### Step 4 — Map + Filter to Owning Target

**Goal:** every classified change gets mapped to exactly one owning agent/skill/command file, **then filtered** against the used-in-context set from Step 1.

**Mapping rules (apply first match):** full table in `references/target-mapping.md`.

1. **Direct edit to a prompt file** (`agents/*.md`, `skills/**/SKILL.md`, `commands/*.md`) → target is that file itself (self-edit signal).
2. **Edit to `.context/<stage-artifact>-N.md`** → target is the agent that produced that artifact (look up via stage-contracts.md: any `planning-N.md` (or legacy `planning.md`) → product-manager, `development-N.md` → developer, etc.).
3. **Edit to source code file** → target is the DV-stage agent for the current workflow (`developer` or whichever platform-specific agent was assigned in `metadata.agent`).
4. **Edit to docs (`README.md`, `docs/**`)** → target is `technical-writer` (DC stage).
5. **No match** → discard, logged only.

**Filter:** after mapping, **drop** any item whose target path is NOT in the used-in-context set. Log discarded items under `## Out-of-Context Discards` in the log file.

**Rationale:** we only learn from agents that actually worked on this task. A user edit to an unrelated file is noise from this workflow's perspective.

### Step 5 — Emit `.context/learnings.md`

**Goal:** write the retrospective artifact with per-proposal checklist items the user can tick to approve.

**Template:** `references/retrospective-template.md`. Structure (4 blocks, inspired by 4Ls):

```markdown
# Self-Improvement Learnings — <workflow_id>

## What Worked
- <bullet list of agents whose output needed zero user edits>

## What the User Changed
<per-change list, one bullet per hunk: path + category + 1-line summary>

## Proposed Updates
<numbered checklist; each item is an approvable proposal>

- [ ] **#1 — agents/developer.md — `completeness`**
  - Observed: user added a "Swift 6 strict concurrency" constraint
  - Proposed edit: append bullet to Constraints (DO NOT) section:
    `- DO NOT ignore @Sendable requirements in actor-isolated code`
  - Confidence: high
  - Target lines: 18–21

- [ ] **#2 — skills/workflow/SKILL.md — `structure`**
  - ...

## Deferred (Low Confidence)
<items that scored low confidence; observational, not actionable yet>

## Out-of-Context Discards
<count only, full list in .context/logs/self-improve-<ts>.log>
```

**Versioning note:** each proposal block that modifies a file's frontmatter MUST instruct prompt-engineer to bump `version: x.y.z` (semver minor for additions, patch for wording tweaks).

## Output Contract

Artifacts produced by this skill:

| Path | Required? | Purpose |
|------|-----------|---------|
| `.context/learnings.md` | Only if in-scope changes detected | User-approvable proposals |
| `.context/logs/self-improve-<YYYYMMDD-HHMMSS>.log` | Always | Run log: context set, decisions, discards |
| `.context/logs/self-improve-<YYYYMMDD-HHMMSS>.diff` | Only if changes detected | Full unified diff for audit |

Filename grammar follows `skills/logging-conventions/SKILL.md`.

## Hand-off to prompt-engineer

After user approval (handled by orchestrator in `commands/workflow.md`), each checked item in `learnings.md` is passed to the `prompt-engineer` agent, which:
1. Reads the proposal block
2. Applies the edit to the target file
3. Bumps `version:` in frontmatter
4. Creates one commit per applied proposal with message `<type>(<scope>): apply self-improvement — <category>`

See `agents/prompt-engineer.md § Self-Improvement Patch Application` for the apply protocol.

## Constraints (DO NOT)

- DO NOT auto-apply any proposal. Human approval is mandatory.
- DO NOT propose changes to files outside the used-in-context set.
- DO NOT react to low-confidence items — park them in Deferred.
- DO NOT edit the target file directly; this skill only proposes.
- DO NOT commit `.context/learnings.md` to the repository (lives under `.context/`, already gitignored per project policy).
- DO NOT include secrets/tokens from diffs in `learnings.md`; redact before writing.

## Test Scenarios (for skill-creator validation)

1. **Zero-change:** agent commits, user approves without edits → no `learnings.md` written; log records `Result: no-changes`.
2. **In-context change:** user edits `.context/development-N.md` wording → proposal targets `agents/developer.md` with `tone` category.
3. **Out-of-context change:** user edits `agents/security-reviewer.md` (but workflow was not `--secure`, so SR did not run) → discarded, no proposal surfaced. Discard logged.
4. **Multi-file change:** user edits both a source file (maps to developer) and `README.md` (maps to technical-writer, if DC ran) → two proposals.
5. **Low-confidence:** wording change of ≤2 words flagged `tone/low` → placed in Deferred.
6. **Short-circuit robustness:** skill invoked but `complete.md` missing → log failure, abort, do not create `learnings.md`.

## Cross References

- `skills/shared/stage-contracts.md` — ST output contract (lists `learnings.md` as optional)
- `skills/logging-conventions/SKILL.md` — log path rules
- `skills/shared/five-whys.md` — reuse for Deferred items that recur across workflows
- `commands/optimize-agent.md` — reuse scoring rubric for proposal confidence
- `commands/prompt-audit.md` — reuse health-score format
- `commands/improve-yourself.md` — manual entry point with `--since`, `--target`, `--dry-run`, `--apply` flags
- `agents/stakeholder.md` — invokes this skill (automatic path at ST)
- `agents/prompt-engineer.md` — applies approved proposals
- `commands/workflow.md` — orchestrator wires approval loop after ST completes

## Common Mistakes

1. **Proposing changes to unused agents** — always filter against the used-in-context set (Step 4).
2. **Treating every wording tweak as a proposal** — low-confidence items belong in Deferred, not the active list.
3. **Skipping the log file** — even short-circuit runs must write a log so the user can audit why no proposals appeared.
4. **Committing `.context/learnings.md`** — this file is ephemeral; it belongs only in the workspace during the approval cycle.
5. **Applying without version bump** — every applied proposal must bump the target file's `version` frontmatter (or add it if absent).
