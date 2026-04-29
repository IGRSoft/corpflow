# Retrospective Template — learnings.md

Canonical shape of `.context/learnings.md`. The self-improvement skill fills in each block; out-of-context diffs never reach this file.

## Header Block

```markdown
# Self-Improvement Learnings — <workflow_id>

**Generated:** <UTC timestamp>
**Diff range:** <agent_sha>..HEAD
**In-context targets:** <count>
**Proposals:** <count> active, <count> deferred
```

## Section 1 — What Worked (mandatory)

Agents whose output survived user review unchanged. Positive signal (4Ls: "Liked").

```markdown
## What Worked

- `agents/product-manager.md` — `<plan_file>` (e.g. `planning-0.md`) accepted without edits
- `agents/qa-engineer.md` — testing.md accepted without edits
```

If no agents fit → write `- (none — every in-scope artifact was edited)`.

## Section 2 — What the User Changed (mandatory if any diff)

Flat bullet list, one bullet per diff hunk. Keep it short — detail belongs in the Proposals section.

```markdown
## What the User Changed

- `.context/development.md` L42–55 — `tone` — reworded approach summary
- `.context/development.md` L102 — `accuracy` — corrected API name
- `src/Models/User.swift` L18 — `domain-knowledge` — added Sendable conformance
```

## Section 3 — Proposed Updates (mandatory if any in-scope change)

Numbered checklist. **Each item is independently approvable.** The orchestrator reads which boxes the user ticked and passes only those to `prompt-engineer`.

```markdown
## Proposed Updates

- [ ] **#1 — agents/developer.md — `completeness` — confidence: high**
  - **Observed:** user added Sendable conformance to Swift 6 actor types in 2 files
  - **Proposed edit:** append to Constraints (DO NOT):
    ```markdown
    - DO NOT define types used across actor boundaries without `Sendable` conformance
    ```
  - **Target location:** `agents/developer.md` line 18 (end of Constraints block)
  - **Version bump:** `version:` minor (new constraint)
  - **Rationale:** Swift 6 strict concurrency requires Sendable; repeated correction signals missing domain knowledge.

- [ ] **#2 — skills/workflow/SKILL.md — `structure` — confidence: medium**
  - **Observed:** user restructured the Orchestrator Execution Loop header hierarchy
  - **Proposed edit:** (diff block showing new hierarchy)
  - **Target location:** lines 44–72
  - **Version bump:** patch
  - **Rationale:** cleaner cognitive load; user preference confirmed once.
```

**Ordering:** sort proposals by `confidence desc` then `category` then `target path asc`. High-confidence items appear first so the user approves the strongest signals quickly.

## Section 4 — Deferred (Low Confidence)

Observational only. The user can skim but is not asked to act.

```markdown
## Deferred (Low Confidence)

- `.context/planning-0.md` L8 — single-word wording tweak (`approach` → `strategy`). Confidence: low. Park until N≥2 similar tweaks accumulate across workflows.
```

If cross-workflow accumulation ever ships (v2), items escalate from Deferred into Proposed when pattern count ≥ 2.

## Section 5 — Out-of-Context Discards

Count only. The full list lives in `.context/logs/self-improve-<ts>.log` so `learnings.md` stays user-focused.

```markdown
## Out-of-Context Discards

12 diffs discarded (not mapped to an in-context target). See `.context/logs/self-improve-20260420-172301.log` § Discards.
```

## Footer — Approval Flow

Always include this block so the user knows what happens next.

```markdown
---

## How to approve

1. Check the boxes next to any Proposed Updates you accept.
2. Leave unchecked any you reject.
3. Commit nothing — the orchestrator reads this file, hands checked items to `prompt-engineer`, and each applied proposal becomes its own commit with a version bump.
4. Rollback-safe: revert any applied proposal via `git revert <sha>`.
```
