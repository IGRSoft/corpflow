# FN Gate — full procedure

Read at gate time from `skills/worktask/SKILL.md § FN Gate` (stub). Detection + bypass-audit logic lives in the orchestrator loop step 4.9; this file is the imperative procedure once the gate fires.

A second human-in-the-loop checkpoint immediately before any FN-stage task. The orchestrator MUST present a pre-FN summary and STOP unless the PL0 task carries `metadata.fn_gate = "bypass"`.

> **Dynamic mode**: when `PL0.metadata.execution_mode == "dynamic"`, this gate fires on **workflow return** (the native Workflow span stops before FN). The pre-FN summary is built from the **reconciled `state.json`** (`dynamic-workflow.md#boundary-reconciliation`) exactly as in manual mode — the gate's ownership, bypass semantics, and template are identical. The workflow never commits, pushes, or opens a PR; FN remains orchestrator-owned and human-gated.

## Gate semantics

- **Carrier**: `PL0.metadata.fn_gate ∈ {"required", "bypass"}`. PL0 sets the value at worktask init based on invocation flags (see `commands/worktask.md` Phase 1, step 4).
- **Default**: missing or unrecognized value → treat as `"required"` (`?? "required"`). This makes in-flight worktasks safe across the change.
- **Bypass triggers**: `--auto-continue`, `--milestone:N`, `--worktree`. (`/emergency` is a documented TODO — not yet wired.)
- **Trigger condition**: gate fires when the next ready task has `metadata.stage === "FN"` AND `gateMode !== "bypass"`.
- **Effect, in order** (6 steps — none skippable, none reorderable):
  1. **Run the Pre-gate writer** (full procedure in *Pre-gate Conductor-attachments writer* section below). Produces both attachment files on disk. Do this **first**, before composing the summary or anything else — the summary template in this same file references both files as `[x]` Planned FN actions, and printing it while files are absent misleads the user.
  2. **Verify pre-seed** — `Bash: test -f ".context/attachments/PR instructions.md" && test -f ".context/attachments/Review request.md"`. On success → append `fn_attachments_preseed` audit line. On failure → append `fn_attachments_preseed_failed`, re-run step 1 once, then re-verify. If the second verify still fails, prepend `> WARN: attachment pre-seed failed — Conductor will use built-in defaults.` to the summary in step 4 so the user sees it before approving.
  3. **Hard precondition for printing the summary**: do not proceed past this point until step 2 has succeeded (or its WARN has been queued for the summary). The summary describes the writer's outputs; emitting it while the outputs are silently missing is a soft failure with no recovery (Conductor caches the absent state).
  4. **Print the pre-FN summary** (template at end of this file).
  5. **Append `fn_gate_waiting`** audit entry.
  6. **Re-verify, then `return`** — immediately before `return`, run `Bash: test -f` once more on both paths. On failure, append `fn_attachments_missing_at_return` audit line AND prepend a visible WARN to your final user message (this catches a writer that ran but wrote to the wrong path or was clobbered between step 2 and step 6). Then `return` from the execution loop. The FN task stays `pending`. The orchestrator MUST NOT call `TaskUpdate` for the FN task.

## Pre-gate Conductor-attachments writer

**Why this exists.** The two files this writer produces are how Conductor's *Create PR* / *Request Review* actions inherit worktask context in later sessions — DR/QA verdicts, resolved base branch, conventional-commit type, link to `complete-summary-N.md`. If they are absent, Conductor falls back to generic built-in templates and the FN agent (running post-approval) has no canonical script to follow. **Skipping this writer silently breaks the handoff — there is no recovery once the gate has returned**, because Conductor will cache the absent state for the duration of the next session. That is why the *Effect, in order* list above wraps this writer in three separate `test -f` checks (steps 2, 3, 6).

The writer is unconditional on the gated path; bypass path falls through to FN-agent Writer 2 (in `agents/project-manager.md § FN Stage`). It is idempotent: every FN-gate entry overwrites both files from scratch. Run it directly — do not delegate to a subagent.

Steps:

1. **Gather all git state in one Bash call** (single tool invocation reduces the chance of abandoning mid-sequence; parse the four values from the output):

   ```bash
   mkdir -p .context/attachments
   echo "BRANCH=$(git rev-parse --abbrev-ref HEAD)"
   echo "BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo main)"
   echo "UNCOMMITTED=$(git status --porcelain | wc -l | tr -d ' ')"
   echo "UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo 'no upstream')"
   ```

2. `Read: <plan_file>` (resolve via `FN0.metadata.plan_file`; fallback newest `.context/planning-*.md`) → derive COMMIT_TYPE from first match of `\b(fix|refactor|perf|docs|chore|test|ci|build|style|feat)\b` (default `feat`).
3. `Read: .context/developer-review-N.md` (N = `FN0.metadata.run_index`) → DR_VERDICT, DR_CONCERNS.
4. `Read: .context/testing-N.md` → QA_VERDICT, QA_NOTES.
5. `Write: .context/attachments/PR instructions.md` using template in `skills/worktask/references/conductor-attachments.md § Template — PR instructions.md`.
6. `Write: .context/attachments/Review request.md` using template in `skills/worktask/references/conductor-attachments.md § Template — Review request.md`.

Verification is owned by the *Effect, in order* list (step 2 immediately after this writer, step 6 immediately before `return`). Do not skip those — they exist because partial writer completion has happened in practice.

**Fault tolerance — per-input policy** (each Read is independent; do NOT wrap the whole sequence in a single try/catch — failure of one optional input must not skip the Writes):

| Input | Required? | If missing |
|-------|-----------|-----------|
| Plan file (step 2) | **Required** | Abort writer. Audit `fn_attachments_preseed_failed` with `reason: "plan_file_missing"`. The *Effect, in order* step 2 trip-wire will surface this to the user; do not write empty templates. |
| `developer-review-N.md` (step 3) | Optional | Defaults: `DR_VERDICT="unknown"`, `DR_CONCERNS="(none flagged)"`. Proceed to write. |
| `testing-N.md` (step 4) | Optional | Defaults: `QA_VERDICT="unknown"`, `QA_NOTES="(none)"`. Proceed to write. |

## `return` vs `continue`

The gate uses `return` (exit the loop), not `continue` (skip to next iteration). Rationale: any other ready task would also re-enter the loop on the next turn anyway, and exiting avoids partial side-effects (e.g., starting a sibling task while the user is reviewing the FN summary). Mirrors the PL0 gate pattern.

## Resume after approval

On the next orchestrator turn (triggered by the user's `approve`/`go`/`yes`/`continue`/`proceed` message):

1. Re-enter the loop. The FN task is still `pending`.
2. The gate check runs again. If the user adjusted PL0 metadata (e.g., set `fn_gate = "bypass"`), the gate now passes.
3. Otherwise: treat the user's most recent approval message as FN approval and proceed past the gate. Disambiguation: only one gate can be active at a time — PL0 is `completed` and no stage task is `in_progress`, so the approval can only be FN.
4. Write an `approval_received` audit entry with `subject: "FN"`.

## Pre-FN summary template

**Hard precondition (do not skip).** Before printing this summary, run:

```bash
test -f ".context/attachments/PR instructions.md" && test -f ".context/attachments/Review request.md" && echo OK
```

If you do not see `OK`, run the *Pre-gate Conductor-attachments writer* above, then re-check. The summary lists those two file writes as `[x]` Planned FN actions — emitting it while either file is absent is a soft failure that the user has no way to detect, and Conductor will inherit the absent state into the next session. Only proceed past this check after `OK` is observed (or, on a second failure, after queuing the `> WARN:` line per *Effect, in order* step 2).

Replace each `- [ ]` with `- [x]` for any Planned FN action whose output already exists on disk — the two attachment writes should now be `[x]`. Build the rest directly from artifacts written by upstream stages — no agent roundtrip needed.

```
## FN gate — review before push

### Change surface
- N commits on branch `<branch>`: <short shas + titles>
- Target: PR against `<base-branch>`
- Net diff: +X / -Y lines across N files

### Quality evidence
- QA verdict: <GO/NO-GO>           (.context/testing-N.md)
- DR verdict: <PASS/CONCERNS>      (.context/developer-review-N.md)
- Tests: <M passed / N failed>

### Planned FN actions
- [ ] Write `.context/attachments/PR instructions.md` (Conductor attachment)
- [ ] Write `.context/attachments/Review request.md` (Conductor attachment)
- [ ] Write `.context/complete-summary-N.md` (worktask summary + stage timings)
- [ ] Create commit(s) with conventional-format messages
- [ ] Push branch with upstream tracking
- [ ] Open PR against <base-branch> with Motivation / Changes / Notes

Reply `approve` to proceed, or describe any changes needed.
```

Source files (per `skills/shared/stage-contracts.md`):

| Field | Source |
|-------|--------|
| Branch / commits | `git status` + `git log <base>..HEAD --oneline` |
| QA verdict | `.context/testing-N.md` (GO/NO-GO line; N from run_index) |
| DR verdict | `.context/developer-review-N.md` (PASS/CONCERNS; N from run_index) |
| Diff stats | `git diff <base>..HEAD --shortstat` |
| Base branch | `workspace.json § base_branch` (milestone) or repo default |

## User amendment at the gate

If the user replies with edits instead of `approve` (e.g., "change the commit message to X"), the orchestrator:

1. Updates the FN task description via `TaskUpdate({taskId, description: ...})`.
2. Re-builds and re-presents the pre-FN summary.
3. STOPs again. The FN task remains `pending` throughout.

## Post-amendment audit

Each gate transition writes an audit line:

```json
{"actor":"orchestrator","action":"fn_gate_waiting","subject":"FN0","result":"pending"}
{"actor":"orchestrator","action":"approval_received","subject":"FN0","result":"ok"}
```

Bypassed gates write a single line:

```json
{"actor":"orchestrator","action":"fn_gate_bypass","subject":"FN0","result":"ok","reason":"auto-continue|milestone|worktree"}
```

# Post-Worktask Self-Improvement

After the execution loop exits (all tasks completed, including ST), the orchestrator runs a final check to handle any learnings captured at ST. Read this section from `skills/worktask/SKILL.md § Post-Worktask Self-Improvement` (stub) when `.context/learnings.md` exists.

## Post-ST Procedure

1. **Check for learnings artifact:** `fs.existsSync(".context/learnings.md")`.
   - Absent → nothing to do. Worktask complete.
   - Present → continue.

2. **Surface to user:** read `.context/learnings.md` and present it to the user. Focus attention on the `## Proposed Updates` checklist.

3. **Wait for user approval decisions.** The user indicates which proposals to accept by checking boxes (`- [ ]` → `- [x]`). The orchestrator MUST NOT auto-check boxes or assume approval.

4. **Read checked items:** parse `.context/learnings.md` for lines matching `- [x]` under `## Proposed Updates`. Each checked item is a proposal to apply.
   - If zero checked items → skip to step 6.

5. **Delegate to prompt-engineer** with one `Agent` call carrying the full list of checked proposals:
   ```typescript
   Task({
     subagent_type: "igrsoft:prompt-engineer",
     model: "opus",
     prompt: `Apply self-improvement learnings from .context/learnings.md.
              Apply ONLY checked items (- [x]). Follow the Apply Protocol in your agent definition.
              Do not propose new changes; only apply approved ones.
              Return a summary of applied/skipped proposals and the commit SHAs created.`
   });
   ```
   The prompt-engineer applies each proposal as its own commit with a `version:` bump (see `agents/prompt-engineer.md § Self-Improvement Patch Application`).

6. **Audit entry:** append one line to `.context/logs/audit.jsonl`:
   ```json
   {"actor": "orchestrator", "action": "self_improvement_applied", "subject": "<worktask_id>", "applied_count": N, "skipped_count": M, "result": "ok"}
   ```

7. **Terminate.** Worktask is now fully complete. Do not re-enter the execution loop.

## Safety invariants

- DO NOT apply proposals the user did not explicitly check.
- DO NOT re-run self-improvement on the orchestrator's own post-ST activity (no recursion).
- DO NOT modify `.context/learnings.md` after ST produced it; the prompt-engineer only reads it.
- If `learnings.md` is malformed (no `## Proposed Updates` section) → log warning, skip apply, continue to terminate.
