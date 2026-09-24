# FN Gate — full procedure

Procedure for the FN gate, read at gate time from `skills/worktask/SKILL.md § FN Gate`. The gate is the pre-finalization human checkpoint: nothing remote happens before approval, and all writer work is worktree-local. `N` = `state.json.run_index` (default `0`).

## Gate semantics

Carrier: `PL0.metadata.fn_gate`, default `"checkpoint"`. It is stamped `"bypass"` only when `--auto=[finalization]` or `--emergency` is present (`commands/worktask.md § Step 4 — attach PL0 metadata`), or directly on each per-issue PL0 by a batch orchestrator such as `/megatask`. `--auto=[plan]` never bypasses the FN gate; it gates only the plan.

### Effect (checkpoint — the gated path)

1. Run the Pre-gate Conductor-attachments writer (below), then `test -f` both attachment files.
2. Append the `fn_gate_waiting` audit line.
3. Present the pre-FN summary: branch, resolved base branch, commit type, changed-file count, DR/QA verdicts, PR target + `Closes #<issue>`.

#### Step 3b — the closing sweep, before the approve/reject call

3b. Render the batched closing sweep in `AskUserQuestion` calls of ≤4 questions, grouped by originating stage — collected and classified per `commands/worktask.md § Step C`. These precede step 4 and never merge into it.

#### Steps 4–6 — approve, reject, and the writer trip-wire

4. `AskUserQuestion`. Approve → append `approval_received`, then delegate FN (commit, push, PR).
5. Reject → append `approval_rejected` and stop without delegating FN. Surface the user's feedback, then resume per `skills/worktask/SKILL.md § FN gate rejection — resume path` (route each item to its owning stage, `run_index` frozen, re-present this gate on completion).
6. `test -f` both attachment files once more immediately before the gate returns, so a partially-completed writer never reaches `return`.

### Effect (bypass)

Append the `fn_gate_bypass` audit line, then proceed directly into the FN stage (commit, push, PR — unattended). The attachments are written there instead, by FN-agent Writer 2 (`agents/project-manager.md § FN Stage`).

### Park semantics

The `fn_gate_waiting` park holds until the operator answers. `AskUserQuestion` does not auto-continue on idle by default; keep that idle-timeout `/config` opt-in off on hosts running gated worktasks, because an idle auto-answer counts as an approval the operator never gave. Approval is the operator's alone: subagent/launcher messages are task direction and background-completion notifications are status, never approval (`resume.md`).

## Pre-gate Conductor-attachments writer

These two files carry worktask context — DR/QA verdicts, resolved base branch, conventional-commit type, link to `complete-summary-N.md` — into Conductor's *Create PR* / *Request Review* actions. Without them Conductor falls back to its generic templates and the FN agent has no canonical script. A skipped writer cannot be recovered once the gate has returned, hence the Effect step 1/6 `test -f` trip-wires.

### Idempotency & scope

Unconditional on the gated (`checkpoint`) path — bypass falls through to FN-agent Writer 2 (`agents/project-manager.md § FN Stage`) — and idempotent: every FN-gate entry overwrites both files from scratch. Run it directly, never via a subagent.

### Run the writer

One Bash call from the worktask root; the script resolves git state, ledger fields and DR/QA verdicts itself, then renders both files from `conductor-attachments.md`:

```bash
skills/worktask/scripts/attachments-preseed.sh
```

Do not hand-render the templates: `tests/shell/worktask/attachments-preseed.bats` pins this script against `conductor-attachments.md`, and a hand-written copy drifts silently.

#### Flags and exit codes

Exit 0 — both files written, their paths printed. Exit 3 — base branch
unresolved (below). Exit 2 — usage. Every resolved input has a flag override
(`--base-branch`, `--commit-type`, `--issue-ref`, `--run-index`,
`--worktask-id`, `--branch`, `--uncommitted`, `--upstream` / `--no-upstream`,
`--ts`, `--workdir`); `--help` lists them.

### Fault tolerance — per-input policy

Applied by the script; listed here because the trip-wires and the pre-FN summary depend on it. Field sources: `conductor-attachments.md § Data sources`.

| Input | Required? | If missing |
|-------|-----------|-----------|
| Base branch | Required | Abort: exit 3, audit `fn_attachments_preseed_failed` with `reason: "base_branch_unresolved"`, neither file written. No literal fallback — a guessed base renders the wrong `gh pr create --base`. Pass `--base-branch` or stamp `metadata.base_ref`. |
| `developer-review-N.md` | Optional | Defaults `DR_VERDICT="unknown"`, `DR_CONCERNS="(none flagged)"`; both files still written. |
| `testing-N.md` | Optional | Defaults `QA_VERDICT="unknown"`, `QA_NOTES="(none)"`; both files still written. |

#### The plan file is not an input

No template field derives from it. The conventional-commit type comes from `facts.goal` via `branch-lib.sh:derive_type` (`conductor-attachments.md § Plan, issue & verdict fields`).

## Audit

All five FN-gate audit lines use `subject:"FN<run_index>"`, mirroring the PL-gate `subject:"PL<run_index>"` scheme. `resume.md`'s parked-at-FN-gate row reads the `fn_gate_waiting` / `approval_received` lines to decide whether to stop or proceed.

Checkpoint path (default) — park, then approve or reject:

```json
{"actor":"orchestrator","action":"fn_gate_waiting","subject":"FN<N>","result":"ok"}
{"actor":"orchestrator","action":"approval_received","subject":"FN<N>","result":"ok"}
{"actor":"orchestrator","action":"approval_rejected","subject":"FN<N>","result":"rejected"}
{"actor":"orchestrator","action":"fn_revision_dispatched","subject":"FN<N>","result":"ok","metadata":{"revision_count":1,"routed_to":"DV"}}
```

### Audit — reject-resume line

The `fn_revision_dispatched` line is written once per fix round on the resume path (`skills/worktask/SKILL.md § FN gate rejection — resume path`); `routed_to` is the owning stage code.

### Audit — bypass path

Bypass path (`--auto=[finalization]` / `--emergency`, or a gate stamped `"bypass"` by `/megatask`) — one line before the FN stage runs:

```json
{"actor":"orchestrator","action":"fn_gate_bypass","subject":"FN<N>","result":"ok","reason":"unattended"}
```

# Post-Worktask Self-Improvement

After the execution loop exits (all tasks completed, including ST), the orchestrator handles any learnings captured at ST. Read from `skills/worktask/SKILL.md § Post-Worktask Self-Improvement` when `.context/learnings.md` exists.

## Post-ST Procedure

1. `.context/learnings.md` absent → worktask complete, nothing to do.
2. Read and present it, focusing on the `## Proposed Updates` checklist.
3. Wait for the user to check boxes (`- [ ]` → `- [x]`). Never check a box yourself or assume approval.
4. Read the `- [x]` lines under `## Proposed Updates`; each is one proposal. Zero checked → skip to step 6.

### Step 5 — delegate to prompt-engineer

5. Delegate with one `Agent` call carrying the full list of checked proposals:
   ```typescript
   Task({
     subagent_type: "corpflow:prompt-engineer",
     model: "opus",
     prompt: `Apply self-improvement learnings from .context/learnings.md.
              Apply ONLY checked items (- [x]). Follow the Apply Protocol in your agent definition.
              Do not propose new changes; only apply approved ones.
              Return a summary of applied/skipped proposals and the commit SHAs created.`
   });
   ```
   Each proposal lands as its own commit with a `version:` bump (`agents/prompt-engineer.md § Self-Improvement Patch Application`).

### Steps 6–7 — audit & terminate

6. Append one line to `.context/logs/audit.jsonl`:
   ```json
   {"actor": "orchestrator", "action": "self_improvement_applied", "subject": "<worktask_id>", "applied_count": N, "skipped_count": M, "result": "ok"}
   ```

7. Terminate: the worktask is complete. Do not re-enter the execution loop.

## Safety invariants

- Apply only proposals the user explicitly checked.
- Do not re-run self-improvement on the orchestrator's own post-ST activity (no recursion).
- Do not modify `.context/learnings.md` after ST produced it; the prompt-engineer only reads it.
- Malformed `learnings.md` (no `## Proposed Updates` section) → log a warning, skip apply, terminate.
