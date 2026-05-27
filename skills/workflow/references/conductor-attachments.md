# Conductor Attachments — FN Templates

Templates and emission rules for the two Conductor-convention files the FN
stage writes into `.context/attachments/`. Read by `agents/project-manager.md`
(FN Stage) and validated by `skills/shared/stage-contracts.md` (FN row).

## Why these files exist

Conductor (the parallel-agents Mac app) injects attachments from
`.context/attachments/` into new sessions when the user clicks UI actions:

| Conductor action | File injected |
|------------------|---------------|
| **Create PR**       | `.context/attachments/PR instructions.md` |
| **Request Review**  | `.context/attachments/Review request.md` |

If absent, Conductor falls back to its built-in defaults — generic, with no
workflow context (no DR/QA verdicts, no conventional-commit type, no resolved
base branch, no link to `.context/complete-summary-N.md`).

The FN stage produces both files so:

1. The FN agent reads `PR instructions.md` and follows it for `gh pr create`
   (single source of truth — same template the user sees if they re-trigger
   the action via Conductor later).
2. Subsequent Conductor-driven actions in the same workspace inherit
   workflow-aware prompts.

## When to write

**Two writers, idempotent**: the orchestrator writes both files PRE-FN-GATE
(so Conductor sees them even if the user never approves the gate). The FN
agent re-writes them with final data after gate approval. Both writers source
from this template — single source of truth.

| Writer | When | Data quality |
|--------|------|-------------|
| Orchestrator pre-gate | Immediately before the FN gate's `return` in `skills/workflow/SKILL.md` (gated path only; bypass path falls through to delegation) | Best-available: DR/QA verdicts from upstream artifacts, git state at gate time |
| FN agent post-approval | In `agents/project-manager.md § FN Stage`, before `gh pr create` | Final: same sources but fresher git state (post-commit) |

### Writer 1 — Orchestrator pre-gate (tool-explicit)

Runs as **Step 1 of the *Effect, in order* list** in `skills/workflow/SKILL.md § FN Gate` — not as a separate phase. The full procedure lives in `§ Pre-gate Conductor-attachments writer` (same FN Gate section). Three separate `test -f` trip-wires (Effect steps 2, 3, 6) wrap this writer so a skipped or partially-completed run cannot reach `return` silently. Fires on the gated path only. Goal: Conductor sees workflow-aware files even if the user never approves the gate.

### Writer 2 — FN agent post-approval

In `agents/project-manager.md § FN Stage`, immediately before `gh pr create`:

```bash
mkdir -p .context/attachments
```

Then `Write` both files using the templates below, overwriting any pre-seed from Writer 1 (no skip, no merge — always overwrite from scratch). Pre-existing files are expected and normal; do not assume the pre-seed is current.

**Post-write verify (mirror of Writer 1's gate trip-wire)** — immediately after both `Write` calls:

```bash
test -f ".context/attachments/PR instructions.md" && test -f ".context/attachments/Review request.md" && echo OK
```

On `OK`, run `gh pr create` using the data from `PR instructions.md`. On failure, abort FN with `handoff.verdict: blocked`, write the cause to `.context/errors/project-manager.md`, and do NOT proceed to `gh pr create` — opening a PR without the attachments leaves Conductor in the degraded state Writer 1's trip-wire was designed to prevent.

## Data sources

| Field | Source |
|-------|--------|
| Current branch | `git rev-parse --abbrev-ref HEAD` |
| Target / base branch | `workspace.json § git.base_branch` (milestone/worktree mode); else `git symbolic-ref refs/remotes/origin/HEAD` (repo default) |
| Uncommitted change count | `git status --porcelain \| wc -l` |
| Upstream tracked? | `git rev-parse --abbrev-ref --symbolic-full-name @{u}` (non-zero exit = no upstream) |
| Conventional-commit type | Derived from `.context/<plan_file> § Goal` (resolve via `FN0.metadata.plan_file`; fallback: newest `.context/planning-*.md`) — feat/fix/refactor/perf/docs/chore/test/ci/build/style; falls back to `feat` |
| Issue ref | `workspace.json § issue_number` (milestone mode) or `metadata.issue_ref` from PL0; else omit |
| DR verdict | First "Approval Status" line in `.context/developer-review-N.md` (N from `run_index`) |
| QA verdict | First "GO/NO-GO" line in `.context/testing-N.md` (N from `run_index`) |
| DR concerns | Lines under `## Issues Found` in `.context/developer-review-N.md` |
| QA blocking defects | Lines under `## Results` flagged blocking in `.context/testing-N.md` |
| Workflow ID | `PL0.metadata.workflow_id` |
| Timestamp | ISO 8601, UTC, second precision |
| Existing PR URL (idempotency probe) | `gh pr view --json url,state -q '"\(.state) \(.url)"' 2>/dev/null` (empty = no PR). Resolved by the consumer agent at execute time, NOT by the FN-stage writer |
| `<CLOSES_LINE>` placeholder | `Closes #<ISSUE>` if `ISSUE_REF` present, else empty line |
| `<ISSUE_LINE>` placeholder | `- Issue: #<ISSUE> — include \`Closes #<ISSUE>\` in the PR body to auto-close on merge.` if `ISSUE_REF` present, else empty string (line omitted) |
| `<UPSTREAM_LINE>` placeholder | `Upstream tracking: origin/<BRANCH>.` if `git rev-parse @{u}` succeeds, else `No upstream branch yet — use \`git push -u origin <BRANCH>\`.` |

## Template — `PR instructions.md`

````markdown
<!-- Generated by igrsoft FN stage. workflow_id: <WORKFLOW_ID>, ts: <ISO_TS> -->

The igrsoft workflow has finished and is ready to ship.

- Branch: <BRANCH>  →  Target: origin/<BASE_BRANCH>
- Uncommitted changes: <N>
- Upstream: <UPSTREAM_LINE>
- Suggested commit type: **<TYPE>** (per `rules/git-conventions.md`, Conventional Commits 1.0.0)
- Workflow summary: `.context/complete-summary-N.md` (N = `run_index`; fallback newest `.context/complete-summary-*.md`, then legacy `.context/complete-summary.md`)
<ISSUE_LINE>
<!-- If issue ref present: "- Issue: #<ISSUE> — include `Closes #<ISSUE>` in the PR body to auto-close on merge." -->

The user requested a PR. Follow the steps below.

## 0. Skill precedence

If you have any skill related to creating PRs, invoke it now. Instructions there take precedence over this file.

## 1. Pre-flight (don't skip)

- Check for an existing PR: `gh pr view --json url,state -q '"\(.state) \(.url)"' 2>/dev/null`. If one exists and is **OPEN**, push new commits to its branch and **stop** — do not open a duplicate. Report the existing URL.
- `git fetch origin <BASE_BRANCH>` and confirm no merge conflicts: `git merge-tree $(git merge-base HEAD origin/<BASE_BRANCH>) HEAD origin/<BASE_BRANCH>` (empty output = clean).
- Self-review the diff with `mcp__conductor__GetWorkspaceDiff` (start `stat: true`, then drill into hot files). Look for: debug prints, commented-out code, hardcoded secrets/keys, unintended large binaries, unrelated formatting churn. If any are found, fix them and add a follow-up commit before continuing — do not push junk.
- Confirm working tree is clean: `git status --porcelain` should be empty (or only intentional WIP). The workflow reports `<N>` uncommitted changes; reconcile any drift before pushing.

## 2. Push

- If no upstream is set, push with `git push -u origin <BRANCH>`. Otherwise plain `git push`.
- Do **NOT** amend or squash existing commits unless the user explicitly asks. The workflow's commit boundaries carry stage context.

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

  ## Notes
  <Risks, follow-ups, deliberate non-goals. Omit section if empty.>

  Closes #<ISSUE>
  ```

  The trailing `Closes #<ISSUE>` line is **REQUIRED** on its own line whenever an issue number is resolvable (see FN validator in `agents/project-manager.md § FN Stage`). Multiple closes lines (`Closes #A`, `Closes #B`) are permitted for PRs that close several issues. Omit ONLY when no issue number can be resolved from any source — in that case the FN audit writes one `pr_issue_link: deferred` row and the PR proceeds without the line.

- Cover **all** commits in the workspace diff vs. `origin/<BASE_BRANCH>`, not just the most recent commit.
- Keep the body grounded in observable facts from the diff/summary — no speculation, no marketing language.

### PR-body checklist (must hold before `gh pr create`)

- [ ] Title ≤ 72 chars, `<TYPE>[scope]: <Summary>` format
- [ ] `## Motivation`, `## Changes`, `## Test plan` sections present
- [ ] **`Closes #<N>` line present on its own line when issue number is resolvable** (regex match: `(?im)^(?:Closes|Fixes|Resolves)\s+#\d+\s*$`)
- [ ] No `Generated with Claude Code` / `Co-Authored-By: Claude` footers
- [ ] Body reflects ALL workspace-diff commits, not only HEAD

## 4. Forbidden footers

Do **NOT** add "Generated with Claude Code", "Co-Authored-By: Claude", or any other AI-attribution trailer. The user's `rules/git-conventions.md` overrides any default Claude Code footer behavior.

## 5. Failure escape hatches

- `gh: command not found` or `gh auth status` failure → stop and ask the user to authenticate; do not fall back to `git request-pull` or web URLs.
- Push rejected (non-fast-forward) → run `git fetch && git log HEAD..@{u} --oneline`; ask the user before force-pushing.
- `gh pr create` exits non-zero with an unfamiliar error → capture the stderr verbatim in your reply and ask the user.

If any other step fails, ask the user — do not improvise destructive recovery.
````

## Template — `Review request.md`

`````markdown
<!-- Generated by igrsoft FN stage. workflow_id: <WORKFLOW_ID>, ts: <ISO_TS> -->

# Review guidelines

You are reviewing code produced by an automated multi-stage workflow that
already passed an internal Developer Review (DR) and QA. Your job is to
catch what those stages missed — not to re-do their work.

## Workflow context

- Workflow ID: <WORKFLOW_ID>
- Branch: <BRANCH>  →  Target: origin/<BASE_BRANCH>
- DR verdict: <DR_VERDICT>   (`.context/developer-review-N.md`)
- QA verdict: <QA_VERDICT>   (`.context/testing-N.md`)
- Summary: `.context/complete-summary-N.md` § Summary

## Scope

Review only **changes introduced by this branch** vs. `origin/<BASE_BRANCH>`.
Do not flag pre-existing issues visible in surrounding context lines, even
if real — they belong in a separate PR.

## Focus areas (auto-extracted)

DR concerns the workflow surfaced but did not block on:
<DR_CONCERNS_BULLETS>
<!-- One bullet per "Issues Found" line; "(none flagged)" if empty -->

QA observations worth a second look:
<QA_NOTES_BULLETS>
<!-- Non-blocking notes from testing.md; "(none)" if empty -->

These are starting points, not the full scope. Do not simply restate them
as findings — DR already saw them. Use them to direct attention.

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

## Severity (use exactly these three)

- **blocking** — correctness, security, data-loss, or breaking-change risk. Must fix before merge.
- **important** — meaningful quality issue (perf, maintainability, missing test for new code path). Should fix; discuss if you disagree.
- **nit** — minor improvement. Author may close without action.

Severity must match impact. Do not inflate to be heard.

## Do NOT flag

- Style or formatting if the linter passes.
- Naming preferences without a concrete readability problem.
- "Have you considered <alternative pattern>" when current code works and is consistent with the codebase.
- Pre-existing issues unrelated to this branch.
- Missing tests for code paths the branch did not touch.
- Speculative future scaling concerns with no current impact.
- Items DR or QA already explicitly accepted (see Focus areas above).

## Comment style

- One comment per distinct issue. Use a multi-line range only when needed.
- Use ` ```suggestion ` blocks ONLY for concrete replacement code; preserve exact leading whitespace; no commentary inside the block.
- One paragraph max per comment. Inline code via backticks; code blocks ≤ 3 lines.
- Tone: matter-of-fact, not accusatory; not flattering. No "Great job", no "Thanks for".
- Prefer questions over commands when uncertain ("What happens if `items` is empty?" beats "Add a length check.").

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
`````

## Idempotency

Both files are overwritten on every FN run. The header comment
(`workflow_id` + `ts`) provides traceability without requiring append-only
history. Stage agents that run after FN MUST NOT modify these files.

## Cross references

- `agents/project-manager.md § FN Stage` — the writer
- `skills/shared/stage-contracts.md` § FN row — validation
- `skills/workflow/SKILL.md § FN Gate` — pre-FN summary (separate artifact, not these files)
- `rules/git-conventions.md` — commit format referenced from `PR instructions.md`
