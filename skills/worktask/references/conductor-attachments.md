# Conductor Attachments — FN Templates

Templates and emission rules for the two Conductor-convention files the FN
stage writes into `.context/attachments/`. Read by `agents/project-manager.md`
(FN Stage) and validated by `skills/shared/stage-contracts.md` (FN row).

## Why these files exist

Conductor (the parallel-agents Mac app) injects them into a new session on a UI action — **Create PR** → `.context/attachments/PR instructions.md`, **Request Review** → `.context/attachments/Review request.md`. Absent, Conductor uses its generic defaults: no DR/QA verdicts, no conventional-commit type, no resolved base branch, no link to `.context/complete-summary-N.md`. FN writes both so the FN agent follows `PR instructions.md` for `gh pr create` (the single source of truth, identical to a later Conductor re-trigger) and later Conductor-driven actions inherit worktask-aware prompts.

## When to write

**Two writers, idempotent**, both sourcing from this template:

| Writer | When | Data quality |
|--------|------|-------------|
| Orchestrator pre-gate | Before the FN gate's `return` (gated path only; bypass falls through to delegation) | Best-available: DR/QA verdicts from upstream artifacts, git state at gate time |
| FN agent post-approval | Before `gh pr create` (`agents/project-manager.md § FN Stage`) | Final: same sources, fresher post-commit git state |

### Writer 1 — Orchestrator pre-gate (tool-explicit)

Step 1 of the FN gate's *Effect (checkpoint)* list, not a separate phase — full procedure in `skills/worktask/references/fn-gate.md § Pre-gate Conductor-attachments writer` (gate detection stays in `skills/worktask/SKILL.md § FN Gate`). Fires on the gated path only, wrapped in `test -f` trip-wires (Effect steps 1 and 6) so a skipped or partially-completed run cannot reach `return` silently.

### Writer 2 — FN agent post-approval

In `agents/project-manager.md § FN Stage`, immediately before `gh pr create`:

```bash
mkdir -p .context/attachments
```

Then `Write` both files from the templates below, overwriting from scratch — no skip, no merge; a pre-seed is expected and never assumed current.

**Post-write verify (mirror of Writer 1's gate trip-wire)** — immediately after both `Write` calls:

```bash
test -f ".context/attachments/PR instructions.md" && test -f ".context/attachments/Review request.md" && echo OK
```

On `OK`, run `gh pr create` from `PR instructions.md`. Otherwise abort FN with `handoff.verdict: blocked`, write the cause to `.context/errors/project-manager.md`, and do NOT proceed — a PR without the attachments leaves Conductor in the degraded state the trip-wire exists to prevent.

### Known emission-rule defects

#### How to fix one safely

`skills/worktask/scripts/attachments-preseed.sh` reproduces the three defects below verbatim rather than smoothing them — its contract is fidelity to this document, and `attachments-preseed.bats` P2/P12 re-derive their expectations from these blocks at run time. **Never fix one by editing a fenced template body alone**: document and script change in the same commit.

#### The three defects

1. **`<N>` is overloaded** — uncommitted-file count in parts 1 and 3, **issue number** in part 7's
   `Closes #<N>` checklist row. Token substitution cannot tell them apart; the script renders
   correctly only by matching surrounding text. Fix: rename the checklist token to `<ISSUE>`.
2. **No blank line before `## 2. Push`** — part 3 is the only fenced body ending without a
   trailing blank line, so concatenating it with part 3b runs the two sections together.
3. **Authoring comments are shipped** — `<!-- If issue ref present: … -->` and the two
   `<!-- One bullet per … -->` notes sit *inside* the fenced bodies, so "no separators added or
   removed" emits them into the real attachment. Harmless but near-certainly unintended; this
   section is the only thing that can decide to strip them.

## Data sources

### Git & branch state

| Field | Source |
|-------|--------|
| Current branch | `git rev-parse --abbrev-ref HEAD` |
| Branch (PR head) | `state.json § facts.branch` — **planned** name from PL start. **Validate first** (`^[A-Za-z0-9._/-]+$` — `project-manager.md § Validating facts.branch`). Push: `git push -u origin HEAD:refs/heads/<facts.branch>` (topology-independent) |
| Target / base branch | One resolution order, highest first, ending in unresolved with no literal fallback — canonical in `handoff-protocol.md § metadata.base_ref`, implemented by `fn-preflight.sh` `resolve_base_ref` |
| Uncommitted change count | `git status --porcelain \| wc -l` |
| Upstream tracked? | `git rev-parse --abbrev-ref --symbolic-full-name @{u}` (non-zero exit = no upstream) |

### Plan, issue & verdict fields

| Field | Source |
|-------|--------|
| Conventional-commit type | `state.json § facts.goal` via `branch-lib.sh:derive_type` (`git-conventions.md § Branch Naming`); defaults to `feature`. Not the plan — no template emits `## Goal` |
| Plan document (other fields) | `FN0.metadata.plan_file` (basename; `handoff-protocol.md § plan_file shape boundary`), else newest `.context/planning-*.md` |
| Issue ref | `workspace.json § issue_number` (milestone mode) or `metadata.issue_ref` from PL0; else omit |
| DR verdict | First "Approval Status" line in `.context/developer-review-N.md` (N from `run_index`) |
| QA verdict | First "GO/NO-GO" line in `.context/testing-N.md` (N from `run_index`) |
| DR concerns | Lines under `## Issues Found` in `.context/developer-review-N.md` |
| QA blocking defects | Lines under `## Results` flagged blocking in `.context/testing-N.md` |
| Worktask ID | `PL0.metadata.worktask_id` |
| Timestamp | ISO 8601, UTC, second precision |

### Probe & placeholder fields

| Field | Source |
|-------|--------|
| Existing PR URL (idempotency probe) | `gh pr view --json url,state -q '"\(.state) \(.url)"' 2>/dev/null` (empty = no PR). Resolved by the consumer agent at execute time, NOT by the FN-stage writer |
| `<CLOSES_LINE>` placeholder | `Closes #<ISSUE>` if `ISSUE_REF` present, else empty line |
| `<ISSUE_LINE>` placeholder | `- Issue: #<ISSUE> — include \`Closes #<ISSUE>\` in the PR body to auto-close on merge.` if `ISSUE_REF` present, else empty string (line omitted) |
| `<UPSTREAM_LINE>` placeholder | `Upstream tracking: origin/<BRANCH>.` if `git rev-parse @{u}` succeeds, else `No upstream branch yet — use \`git push -u origin <BRANCH>\`.` |

## Template — `PR instructions.md`

**Emission rule**: the attachment file content is the concatenation of the fenced bodies of the `Template part N` blocks below, in order (part 1 first), with no separators added or removed — template text is byte-equivalent to the original single template.

#### Template part 1

~~~markdown
<!-- Generated by corpflow FN stage. worktask_id: <WORKTASK_ID>, ts: <ISO_TS> -->

The corpflow worktask has finished and is ready to ship.

- Branch: <BRANCH>  →  Target: origin/<BASE_BRANCH>
- Uncommitted changes: <N>
- Upstream: <UPSTREAM_LINE>
- Suggested commit type: **<TYPE>** (per `rules/git-conventions.md`, Conventional Commits 1.0.0)
- Worktask summary: `.context/complete-summary-N.md` (N = `run_index`; fallback newest `.context/complete-summary-*.md`)
<ISSUE_LINE>
<!-- If issue ref present: "- Issue: #<ISSUE> — include `Closes #<ISSUE>` in the PR body to auto-close on merge." -->

The user requested a PR. Follow the steps below.

~~~

#### Template part 2

~~~markdown
## 0. Skill precedence

If you have any skill related to creating PRs, invoke it now. Instructions there take precedence over this file.

## 1. Pre-flight (don't skip)

- Check for an existing PR: `gh pr view --json url,state -q '"\(.state) \(.url)"' 2>/dev/null`. If one exists and is **OPEN**, push new commits to its branch and **stop** — do not open a duplicate. Report the existing URL.
- `git fetch origin <BASE_BRANCH>` and confirm no merge conflicts: `git merge-tree $(git merge-base HEAD origin/<BASE_BRANCH>) HEAD origin/<BASE_BRANCH>` (empty output = clean).
~~~

#### Template part 3

~~~markdown
- Self-review the diff with `mcp__conductor__GetWorkspaceDiff` (start `stat: true`, then drill into hot files). Look for: debug prints, commented-out code, hardcoded secrets/keys, unintended large binaries, unrelated formatting churn. If any are found, fix them and add a follow-up commit before continuing — do not push junk.
- Confirm working tree is clean: `git status --porcelain` should be empty (or only intentional WIP). The worktask reports `<N>` uncommitted changes; reconcile any drift before pushing.
- The branch was already named once, at the start of planning (`skills/shared/git-conventions.md § Branch Naming`) — nothing renames it here.
~~~

#### Template part 3b

~~~markdown
## 2. Push

- Validate `facts.branch` (`^[A-Za-z0-9._/-]+$`; empty/failed → plain push), then push under the ledger name: `git push -u origin HEAD:refs/heads/<facts.branch>`. Otherwise, if upstream is already set to that name, plain `git push`.
- Do **NOT** amend or squash existing commits unless the user explicitly asks. The worktask's commit boundaries carry stage context.

~~~

#### Template part 4

~~~markdown
## 3. Open the PR

Run `gh pr create --base <BASE_BRANCH>` with:

- **Title** ≤ 72 chars, format `<TYPE>[scope]: <Summary>` (matches commit subject style; see `rules/git-conventions.md`). Suggested type: **<TYPE>**.
- **Body** via HEREDOC (preserves formatting). Use this skeleton — fill from `.context/complete-summary-N.md`:

  ```markdown
  ## Motivation
  <Why this change exists — link to the user need / bug / requirement>

  ## Changes
  - <Change 1, user-visible language>
  - <Change 2>

  ## Test plan
  - [ ] <How a reviewer can verify locally — commands, URLs, screenshots>

  <!-- ## Visual evidence — inserted here when UI changed (see below) -->

  ## Notes
  <Risks, follow-ups, deliberate non-goals. Omit section if empty.>

  Closes #<ISSUE>
  ```

~~~

#### Template part 5

~~~markdown
  **Visual evidence section** (between `## Test plan` and `## Notes`): on a UI-change run, run `skills/worktask/scripts/attach-visual-evidence.sh --emit pr` and insert its stdout verbatim. The helper self-gates — it prints the `## Visual evidence` block (hosted image refs + manifest reference) when `metadata.requires_screenshots == true` AND captures exist, and prints **nothing** otherwise (flag false / no captures). Insert the block only when stdout is non-empty; never hand-author the section. Image hosting reuses the publish-helper host tiers; the manifest reference is path-free, so no `.context/` path reaches the body. Invoke it unconditionally; the empty-stdout case omits the section. `fn-preflight.sh pr-body` verifies the helper's `visual_evidence_pr_emitted` row for **this** run and blocks a body that dropped the block — a hand-authored body will not pass, and it then runs `pr-body-lint.sh` (warn-only) over the sanitised body.

~~~

#### Template part 5b — degraded visual evidence

~~~markdown
  **If captures exist but none embedded**, the helper prints a `NOTICE` on stderr and writes a `visual_evidence_degraded` audit row carrying `captured`, `embedded` and a `reason`. Surface that row at the FN gate — it means reviewers will see no images. `reason=probe_timeout` or `token_invalid` is fixed by exporting **`GH_SESSION_TOKEN`**, which lets the `gh image` uploader skip browser-cookie extraction (slow, and blocking on a Keychain prompt when non-interactive).

~~~

#### Template part 6

~~~markdown
  The trailing `Closes #<ISSUE>` line is **REQUIRED** on its own line whenever an issue number is resolvable (see FN validator in `agents/project-manager.md § FN Stage`). Multiple closes lines (`Closes #A`, `Closes #B`) are permitted for PRs that close several issues. Omit ONLY when no issue number can be resolved from any source — in that case the FN audit writes one `pr_issue_link: deferred` row and the PR proceeds without the line.

- Cover **all** commits in the workspace diff vs. `origin/<BASE_BRANCH>`, not just the most recent commit.
- Keep the body grounded in observable facts from the diff/summary — no speculation, no marketing language.

~~~

#### Template part 7

~~~markdown
### PR-body checklist (must hold before `gh pr create`)

- [ ] Title ≤ 72 chars, `<TYPE>[scope]: <Summary>` format
- [ ] `## Motivation`, `## Changes`, `## Test plan` sections present
- [ ] **`Closes #<N>` line present on its own line when issue number is resolvable** (regex match: `(?im)^(?:Closes|Fixes|Resolves)\s+#\d+\s*$`)
- [ ] Body reflects ALL workspace-diff commits, not only HEAD

~~~

#### Template part 8

~~~markdown
## 4. Failure escape hatches

- `gh: command not found` or `gh auth status` failure → stop and ask the user to authenticate; do not fall back to `git request-pull` or web URLs.
- Push rejected (non-fast-forward) → run `git fetch && git log HEAD..@{u} --oneline`; ask the user before force-pushing.
- `gh pr create` exits non-zero with an unfamiliar error → capture the stderr verbatim in your reply and ask the user.

If any other step fails, ask the user — do not improvise destructive recovery.
~~~

## Template — `Review request.md`

**Emission rule**: as above — concatenate the fenced bodies of the `Template part N` blocks below in order, no separators added or removed.

#### Template part 1

~~~markdown
<!-- Generated by corpflow FN stage. worktask_id: <WORKTASK_ID>, ts: <ISO_TS> -->

# Review guidelines

You are reviewing code produced by an automated multi-stage worktask that
already passed an internal Developer Review (DR) and QA. Your job is to
catch what those stages missed — not to re-do their work.

## Worktask context

- Worktask ID: <WORKTASK_ID>
- Branch: <BRANCH>  →  Target: origin/<BASE_BRANCH>
- DR verdict: <DR_VERDICT>   (`.context/developer-review-N.md`)
- QA verdict: <QA_VERDICT>   (`.context/testing-N.md`)
- Summary: `.context/complete-summary-N.md` § Summary

~~~

#### Template part 2

~~~markdown
## Scope

Review only **changes introduced by this branch** vs. `origin/<BASE_BRANCH>`.
Do not flag pre-existing issues visible in surrounding context lines, even
if real — they belong in a separate PR.

## Focus areas (auto-extracted)

DR concerns the worktask surfaced but did not block on:
<DR_CONCERNS_BULLETS>
<!-- One bullet per "Issues Found" line; "(none flagged)" if empty -->

QA observations worth a second look:
<QA_NOTES_BULLETS>
<!-- Non-blocking notes from testing.md; "(none)" if empty -->

These are starting points, not the full scope. Do not simply restate them
as findings — DR already saw them. Use them to direct attention.

~~~

#### Template part 3

~~~markdown
## When to flag a finding

A finding must satisfy ALL of:

1. Meaningfully impacts accuracy, performance, security, or maintainability.
2. Discrete and actionable.
3. **Introduced by this branch** (not pre-existing in the file).
4. The original author would fix it if they were aware.
5. Does not rely on unstated assumptions about the codebase.
6. Not just an intentional design choice.

If nothing meets the bar, return zero findings. Inventing issues to look
thorough wastes the author's time and erodes trust in the review.

~~~

#### Template part 4

~~~markdown
## Severity (use exactly these three)

- **blocking** — correctness, security, data-loss, or breaking-change risk. Must fix before merge.
- **important** — meaningful quality issue (perf, maintainability, missing test for new code path). Should fix; discuss if you disagree.
- **nit** — minor improvement. Author may close without action.

Severity must match impact. Do not inflate to be heard.

~~~

#### Template part 5

~~~markdown
## Do NOT flag

- Style or formatting if the linter passes.
- Naming preferences without a concrete readability problem.
- "Have you considered <alternative pattern>" when current code works and is consistent with the codebase.
- Pre-existing issues unrelated to this branch.
- Missing tests for code paths the branch did not touch.
- Speculative future scaling concerns with no current impact.
- Items DR or QA already explicitly accepted (see Focus areas above).

~~~

#### Template part 6

~~~markdown
## Comment style

- One comment per distinct issue. Use a multi-line range only when needed.
- Use ` ```suggestion ` blocks ONLY for concrete replacement code; preserve exact leading whitespace; no commentary inside the block.
- One paragraph max per comment. Inline code via backticks; code blocks ≤ 3 lines.
- Tone: matter-of-fact, not accusatory; not flattering. No "Great job", no "Thanks for".
- Prefer questions over commands when uncertain ("What happens if `items` is empty?" beats "Add a length check.").

~~~

#### Template part 7

~~~markdown
## Getting the diff

Prefer `mcp__conductor__GetWorkspaceDiff` (start with `stat: true`, then request specific files).

Fallback when the tool is unavailable:

```bash
MERGE_BASE=$(git merge-base origin/<BASE_BRANCH> HEAD)
git diff $MERGE_BASE HEAD       # committed changes
git diff HEAD                    # uncommitted work in progress
```

Review both outputs together. No need to mention which strategy you used.

If the diff exceeds ~1000 changed lines, focus on the highest-risk files
first (auth, persistence, public APIs, config). Note in your summary that
review was scoped due to size — do not silently skip files.

~~~

#### Template part 8

~~~markdown
## Output

1. **Inline comments first** — post via `mcp__conductor__DiffComment`, one per unique issue, severity prefix (e.g. `**blocking**: …`).
2. **Then a top-level summary**:

```
## Review summary
Verdict: <approve | approve-with-nits | request-changes>
Findings: <B blocking, I important, N nits>

### #1 <Short title>  (<severity>)
<One-paragraph explanation>
File: <path>:<line>

### #2 <Short title>  (<severity>)
…
```

If verdict is **approve** with zero findings, write only:

```
## Review summary
Verdict: approve. No findings meet the bar.
```
~~~

## Idempotency

Both files are overwritten on every FN run; the header comment (`worktask_id` + `ts`) carries traceability without append-only history. Stage agents that run after FN MUST NOT modify these files.

## Cross references

- `agents/project-manager.md § FN Stage` — the writer
- `skills/shared/stage-contracts.md` § FN row — validation
- `skills/worktask/SKILL.md § FN Gate` — pre-FN summary (separate artifact, not these files)
- `rules/git-conventions.md` — commit format referenced from `PR instructions.md`
