---
name: worktask
description: Initialize a new worktask task with proper folder structure and state-ledger integration
argument-hint: '<task description> [--secure] [--emergency] [--auto=[plan, decision, finalization]]'
version: 0.6.0
model: opus
allowed-tools: Read, AskUserQuestion, SendMessage, ListAgents, Monitor, TaskStop, Bash(claude:*), Glob, Grep, Bash(mkdir:*), Bash(gh:*), Bash(git:*), Bash(bash skills/worktask/scripts/state-patch.sh:*), Bash(bash skills/worktask/scripts/preflight-issue-scan.sh:*), Bash(bash skills/worktask/scripts/branch-name.sh:*), Bash(bash skills/worktask/scripts/refine-branch-target.sh:*), Bash(bash skills/worktask/scripts/publish-pl-issue.sh:*), Bash(bash skills/worktask/scripts/handoff-harness.sh:*), Bash(bash skills/worktask/scripts/workspace-root-banner.sh:*), Bash(bash skills/worktask/scripts/effort-ladder.sh:*), Task(corpflow:product-manager)
related:
  - skills/worktask/SKILL.md
  - commands/megatask.md
  - skills/megatask/SKILL.md
  - skills/shared/stage-codes.md
  - skills/agent-coordination/references/headless-dispatch.md
  - agents/workflow-engineer.md
---

> **Execution model** — every worktask is worktree-isolated, so the PR is the review
> surface. Three orthogonal carriers on `PL0.metadata` drive the two human checkpoints and the
> optional decision delegate; `/megatask` stamps them directly on each per-issue PL0.
>
> | Carrier | Default | Alternate | Meaning |
> |---|---|---|---|
> | `plan_gate` | `checkpoint` | `bypass` — `--auto=[plan]`, `--emergency` | Post-PL0 checkpoint: present the plan, wait for explicit `AskUserQuestion` approval before dispatching any implementation stage (AR/DV/…) |
> | `decision_gate` | `user` | `auto` — `--auto=[decision]` | Who answers `open_questions[]`: the user, or a delegate. PL0's at the plan gate (§ Step A.4); every other stage's blocking items at their own boundary (§ Step C.0a); the FN-gate batch at § Step C.3. Escalation-class questions always fall back to the user |
> | `fn_gate` | `checkpoint` | `bypass` — `--auto=[finalization]`, `--emergency` | Pre-FN checkpoint: STOP before the FN `Task()`, present a pre-FN summary, approve before any commit/push/PR |

# Worktask Command

Initialize a new worktask task with proper folder structure and state-ledger integration.

> **CRITICAL CONSTRAINTS**
> - MUST use `.context/state.json` `tasks{}` for worktask state, written only via `state-patch.sh`. Do NOT use Claude Code's built-in plan mode.
> - Every stage MUST have a ledger entry. Do NOT skip seeding one.
> - If the ledger cannot be read or written, STOP and report. Do NOT fall back to alternative planning.

## Usage

```
/worktask "Task Title" [options]     # Execute a single task through the staged pipeline
```

> **Multi-issue batches moved to `/megatask`.** `/worktask` is strictly single-issue and
> milestone-agnostic — it has no `--milestone` flag. For a milestone or an issue array with
> dependency ordering use `/megatask N` / `/megatask --issues 12,15,18` (`commands/megatask.md`,
> `skills/megatask/SKILL.md`).

## Worktask Types

| Type | Stages | Entry point |
|------|--------|-------------|
| Standard | PL→AR→TL→DV→DR→QA→DC→FN→ST | `/worktask` |
| Secure | PL→AR→TL→DV→DR→SR→QA→DC→RE→FN→ST | `/worktask --secure` |
| Emergency | IR→DV→DR→QA→RE→FN | `/worktask --emergency` |

AR and TL are optional in the standard and secure pipelines: AR is a tier default PL0 may override
either way, TL is included only when PL0 splits work across ≥2 developers. Criteria:
`skills/estimation-methodology/SKILL.md § Stage Inclusion Criteria (PL0 authority)`. Stage details:
`skills/shared/stage-codes.md`.

## Options

### Gate automation flag (`--auto`)

`--auto=[<values>]` takes an **array** — any non-empty subset of `plan`, `decision`,
`finalization`, comma-separated. Brackets optional, inner whitespace tolerated
(`--auto=[plan, decision]`, `--auto=plan,finalization` both valid). An unknown value is a parse
error: reject the invocation and report; never drop it silently. Each value is an independent
carrier on PL0.

#### Gate automation flag — values

| Value | Stamps | Effect beyond the carrier table above |
|-------|--------|---------------------------------------|
| `plan` | `plan_gate: "bypass"` | Auto-proceeds into the stage loop. FN gate still checkpoints unless `finalization` is also set. |
| `decision` | `decision_gate: "auto"` | Bypasses NO gate by itself: under a `checkpoint` plan gate the auto-decisions are presented (marked) for approval. Also what enables the § Step C.0a resolver, so a blocking `decision` item from AR/TL/DV/DR/SR/QA/DC/RE/ET is answered a tier up instead of stopping the run. Escalation-class questions — irreversible, scope-expanding, security-posture, spend — always fall back to the user. |
| `finalization` | `fn_gate: "bypass"` | Auto commit/push/PR. Plan gate still applies unless `plan` is also set. |

### Scope and pipeline flags

| Option | Effect |
|--------|--------|
| `--priority [High\|Medium\|Low]` | Task priority |
| `--platform <apple\|android\|web\|systems\|backend\|ai\|all>` | Target platform |
| `--ethics-review` | Add ET checkpoint after PL |
| `--with-design` | Invoke `corpflow:designer` during PL. Without it Designer is skipped even for UI work and the keyword score stays advisory. |
| `--sequential` | DC waits for QA |
| `--secure` / `--full` | Use 11-stage worktask |
| `--emergency` | Run the incident pipeline (IR→DV→DR→QA→RE→FN) instead of the PL-first pipeline; IR owned by `incident-responder`. Replaces the former `emergency:` prefix. |
| `--no-gh-issue` | Skip the post-PL GitHub issue auto-publish. Sets `metadata.no_gh_issue: true` on PL0; `publish-pl-issue.sh` audits `deferred`/`opted_out` and the stage loop continues. |

### Replay flags

| Option | Effect |
|--------|--------|
| `--resume <STAGE_ID>` | Replay one already-settled stage of the worktask in this `.context/` — § Phase 0. Takes a ledger id (`DV1`), not a stage code. Creates no run: no new `planning-N.md`, no issue, no branch rename. Composes with none of the flags above. |
| `--cascade` | Only with `--resume`. Also replays dependents transitively reachable through `blocked_by`. FN/RE **dependents** are traversed through but never reset; an FN/RE named as the *target* is still reset — an explicit id is your instruction — with a `side-effect-target` warning. |

## Examples

```bash
/worktask "Add dark mode support"                      # standard pipeline
/worktask "Rotate the API token store" --secure        # 11-stage; --full is the same flag
/worktask "Fix flaky sync test" --priority High --platform apple
/worktask "Ship the referral banner" --ethics-review --sequential
/worktask "Bump the SDK" --no-gh-issue --auto=[plan,finalization]
/worktask --emergency "Production login failing"       # IR→DV→DR→QA→RE→FN
/worktask --resume DV1 --cascade                       # replay DV1 and its dependents
# Multi-issue: /megatask 1   (milestone)   or   /megatask --issues 12,15,18   (array)
```

## Phase 0: Replay one stage (`--resume <STAGE_ID>`)

Entered ONLY by `/worktask --resume <STAGE_ID> [--cascade]`. Unlike automatic reattach (first
incomplete stage, retry ceiling honoured), a replay is *given* one ledger id by a human and may
override that ceiling (`skills/worktask/references/resume.md § Explicit-replay row`).

Phase 0 replaces Phase 1 entirely, then re-enters the existing stage loop, adding **no** dispatch
route and **no** readiness rule: the replayed task becomes `pending` with its dependencies still
`completed`, so it is the first unblocked task and every other stage stays settled.

### Phase 0 — what runs

**Skip** — all of Phase 1 (Steps 2a, 3, 3a, 3c, 4, 5–6, 7–8) and every pre-loop Phase 2 step
(A.4, A.4b, A.5, Step A publish). `run_index` is frozen; no `planning-N.md`, no rename, no issue.

**Run** — Step 3b hook-install verification (idempotent; a resumed loop still needs
SubagentStop), the `fn-preflight.sh branch-divergence` check (`resume.md § Branch-rename
detection`), and the BINDING workspace-root cross-check before every `Task()`.

### Phase 0 — procedure

1. No `.context/state.json` in the working tree → error out: "no worktask here — use
   `/worktask <task>`". Do not seed one.
2. Present the **pre-replay confirmation and STOP**, naming: the target id with its status,
   `retry_count`, `error_escalated_to`; whether the escalation cap is being overridden; any
   already-`completed` dependents, marked *these may now be stale* (warn only — never auto-reset);
   a plan-unapproved warning when no `approval_received` row exists for `PL<run_index>`; and under
   `--cascade` the member list plus the skipped FN/RE members. There is no bypass flag.
3. Run `bash "$PLUGIN_ROOT/skills/worktask/scripts/state-patch.sh" --task-replay <ID> [--cascade]`.

### Phase 0 — procedure, steps 4–6

4. **Exit 4** means a guard refused (target live or parked, liveness indeterminate, planning
   incomplete, or a blocked cascade member); `state.json` is byte-unchanged. Print the refusal line
   verbatim and STOP — do NOT enter the stage loop. Exit 1 is an unknown id, exit 2 a malformed one.
5. Append the ordinary `resume` audit row (`resume.md` step 7) — it records session re-entry, while
   the primitive's `stage_replay` row records what changed in the ledger.
6. Re-enter `§ After Step A — run the stage loop`, unchanged.

### Phase 0 — gates on a resumed run

| Gate | Behaviour |
|------|-----------|
| `plan_gate` (Step A.5) | **Never re-fires.** It gates the Phase-1→Phase-2 transition; a replay reopens no planning and the `approval_received` row persists. Its absence is a warning at step 2, not a stop |
| `fn_gate` | **Applies unchanged.** It is a property of the loop, not of the entry point — a resumed run must not slip a commit past the finalization checkpoint |

## Phase 1: Planning (execute immediately)

> **BINDING 1 — Pre-work Prohibition**: create, edit, or modify NO project files during Phase 1
> (localization, accessibility IDs, config, sources). Only
> `mkdir -p .context/designs .context/images .context/errors`, `state-patch.sh` ledger writes, and
> the Step 2a `.context/gh-issue.json` anchor (reuse path only) are permitted. ALL file
> modifications belong to DV or later.

### Phase 1 binding constraint 2 — Context-Interruption Recovery

> **BINDING 2 — Context-Interruption Recovery**: after an interruption (auth flows, tool failures),
> on resumption MUST verify PL0 exists with status `completed`; if not, restart from the appropriate
> phase — **except** when PL0 is `in_progress` with stage tasks present and the audit tail has a
> `plan_revision_dispatched` row with no later `approval_received` for `PL<run_index>`: that is a
> plan revision in flight, resumed per § Plan-revision re-dispatch (re-dispatch PM with
> `plan_revision: true`; never the fresh-run path). Both checkpoints still apply — the plan gate at
> Step A.5 and the FN gate (`skills/worktask/SKILL.md § FN Gate`).

### Steps 1–2 — Parse flags and detect embedded commands

1. **Parse** the task description and flags. Resolve the `--auto` array per § Gate automation flag:
   strip optional brackets, split on commas, trim whitespace, reject unknown values.
2. **Detect embedded commands**: extract any `/plugin:command` or `/command` pattern into
   `metadata.embedded_commands` (comma-separated), strip the prefix from the description passed to
   PL0, preserve the arguments. See § Embedded Command Detection.

### Step 2a — Duplicate-issue pre-flight (advisory)

Runs once the request is known and **strictly before** Step 3 creates `.context/`. The
`skills/gh-issue-dedup` anchor guards *re-runs* only, so a first run of work already filed under
different wording still opens a second issue — this step surfaces the candidates while the duplicate
is still preventable. Append `--no-gh-issue` to the invocation when that flag was supplied.

#### Snippet preamble (every snippet in this file)

    PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"  # CC substitutes on load; if empty resolve per skills/shared/plugin-root-resolution.md
    [ -d "$PLUGIN_ROOT" ] || PLUGIN_ROOT="<plugin-root>"

#### Step 2a snippet — invoke the scan, non-blocking

    SCAN="$PLUGIN_ROOT/skills/worktask/scripts/preflight-issue-scan.sh"
    scan_out=""
    if [ -f "$SCAN" ]; then scan_out=$(bash "$SCAN" --goal "<task description>") || true; fi
    scan_result=$(printf '%s\n' "$scan_out" | sed -n 's/^result=//p' | tail -n 1)

#### Step 2a — the gate

Anything other than `result=shown` proceeds to Step 3 unchanged, with no prompt. On `result=shown`,
present each `candidate=<json>` line (number, title, url — at most three, most likely first) and
`AskUserQuestion` with exactly two outcomes:

- **Start a new worktask** — Step 3 as normal. Nothing is written yet, so declining leaves no
  orphaned state.
- **Use one of the existing issues** — Step 3, then bind this context to the chosen issue: after
  Step 3a seeds `state.json`, write the dedup anchor below.

#### Step 2a — reusing an existing issue

    jq -cn --arg url "<chosen url>" --argjson num <chosen number> \
       --arg wid "$(jq -r '.worktask_id // "unknown"' .context/state.json)" \
       --arg ts "$(date -u +%FT%TZ)" \
       '{version:1, url:$url, number:$num, created_run_index:-1, created_worktask_id:$wid,
         created_at:$ts, last_commented_run_index:-1}' > .context/gh-issue.json

Planning still runs, bound to the existing issue. `created_run_index: -1` is the "predates this
context" value `publish-pl-issue.sh` already uses for a recovered search hit, so Step A comments on
that issue instead of opening a second one.

#### Step 2a invariants

- The trailing `|| true` is mandatory — **non-blocking by contract**: no network/`gh`/auth/remote, an
  API error, a rate limit, a timeout, a malformed response, or zero hits each print
  `result=skipped`/`result=none` and Step 3 runs unchanged.
- **Advisory only**: it never links, comments, closes, or writes (not even an audit row — the ledger
  does not exist yet), and does NOT relax the exact-title auto-bind in `publish-pl-issue.sh`
  (`skills/gh-issue-dedup § Resolution order`).
- **Unattended runs never reach it**: self-skips under `CORPFLOW_NONINTERACTIVE=1`, `/megatask`
  (`MILESTONE_MODE=1` or a `workspace.json`), and `--emergency` (`INCIDENT_MODE=1`);
  `PREFLIGHT_ISSUE_SCAN=0` disables it outright. A `.context/` already carrying a `gh-issue.json`
  anchor is a resume: `reason=already_anchored`, and the anchor answers authoritatively.

### Steps 3–3a — Context folders and state.json seed

3. `mkdir -p .context/designs .context/images .context/errors .context/logs`
3a. Atomic-write the `.context/state.json` seed (temp+fsync+rename per
`skills/worktask/references/handoff-protocol.md#atomic-write`, schema per `#state-json-schema`),
PL0 `in_progress`. **Re-run aware**: compute the next free planning index from any pre-existing
`.context/planning-*.md` — hard-coding `planning-0.md` pins the old plan and lets PL0 overwrite it.
If creation fails (e.g. read-only filesystem), STOP and report: there is no correct degraded mode.

#### Step 3a — the seed payload

The re-run-aware next-free-index resolver (N=0 on a fresh `.context/`, nullglob-safe) and the atomic
write are canonical in `skills/worktask/references/initialization-patterns.md`. Seed
`{version:2, worktask_id, plan_file: .context/planning-${N}.md, platform, run_index:N,
metadata.workspace_path, tasks.PL0.status:in_progress, facts.goal, plus the otherwise-empty facts
incl. dispatched_agents:[], handoffs:{}}`. The seeded `plan_file` is the **path** shape, not a bare
basename — task metadata carries the basename shape; both are legal (`handoff-protocol.md §
state.json schema`).

#### Step 3a — `metadata.workspace_path` (UNCONDITIONAL) and `facts.goal`

- **`workspace_path`**: `git rev-parse --show-toplevel`, else `pwd`. Not a megatask-only field:
  `dv-tree-preflight.sh`, the § Workspace-root cross-check, and `agents/developer.md`'s path-prefix
  check all read it and each degrades to a **silent pass** when it is absent — omitting it disables
  all three at once (`initialization-patterns.md § Seeded workspace_path`).
- **`facts.goal`**: from the task description, JSON-escaped, truncated to 240 chars. It is the issue
  title and `## Summary` source for `publish-pl-issue.sh`, and nothing on the PL state-patch path
  writes it. PM refines it later; the seed only guarantees it is never absent.

#### Step 3a field notes

`facts.dispatched_agents: []` is seeded (additive) so the loop appends per-`task_id` dispatch entries
in place. The other v1 additive fields (`tasks.<ID>.completed_via`/`last_error`/`worktree`,
`facts.capabilities`) are written on demand — do NOT seed them; their absence is meaningful
(`handoff-protocol.md#state-json-schema`).

### Step 3b — Verify SubagentStop hook installed

3b. After the seed, verify `.claude/hooks/state-merge.sh` exists and is executable AND that the
plugin's `plugin.json` registers the SubagentStop hook — the Layer 2 safety net that patches
state.json when agents skip self-patching (`initialization-patterns.md#hook-installation`).

   ```bash
   # $PLUGIN_ROOT per § Snippet preamble
   hook_src="$PLUGIN_ROOT/hooks/state-merge.sh"
   hook_dst=".claude/hooks/state-merge.sh"
   if [[ ! -x "$hook_dst" ]] && [[ -f "$hook_src" ]]; then
     mkdir -p .claude/hooks
     cp "$hook_src" "$hook_dst" && chmod +x "$hook_dst"
   fi
   ```

#### Step 3b regression guard

**Regression guard**: if neither the plugin-registered hook NOR the project-local copy exist, warn
(`"⚠ state-merge.sh hook not installed — state.json will only be patched if agents self-merge
(Layer 1) or orchestrator Step 6.5 fires (Layer 3). Run hook-install.sh to fix."`) and do NOT block.

### Step 3c — Name the branch once (PL start)

3c. **UNCONDITIONAL**, on every worktask with no precondition (Conductor workspaces and manual
`git checkout -b` branches included): after the seed and before Step 4, run
`bash skills/worktask/scripts/branch-name.sh --goal "<concise imperative title>"`. This is the ONLY
place a worktask branch is ever renamed (once-only rule, `skills/shared/git-conventions.md § Branch
Naming`); the *planned* ledger name may be refined once more without git mutation (§ Step A.4b).
Every outcome exits 0 — a naming problem must never stop planning — and the step self-disables
**inside the script** under `/megatask` or `--emergency`. Its guard ladder has an "already
conventional" no-op arm, so running it on a named branch costs one process and is the only correct
way to establish that the name is in fact conventional.

#### Step 3c — the input is a title, not the task description

**Derive the title from the request; never pass the request verbatim.** A title is an imperative
phrase of ≤60 characters naming the thing changed and the change; the goal is slugified into a
48-character slug and the overflow is dropped **silently** (grammar and budget:
`git-conventions.md § Branch Naming`).

- good: `Replace in-house ZIP with upstream ZipArchive`
- bad: `Replace the in-house ZIP implementation in Sources/Archive/ with the upstream ZipArchive
  package, keeping the existing public API and updating the tests`

`BRANCH_NAME_PRINT=1 bash …/branch-name.sh --goal "<title>"` previews the name — renames nothing,
writes no audit row. Preview before the one rename-mode run; that is how a poor title is caught while
it is still free to change.

#### Step 3c — who decides conventionality (BINDING)

> Never judge conventionality by eye. The sole authority is `branch_is_conventional()` from
> `skills/worktask/scripts/branch-lib.sh`, reachable as `branch-name.sh --check "<name>"`
> (0 = conventional, 1 = not, 2 = internal fault). "This looks like a real branch name, skip" is how
> `fix/catalog-image-blinking` reached `facts.branch` after `fix` left `BRANCH_TYPES`.

#### Step 3c — host-session authorization (BINDING)

Invoking `/worktask` **satisfies** a host's "do not rename the current branch unless the user
explicitly tells you to" session rule (Conductor injects exactly that): **never revert this step's
rename, and never suspend the pipeline to re-ask** — worktrees included
(`skills/worktask/references/workspace-modes.md § Host session authorization`), where the local
branch is renamed too, so
`branch=` and `target_branch=` agree and the host's branch↔workspace mapping moves with it.
`BRANCH_NAME_WORKTREE_RENAME=0` restores the defer-to-host behaviour (local name kept, only
`target_branch=` derived).

#### Step 3c — validate before stamping

Capture **both** stdout key=value lines: `target_branch=<name>` (the name the PR head should carry)
and the final `branch=<name>` (the local branch as it stands). **Verify against
`^[A-Za-z0-9._/-]+$` before stamping** — defence in depth alongside the script's emission validation
and FN's re-validation (`agents/project-manager.md § Final FN steps`); a failing value MUST be
stamped empty, never as-is. Stamp `state.json facts.branch` — the script never writes state.json
(`handoff-protocol.md § branch`). Both lines come back empty rather than carrying a name that fails
the predicate, so an empty stamp is the honest "no planned name" outcome (FN pushes plainly).

#### Step 3c — which of the two names gets stamped

   ```bash
   # A TITLE (≤60 chars), never the raw task description — the 48-char slug budget
   # drops the overflow silently.
   out=$(bash skills/worktask/scripts/branch-name.sh --goal "<concise imperative title>")
   local_branch=$(printf '%s\n' "$out" | sed -n 's/^branch=//p' | tail -n 1)
   target=$(printf '%s\n' "$out" | sed -n 's/^target_branch=//p' | tail -n 1)
   truncated=$(printf '%s\n' "$out" | sed -n 's/^slug_truncated=//p' | tail -n 1)

   # target_branch wins whenever the local name is unusable as a PR head; falling back
   # to the local name here is what shipped a `<city>-v<n>` branch as a PR head.
   stamp="$local_branch"
   if [ -z "$stamp" ] || ! bash skills/worktask/scripts/branch-name.sh --check "$stamp"; then
     [ -n "$target" ] && stamp="$target"
   fi
   ```

#### Step 3c — post-check (non-blocking)

After stamping, assert the stamped value against the predicate — not by eye. Reuse `$target`; never
re-invoke in **rename mode** (that writes a second audit row). `BRANCH_NAME_PRINT=1`, `--check`, and
`--print-target` write none:

   ```bash
   stamped=$(jq -r '.facts.branch // ""' .context/state.json)
   if [ -n "$stamped" ] && ! bash skills/worktask/scripts/branch-name.sh --check "$stamped"; then
     jq -cn --arg ts "$(date -u +%FT%TZ)" --arg a "$stamped" --arg d "$target" \
       '{ts:$ts, actor:"orchestrator", action:"branch_convention_check", subject:"PL0",
         result:"warn", metadata:{actual:$a, derived_target:$d}}' \
       >> .context/logs/audit.jsonl
   fi
   ```

#### Step 3c — post-check, the truncation row

`slug_truncated=1` appears ONLY when the budget dropped content. Then append one row naming the input
length and the surviving slug — the evidence a human reads at the plan gate, and the
incumbent-quality signal § Step A.4b reads (`$title` is the `--goal` title; `slug` is the
post-`<type>/` remainder):

   ```bash
   if [ "$truncated" = "1" ]; then
     wid=$(jq -r '.worktask_id // "unknown"' .context/state.json)
     ri=$(jq -r '.run_index // 0' .context/state.json)
     jq -cn --arg ts "$(date -u +%FT%TZ)" --arg s "PL$ri" --arg t "$target" \
       --arg len "${#title}" --arg slug "${target#*/}" --arg dk "$wid:$ri:branch_slug_truncated" \
       '{ts:$ts, actor:"orchestrator", action:"branch_slug_truncated", subject:$s,
         result:"warn", task_id:"PL0",
         metadata:{input_len:$len, slug:$slug, target:$t,
                   origin_stage:"PL", dedupe_key:$dk}}' \
       >> .context/logs/audit.jsonl
   fi
   ```

#### Step 3c — post-check invariants

**The post-check MUST NOT block planning** — a warning row and nothing else: no STOP, no retry, no
rename (a rename here would violate the once-only rule). The convention row MUST name **both** the
stamped branch and the derived target, so the divergence is legible without re-deriving it. An empty
`facts.branch` is a documented outcome (detached HEAD, not a git repo), not a warning; an empty
`derived_target` means a guard arm short-circuited before derivation. A non-empty `derived_target`
there is a **bug report**: a conventional target existed and something stamped past it.

### Step 4 — attach PL0 metadata

4. The Step 3a seed already created `tasks.PL0`, so this step MERGES metadata rather than creating
the task — `--task-create` would hit the create op's idempotent early-exit and drop the payload
silently. `state-patch.sh --task-meta PL0 --set '{"stage":"PL","agent":"corpflow:product-manager","model":"opus","worktask_id":"<slug>","priority":"<priority>","plan_gate":"checkpoint","decision_gate":"user","fn_gate":"checkpoint","isolation":"worktree","workspace_path":"<resolved root>","description":"<task description>"}'`
— `metadata.agent` MUST use fully-qualified `plugin:agent` form (`corpflow:`, `apple-developer:`, …).

#### Step 4 — workspace_path stamping

`workspace_path` carries the Step 3a value and is stamped on **every** run beside `isolation`, not
only under `/megatask`; PM propagates it to every stage task. It tells a stage agent which tree it
was *assigned* — a different claim from the tree it resolved (`workspace-modes.md § Sibling-worktree
hazard`).

#### Step 4 — gate stamping

Gate defaults (`plan_gate: "checkpoint"`, `decision_gate: "user"`, `fn_gate: "checkpoint"`) stamp
unless a flag overrides. They are the carriers resume logic branches on (`resume.md § State → Action
Table`); `/megatask` stamps them directly per issue.

| Alternate | Stamp ONLY when | Notes |
|---|---|---|
| `plan_gate: "bypass"` | `--auto` contains `plan`, OR `--emergency` | Emergency runs unattended from IR |
| `fn_gate: "bypass"` | `--auto` contains `finalization`, OR `--emergency` | `--auto=[plan]` MUST NEVER stamp this — orthogonal carriers. Enforced at SKILL.md loop step 4.9 |
| `decision_gate: "auto"` | `--auto` contains `decision` | `--emergency` leaves it `"user"` (no PL stage, carrier inert) |

#### Step 4 — decision_gate readers

`decision_gate` has two readers: the PM agent (returns questions in `open_questions[]` rather than
holding a gate round-trip — `skills/worktask/references/pl0-procedure.md § Plan-Gate Open-Question
Batching`) and Step A.4.

### Steps 5–8 — Dispatch PL, then present the plan

5. **PL0 → in_progress**: `state-patch.sh --task-status PL0 in_progress`
6. **Delegate**: `Task({ subagent_type: "corpflow:product-manager", prompt: "<planning prompt>" })`
   — PM computes the next free plan filename (`pl0-procedure.md § Plan File & Run Index Naming`:
   glob+increment `.context/planning-0.md`, `planning-1.md`, …), writes it, assesses complexity, and
   creates stage tasks with `metadata.agent` AND `metadata.plan_file`. The seeded
   `plan_file`/`run_index` are provisional — PM recomputes and is authoritative. Glob+increment
   applies to a **new run** only: a plan-gate revision reuses the frozen index (§ Plan-revision
   re-dispatch).
7. **PL0 → completed**: `state-patch.sh --task-status PL0 completed`
8. **Present the plan summary** (contents per § Plan gate checkpoint path), then continue to Phase 2.

#### Step 6 — record dropped and added stages

When dynamic sizing omits any of the full 9-stage pipeline (`PL→AR→TL→DV→DR→QA→DC→FN→ST`), PM stamps
PL0's `metadata.skipped_stages` (`{stage, reason}` list) so `state.json` self-documents the drops;
a stage included beyond the tier default (AR0 at a low tier, TL0 at any tier) stamps the symmetric
`metadata.added_stages`, identical shape (`pl0-procedure.md § Dynamic Worktask Sizing (PL0 Stage)`).

## Phase 2: Execute Stages (proceeds automatically)

Phase 2 begins with the Auto-Decision Pre-Pass (Step A.4, no-op unless `decision_gate == "auto"` AND
PL0 left open questions), then the Plan Gate Check (Step A.5): on `checkpoint` present the plan and
wait for approval before the stage loop; on `bypass` proceed directly.

### Step A.4 — Auto-Decision Pre-Pass (runs before Step A.5)

Read `tasks.PL0.metadata.decision_gate` (default `"user"`) and, from `facts.open_questions[]`, PL's
unresolved `sw-PL<N>-*` items — those whose `status` is not `"resolved"`
(`pl0-procedure.md § Plan-Gate Open-Question Batching`). Resolve each item's question text and
`options[]` from `planning-N.md#elicitation-sweep` exactly as § Step C.4 does; the stub carries
neither. **No-op** when `decision_gate == "user"` or no such item exists — fall through to
Step A.5. Otherwise, run § Step A.4 — the delegate dispatch.

#### Step A.4 — the delegate dispatch

1. Append an `auto_decision_dispatched` audit row (`subject:"PL<N>"`, `metadata.questions: <count>`).
2. Re-dispatch PM as a decision delegate on the **Fable model**:
   `Task({ subagent_type: "corpflow:product-manager", model: "fable", prompt: <decision prompt> })`,
   the prompt carrying the open-question list verbatim (each with its recommended default) and the
   plan file path. **Model fallback**: loop step 5f exactly — if
   `facts.capabilities.fable_dispatch == "credit_blocked"`, dispatch on `"opus"` and audit
   `model_resolution_constrained`.

#### Step A.4 stamps no approval carrier

The asymmetry with Step A.5 is deliberate: this pre-pass bypasses no gate. Resolving open questions
answers plan content, it does not approve the plan, and every path out of here falls through to
Step A.5, the sole stamping point. A stamp here would approve a run whose `plan_gate` is still
`checkpoint`, before any human has seen the plan.

#### Auto-decision recording contract

The delegate decides every non-escalation question (default-biased — deviate from PM's recommended
default only with stated evidence), applies the amendments to the plan's EXISTING mandatory anchors
(`## requirements` / `## acceptance-criteria` / `## scope`) in ONE batch pass, and returns each
decision as a typed-return `key_decisions[]` entry prefixed `(auto-decided)`, plus any `escalate`
items. It adds NO new anchor (`handoff-protocol.md § #anchor-allow-list`) and does NOT re-run
`state-patch.sh`: PL0 is already `completed`, so the plan amendments are its only writes.

#### Auto-decision ledger merge (orchestrator)

3. On return the ORCHESTRATOR — not the delegate — merges via `atomicMergeStateJson`: mark each
   answered `facts.open_questions[]` item `status: "resolved"` with its `resolution` (the § Step C.5
   write — the whole stub, never `{id, status, resolution}` alone). That write is the **only** one:
   there is no second append to `facts.decisions[]`. § Step C.5 sends sweep answers to `resolution`
   and nowhere else, and the record survives because every stage extracts `facts.open_questions[]`
   on entry (`skills/shared/stage-contracts.md § Required Inputs`), so no downstream reader loses
   the answer. Entries are marked resolved, **never removed** — a deleted item takes its `ref`
   anchor and its answer with it.

##### Auto-decision ledger merge — the audit row

4. Append one `auto_decision_resolved` audit row (`subject:"PL<N>"`, `metadata: { decided: <count>,
   escalated: <count>, model_resolved: <alias>, decisions: [{question, answer, rationale}] }`) — the
   per-question rationale is carried there, one line each.

#### Escalation guard (BINDING)

The delegate MUST NOT auto-decide **escalation-class** questions: anything irreversible or
destructive (data deletion, force-push, external publication), scope-expanding beyond the task
description, security-posture-weakening, or spend-authorizing. Those return as `escalate` items. If
any exist, Step A.5 runs as a **`checkpoint`** gate for those items even under `plan_gate ==
"bypass"` — the user answers only the escalated questions, the batch amendment pass applies their
answers, then the bypass path resumes. Auto-decision never widens what runs unattended.

##### Escalation guard — raise-only self-labels

A closing-sweep item arrives carrying its emitting stage's own `class`. At § Step C.2, strictly
before any auto-answer, join it with the orchestrator's own label on both axes — `class` and
`blocks_next_stage` — and carry the joined value forward, so no item reaches the delegate
un-reclassified. The escalation classes are the four enumerated directly above; this sub-heading
adds no second copy of them.

The join is over **labellers, never transports**: never an agent's artifact stub against its own
ledger stub. Those two copies have one author, so a disagreement is a defect —
`handoff-harness.sh check_sweep_ledger` fails the stage and the agent reconciles both.

The join itself, both axes, and why raise-only holds by construction rather than by a remembered
rule: `skills/shared/stage-contracts.md § Self-labels raise, never lower`.

##### Escalation guard — unattended `/megatask` per-issue runs (PARK)

Under a `/megatask` per-issue run (detected by `PL0.metadata.megatask_group`) there is no user to
stop for, so instead of holding the checkpoint, **PARK the issue**: write
`workspace.json.execution.status: "failed"` with `execution.reason: "parked_escalation"`, append an
`escalation_parked` audit row (`subject:"PL<N>"`, `metadata.escalated: [<questions>]`), and STOP
without dispatching any stage. Parking rides the monitor's failure path
(`hooks/megatask-monitor.sh` settles only `completed`/`failed`): the track is freed, dependents stay
`blocked`, and the batch summary lists the issue with its unanswered questions for a follow-up
interactive `/worktask`.

#### Presentation in the gate summary

On a `checkpoint` plan gate the Step A.5 summary MUST list every auto-decided question with its
answer marked `(auto-decided by Fable — see facts.open_questions[].resolution / audit)`, so the user
approves the decisions together with the plan. On `bypass`, the `auto_decision_resolved` audit rows
plus each item's own `resolution` are the durable record.

### Step A.4b — Refine the branch target (after A.4, before A.5)

The Step 3c name predates the plan. Now that the approved plan carries its own `title:`, re-derive
the **planned remote target** from it — at most once per run, only while no commit exists to
disagree. This step **performs no git mutation**: it rewrites `facts.branch` on the ledger and
nothing else, leaving the once-only *rename* rule unaffected (`git-conventions.md § Once-only
rule`). Placed here so the Step A.5 summary carries the final name before anything is published.

#### Step A.4b snippet — invoke the helper, non-blocking

    # $PLUGIN_ROOT per § Snippet preamble
    HELPER="$PLUGIN_ROOT/skills/worktask/scripts/refine-branch-target.sh"
    ref_out=""; if [ -f "$HELPER" ]; then ref_out=$(bash "$HELPER") || true; fi
    ledger_branch=$(printf '%s\n' "$ref_out" | sed -n 's/^ledger_branch=//p' | tail -n 1)

#### Step A.4b invariants

- The trailing `|| true` is mandatory — non-blocking by contract, like the Step A publish helper. A
  helper failure does not fail the worktask.
- **Self-guarding**: it scans `audit.jsonl` for a prior successful `branch_target_refined` row at
  this run index, so a duplicate invocation after a resume is a `noop`, never a second refinement.
- Exactly one audit row per invocation **whenever `jq` is available**; the `jq_unavailable` arm alone
  writes none, announcing itself on stdout (matching `branch-lib.sh audit_fn`).
- The row is `branch_target_refined`, `ok` or `noop` with a reason from its closed set. A `noop` is
  normal: the helper declines when a commit exists, an upstream is configured, the plan carries no
  `title:`, the candidate is unusable or unchanged, or it would truncate while the incumbent has no
  recorded truncation.

#### Step A.4b — the returned value

- `ledger_branch` is the value on the ledger **after** this step, refined or not. Use it in the Step
  A.5 summary rather than re-reading `state.json`.
- FN's re-validation of `facts.branch` against `^[A-Za-z0-9._/-]+$` is unchanged and still runs — the
  refined value passes the identical check because FN reads the ledger.

### Step A.5 — Plan Gate Check (after A.4, before Step A publish)

Read `tasks.PL0.metadata.plan_gate` (default `"checkpoint"`). Resolve the run index `N` from
`state.json.run_index` (default `0`).

#### Plan gate checkpoint path

**If `plan_gate == "checkpoint"`** (default):
1. Read `state.json.plan_file` to locate the plan; accept either shape (`handoff-protocol.md §
   plan_file shape boundary`).
2. Present the plan summary: complexity score, stages created (with agents), dependency chain, key
   decisions, and both inclusion decisions (below).

##### Plan gate checkpoint path — the sweep render

2b. Render PL's unresolved sweep items FIRST — every `facts.open_questions[]` item whose id matches
   `sw-PL<N>-*` and whose `status` is not `"resolved"` — through § Step C.4 (question text and
   `options[]` from `planning-N.md#elicitation-sweep`) and record the answers through § Step C.5,
   with `subject:"PL<N>"` on every audit row. These are separate `AskUserQuestion` calls; the
   approve/reject call in step 3 fires **last and unmodified**, exactly as at the FN gate.

##### Plan gate checkpoint path — the approval call

3. `AskUserQuestion`: *"Here is the generated plan for your worktask. Approve to begin
   implementation, or describe any changes you want first."* The gate holds until a human answers.
   Keep the `/config` idle-timeout opt-in OFF on hosts running gated worktasks — an idle auto-answer
   would count as an approval the operator never gave, and a background-task completion notification
   (which states that no human input occurred) is never this approval either.

##### What counts as approval — and what does not

The gate holds for an **explicit human answer to this call**. Three things that routinely look like
approval are not:

- **A subagent returning `verdict: ok`.** PL0 finishing means the plan exists, not that anyone
  accepted it. No agent can approve on the user's behalf, and no message from one is the user's
  consent.
- **A background-task completion notification**, which states on its face that no human input
  occurred (see the idle-timeout note in step 3).
- **A free-text reply that is a question.** "Wait, explain the AR exclusion first" is a question:
  answer it and re-present the gate. Same rule as `commands/megatask.md § R1 outcomes`.

Only the user's own answer, or `plan_gate == "bypass"` set before the run, moves past this point.
Recording `approval_received` on anything else fabricates the one row an operator relies on to know
a human saw the plan.

##### Stage-inclusion decisions in the gate summary

The step-2 summary MUST show both decisions explicitly, each with its one-line reason drawn from
`skipped_stages`/`added_stages`:

- **AR** — included or excluded, and whether that deviates from the tier default (flag the
  deviation; a tier-default AR still states its reason for being kept).
- **TL** — included or excluded on the split-work test, naming the workstreams when included.

##### Branch name in the gate summary

It MUST also show `Branch (PR head): <ledger_branch>` (the Step A.4b value), so the user sees the
name the PR will carry before anything is published. An empty `ledger_branch=` means **unknown**, not
absent: the `jq_unavailable` arm prints it empty even when a good name is stamped — so on empty, read
`facts.branch` directly and print `Branch (PR head): — (none planned)` only if that read is also
empty.

##### Branch name in the gate summary — conditional additions

- `⚠ name truncated at 48 chars (<input_len> chars of input)` when a `branch_slug_truncated` row
  exists for `PL<N>` (the Step 3c row).
- `(refined from <old> via plan title)` when the Step A.4b row is `result: "ok"`.
- `⚠ renamed inside a linked worktree — your host's workspace↔branch mapping may need to re-sync;
  set BRANCH_NAME_WORKTREE_RENAME=0 to keep the host's name` when the Step 3c `branch_renamed / ok`
  row carries `in_worktree: "true"` — reporting the Step 3c rename, not asking; reversible with
  `git branch -m <original>`.

This is the last point at which a name is free to change: a user who dislikes it says so here, and
the plan revision path re-derives nothing (§ Plan-revision invariants row 5).

#### Plan gate approval / rejection audit rows

4. **On approval**, first stamp the carrier: `state-patch.sh --task-meta PL0 --set '{"approved":"user"}'`.
   The stamp precedes the row by contract — a crash between them leaves state approving with no row,
   and the resume path re-prompts a human; the reverse order resumes into the stage loop with the
   carrier unset, which is the block this stamp exists to prevent. Then append one line to
   `.context/logs/audit.jsonl` and proceed to Step A:
   ```json
   {"ts":"<ISO>","actor":"orchestrator","action":"approval_received","subject":"PL<N>","result":"ok"}
   ```
5. **On rejection / revision request**, append:
   ```json
   {"ts":"<ISO>","actor":"orchestrator","action":"approval_rejected","subject":"PL<N>","result":"rejected"}
   ```
   STOP — do NOT enter the stage loop. Surface the user's feedback. For revisions, re-dispatch PM per
   § Plan-revision re-dispatch — a revision is NOT a new run.

##### Plan-revision re-dispatch (gate rejection only)

A gate rejection revises the run **in flight**. `run_index` and `plan_file` are FROZEN for the life
of a run — allocating `planning-<N+1>.md` forks the plan, wipes the `facts.decisions[]` the user just
supplied, strands the stage-task chain on the old index, and splits the published-issue record.
Re-dispatch product-manager with `plan_revision: true` in the prompt, carrying the feedback verbatim.
PM's own arm: `pl0-procedure.md § Revision of the run in flight`.

##### Plan-revision invariants (BINDING)

| # | Do | Never |
|---|---|---|
| 1 | Edit the existing `planning-<N>.md` in place | Allocate `planning-<N+1>.md` |
| 2 | Patch `facts.*` additively — `facts.decisions[]` survives | Run the state.json reset |
| 3 | Patch the existing stage tasks | Seed a second stage chain |
| 4 | Leave the published GitHub issue as-is | Re-publish or re-anchor the issue |
| 5 | Leave the refined `facts.branch` as-is | Re-run Step A.4b — a revision is not a new naming window |

##### Plan-revision bookkeeping

Set PL0 back to `in_progress`, increment `metadata.revision_count` (absent → `1`), and append exactly
one audit row before dispatching:

```json
{"ts":"<ISO>","actor":"orchestrator","action":"plan_revision_dispatched","subject":"PL<N>","result":"ok","metadata":{"revision_count":<count>}}
```

On PM's return, re-enter the plan gate at Step A.5 — the revised plan needs its own approval, and
Step A still runs exactly once per run (the issue is published after the *approved* plan).

#### Plan gate bypass path

**If `plan_gate == "bypass"` AND Step A.4 left no unresolved `escalate` items**: stamp
`state-patch.sh --task-meta PL0 --set '{"approved":"auto"}'`, then proceed directly to Step A. No
prompt, no approval line, no audit row — the requested bypass carrier IS the approval, and without
the stamp every stage agent blocks. The guard is a precondition: stamping ahead of the stop lets a
crash resume into the stage loop with escalation-class questions unanswered and the check passing.

Exception: unresolved `escalate` items force a `checkpoint`-style stop first (§ Escalation guard).
Once answered, stamp `state-patch.sh --task-meta PL0 --set '{"approved":"user"}'`, then append the
standard `approval_received subject:"PL<N>"` row (required as the escalate resolution), then resume
at Step A — NOT at the arm above, which this run can no longer reach: re-entering it would overwrite
a real human approval with `auto`. Stamp before row, as in the approval arm.

### Step A — Publish plan to GitHub (run BEFORE the stage loop)

    # $PLUGIN_ROOT per § Snippet preamble
    HELPER="$PLUGIN_ROOT/skills/worktask/scripts/publish-pl-issue.sh"

#### Step A snippet — continued: invoke helper, or audit a deferred row

    if [ -f "$HELPER" ]; then
      bash "$HELPER"; true
    else
      LOG_DIR="${WORKSPACE_ROOT:-${CLAUDE_PROJECT_DIR:-.}}/.context/logs"
      mkdir -p "$LOG_DIR"
      STATE_FILE="${WORKSPACE_ROOT:-${CLAUDE_PROJECT_DIR:-.}}/.context/state.json"
      jq -cn --arg ts "$(date -u +%FT%TZ)" --arg dk "$(jq -r '.worktask_id // "unknown"' "$STATE_FILE" 2>/dev/null || echo unknown):$(jq -r '.run_index // 0' "$STATE_FILE" 2>/dev/null || echo 0):gh_issue" \
        '{ts:$ts, actor:"orchestrator", action:"github_issue_created", subject:"PL0", result:"deferred", task_id:"1", metadata:{via:"publish-pl-issue.sh", reason:"helper_not_found", dedupe_key:$dk}}' \
        >> "$LOG_DIR/audit.jsonl"; true
    fi

#### Step A publish invariants

- The trailing `; true` is mandatory — non-blocking by contract. A helper failure does not fail the
  worktask.
- The helper self-skips (`--no-gh-issue`; megatask per-issue mode, detected via `workspace.json` /
  `metadata.milestone`; already published; missing `gh`/auth/remote) — each exits 0 and audits a
  `deferred` row. Sanitiser rules: `skills/worktask/SKILL.md § PL Issue Publish`.
- One `.context/` ↔ one GitHub issue: a later run resolves the run-independent
  `.context/gh-issue.json` anchor and comments instead of duplicating (`skills/gh-issue-dedup`).
- This step is NOT optional. Do not skip it because SKILL.md describes it — run the command as
  written.

#### After Step A — run the stage loop

Execute the loop from `skills/worktask/SKILL.md § Orchestrator Execution Loop`. Before the FN
`Task()` delegation apply the FN gate check (STOP on `checkpoint`, proceed on `bypass`) —
`skills/worktask/SKILL.md § FN Gate`.

#### Workspace-root cross-check (BINDING)

Conductor-managed sessions spawn the orchestrator inside a workspace clone whose `pwd` differs from
the canonical plugin source repo. Before every `Task()` call in the stage loop the orchestrator MUST
verify that the working tree matches the task's declared workspace, and MUST inject the resolved root
into the stage prompt so the subagent targets the right directory.

##### Cross-check snippet

```bash
# Runs in the orchestrator turn, not in the subagent
_orch_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
_task_root=$(jq -r '.metadata.workspace_path // empty' .context/state.json)
# Unset is a DEFECT, not a mode: defaulting it to $_orch_root compares a value to itself,
# so the check passes unconditionally and an unstamped ledger reads as clean — which also
# leaves dv-tree-preflight.sh and developer.md's path-prefix check inert.
if [ -z "$_task_root" ]; then
  echo "⚠ state.json has no .metadata.workspace_path — the assigned-tree guards are ALL inert. Re-seed per Step 3a." >&2
  # Write audit row `workspace_path_unstamped` and STOP — do not call Task()
  exit 1
fi
if [ "$_orch_root" != "$_task_root" ]; then
  echo "⚠ cwd mismatch: orchestrator is at $_orch_root but task.metadata.workspace_path is $_task_root. Aborting delegation until resolved." >&2
  # Write audit row and STOP — do not call Task()
  exit 1
fi
```

##### Banner injection

The orchestrator MUST also append the task's `WORKSPACE_ROOT=` line as the first line of every stage
prompt banner (section [7] suffix per the cache-prefix spec) so the subagent knows which directory to
target. The value is `tasks.<ID>.metadata.workspace_path` when set, else the orchestrator root —
never the ledger-level path, which names the orchestrator's tree and hides a DV stream's own:

```bash
bash skills/worktask/scripts/workspace-root-banner.sh --task "<TASK_ID>" --orch-root "$_orch_root"
# stdout is the banner line verbatim; exit 2 (unknown task id) means do not call Task()
```

Failure mode prevented: `workspace-modes.md § Conductor Workspace Topology`.

#### Post-delegation state.json enforcement (BINDING)

After every `Task()` return (the *completed stage result* — under background-default subagents that
is the completion notification, not the launch acknowledgement), before Step 7 settles the row:
re-read `.context/state.json`; if `tasks.<ID>` does not already carry the artifact's
`handoff.verdict` and the status it maps to (`handoff-protocol.md § tasks — verdict → status`), run
   ```bash
   CLAUDE_ARTIFACT_PATH=".context/<artifact>-N.md" \
   CLAUDE_TASK_METADATA_STAGE="<CODE>" \
   STATE_MERGE_VIA=step6_5 \
   bash .claude/hooks/state-merge.sh
   ```

##### Layer-3 stamp and F3 fallback

`STATE_MERGE_VIA=step6_5` stamps `tasks.<ID>.completed_via=step6_5` so this synchronous Layer-3 path
is distinguishable from the SubagentStop-hook Layer-2 default (`hook`). Then re-read; if the row
STILL does not match, apply the F3 fallback: it stamps the verdict-mapped status (plus
`metadata.gate_from_stage` when that status is `pending`) with `completed_via: "f3"`, and writes
nothing for an absent handoff or an unmapped verdict — this covers environments where the
SubagentStop hook never fired. Full
three-layer logic: `skills/worktask/SKILL.md § Orchestrator Execution Loop` Step 6.5.

### Step B — AR-reference check at DV completion

The AR-reference arm fires only when `.context/state.json` has a `tasks.AR0` entry (AR is optional —
`skills/estimation-methodology/SKILL.md § Stage Inclusion Criteria`). The invocation itself is the
§ Step B.1 call every stage makes. It runs once per DV row, on that row's own artifact, as the row
completes; DR0 is dispatched only after every DV row has passed it:

```bash
STRICT_FLAG=""
[ "${CORPFLOW_AR_REF_STRICT:-0}" = "1" ] && STRICT_FLAG="--strict"
# The completing row names its artifact; a stream suffix cannot be composed from N.
DEV_ARTIFACT=$(jq -r --arg id "$TASK_ID" \
  '.tasks[$id] | .artifact // .metadata.artifact // empty' .context/state.json)
# shellcheck disable=SC2086
skills/worktask/scripts/handoff-harness.sh --validate-frontmatter "$DEV_ARTIFACT" \
  --state .context/state.json $STRICT_FLAG
```

#### Step B rollout and opt-in

**Rollout — warn-only in 3.42.0.** With no opt-in the harness emits `warn:` lines and exits 0. Record
each as an audit row and carry it into the DR dispatch prompt so DR checks the linkage; a warning is
**not** a `missing_input` block and never stops the transition.

```json
{"ts":"<ISO>","actor":"orchestrator","action":"ar_ref_check","subject":"DV<k>","result":"warn"}
```

##### Step B — what the sweep checks do to this rollout

**The warn-only rollout covers the AR-reference check only.** The same invocation also runs the
three closing-sweep checks (stub shape, `ref` anchor resolution, ledger parity), which **hard-fail
regardless of `--strict`** — the sweep obligation is strict from its first release
(`skills/shared/stage-contracts.md § Closing Elicitation Sweep`). A non-zero exit here is therefore
not necessarily an AR-reference failure; a sweep failure blocks the transition per § Step B.1 — on
failure, and its `fail:` line names a `sw-` id.

**Early opt-in — `CORPFLOW_AR_REF_STRICT=1`.** The orchestrator passes `--strict`; violations become
`fail:` lines with exit 1 and block the DR dispatch until DV fixes the reference. Use it to shake out
dangling references before the next minor flips `--strict` to the default. The inverse guard (an
architecture reference with no `tasks.AR0` entry) warns in both modes and never fails.

### Step B.1 — Sweep checks at every stage completion

The harness is not a DV-only tool. After **any** stage `<CODE><N>` lands its `completed` patch (loop
step 6.5) and before § Step C.0 renders its blocking items or the next stage is dispatched, run:

```bash
ART=$(jq -r --arg id "<CODE><N>" '.tasks[$id].artifact // empty' .context/state.json)
skills/worktask/scripts/handoff-harness.sh --validate-frontmatter "$ART" --state .context/state.json
```

`$STRICT_FLAG` from § Step B may be appended; it affects only the AR-reference arm, which fires for DV
alone. For DV this **is** the § Step B invocation — run it once, not twice. An artifact whose
`open_questions` is the empty array passes untouched; any item in it must be a full sweep stub.

#### Step B.1 — on failure

Exit 0 → append `{"action":"sweep_check","subject":"<CODE><N>","result":"ok"}` and continue to
§ Step C.0.

**Any non-zero exit** → append the same row with `result:"fail"` and every `fail:` line as
`reason`, then treat it as a `missing_input` contract violation on `<CODE><N>`: do **not** run Step
C.0, do **not** dispatch the next stage; re-dispatch the stage with the `fail:` lines verbatim so it
writes what it owes. There is no advisory tier here — the unreadable-ledger case fails too.

##### Step B.1 — the routing default, and why it is a default

The default is the rule, not a fallback: a shape absent from this table routes like every row in
it. An earlier version routed only the first three, so one run's boundary stalled four times on
lines that each named a real defect and had no branch to take.

| `fail:` line names | What the stage owes |
|---|---|
| a `sw-` id | the missing stub, its `ref` anchor, or its `--facts` entry |
| `sweep ledger parity cannot be verified` | a readable ledger or spill, then re-run |
| a decision id `disagrees across transports` | one reconciled statement — see the arm below |
| `missing required field: <field>` | that field, per `stage-contracts.md#tpl-<CODE>` |
| `tests_executed: 0 with no test_suite_compiles` | the compile answer — no test authority needed |
| `N discretionary tokens > 200 budget` | a shorter `summary` / `next_stage_focus` |
| anything else | what the line says — route it here regardless |

##### Step B.1 — the `key_decisions` divergence arm

Not every failure names a `sw-` id. `check_decision_divergence` compares each `key_decisions[]`
summary against the same id's entry in the artifact body and fails with

```
fail: decision <id> disagrees across transports — frontmatter says "…" but the <artifact> body says "…"
```

which names a **decision** id and mentions neither a sweep id nor ledger parity. It has its own row
in the table above, and would route correctly on the default arm even without one — but the fix it
asks for differs from every other row's, which is what the next section is for.

###### Step B.1 — routing the divergence failure

Routing is the default: `result:"fail"` with the line as `reason`, no Step C.0, no next stage,
re-dispatch with the `fail:` line verbatim. What differs is the fix the stage owes — the two transports are reconciled to **one** statement, and the artifact body is the author's
copy. Never settle it by deleting the body entry: that removes the reader's only expansion of the
id.

The harness collects every failure it can reach in one invocation, so a single re-dispatch may carry
a sweep line and a decision line together. Pass **every** `fail:` line, not the first.

###### Step B.1 — shape failures short-circuit

"Every failure" is bounded by what stays parseable. A non-sequence `open_questions`, a missing
`handoff:` block and an unknown stage each stop the checks at that point, because every later check
reads the structure the failed one was validating.

So a re-dispatch that fixes a shape line can legitimately return new failures that were always
present and unreachable. That is the check working, not the stage regressing. Do not treat the
second round as a new defect, and do not promise a stage one-shot batching when its first line is a
shape line.

### Step C — Closing-sweep collection and render (loop step 4.9)

Step C is to the FN gate what Step A.4 is to the plan gate: it resolves questions, it approves
nothing, and every path out of it falls through to the gate's own approve/reject call. Contract:
`skills/shared/stage-contracts.md § Closing Elicitation Sweep`.

It has **two firing points**, selected per item by `blocks_next_stage`, never by stage:

- **C.0a** runs first at every stage boundary *except* PL/FN/ST/IR, resolving that stage's
  blocking `decision` items through a sub-agent so the run does not stop for them at all.
- **C.0** runs at *every* stage boundary, immediately after that stage's `completed` patch and
  before the next stage is dispatched, over whatever blocking items C.0a did not settle.
- **C.1–C.5** run once, immediately before the FN `Task()` delegation, over everything else.

#### Step C.0a — resolve blocking items instead of asking (loop step 4.9, first)

Contract: `skills/shared/stage-contracts.md § Blocking items are resolved, not asked`.

After any stage `<CODE><N>` completes, and **before** § Step C.0, collect the items it just wrote
that satisfy **all four**:

1. `<CODE>` ∉ {PL, FN, ST, IR} — the four exception stages keep their own surfacing
   (`stage-contracts.md § Exceptions — PL, FN, ST, IR`), so there is nothing here to unblock.
2. `blocks_next_stage` is true and `status` is not `"resolved"`.
3. `effective_class == "decision"` **after** the § Step C.2 raise-only join. Run C.2 first, on
   this set, exactly as C.1–C.5 does — an item the orchestrator raises to `escalate` must never
   reach a delegate.
4. `decision_gate == "auto"`.

Empty set ⇒ no-op, fall through to § Step C.0 unchanged.

##### Step C.0a — the resolver dispatch

1. Compute the tier. Read `tasks.<CODE><N>.metadata.effort` and `.model` — the ledger, never the
   agent's frontmatter, because a stage dispatched at an override runs at a tier its frontmatter
   never mentions. Source `skills/worktask/scripts/effort-ladder.sh` and call
   `effort_for_resolver "<effort>" "<model>"`; it bumps one rung and applies the non-Opus clamp.
   A stage row with no `metadata.effort` is a **contract violation, not a default** — fall through
   to § Step C.0 and audit `resolver_skipped` with `reason: "effort_unstamped"` rather than
   guessing a tier.
2. Append `auto_decision_dispatched` (`subject:"<CODE><N>"`, `metadata: { questions: <count>,
   effort_requested: <tier>, effort_clamped: <bool> }`).
3. Dispatch **the emitting stage's own agent** on **its own model** at the computed tier. One
   dispatch per boundary over the whole set (≤4 by the per-stage cap) — never one per item.

##### Step C.0a — the tier only reaches some dispatch surfaces

`metadata.effort` is **not** honoured in-process — `headless-dispatch.md § Translation table —
model & effort` marks `model` "Yes (passed to `Task()`)" and `effort` "Advisory". The audit row
must say which surface it got:

| Surface | Carries the tier by | `effort_transport` |
|---|---|---|
| headless `claude agents run` | `--effort <tier>` | `dispatch-flag` |
| in-process `Task()` | nothing — the sub-agent runs at its own frontmatter `effort:` | `frontmatter-only` |

In-process the tier is **recorded, not applied**, and the resolver still runs.

###### Step C.0a — do not reach the tier another way

Never substitute a different agent whose frontmatter sits a rung higher: that trades the domain
expertise answering the question for a field value. `Task()` gains no `effort` parameter here and
none is invented; if one lands later, the table above is the only place that changes.

##### Step C.0a — what the prompt carries

Paths, not inlined content — the § Step A.4 convention. Resolve artifact filenames through
`handoff-protocol.md #stage-artifact-map`; build no second mapping. The context tiers are
enumerated once, in `stage-contracts.md § What the resolver is given`, and are not restated here.

The delegate answers each item default-biased — deviate from the stage's own `recommended` entry
only with stated evidence — and returns one entry per item plus any it declines. It declares its
full reads through `deep_reads` (exempt from the B4 tripwire, per that section) and runs
`state-patch.sh` **not at all**: the stage is already `completed`, so the orchestrator owns every
write, exactly as at Step A.4.

##### Step C.0a — record, then fall through

4. The ORCHESTRATOR merges each answer through the § Step C.5 write — the whole stub, resolution
   marked `(auto-decided)` — and appends one `auto_decision_resolved` row (`subject:"<CODE><N>"`,
   `metadata: { decided, declined, model_resolved, effort_requested, effort_resolved,
   effort_transport, decisions: [{question, answer, rationale}] }`).
5. Fall through to § Step C.0 with whatever remains: every `escalate` item, everything the
   delegate declined, and everything C.0a's four conditions excluded.

###### Step C.0a — reading the two effort fields

`effort_requested` != `effort_resolved` means the tier evaporated in transit — thinking disabled
downgrades `xhigh`/`max` to `high` silently (`model-selection.md § xhigh routing`). Recorded, not
enforced: the answer stands, it just was not reached at the tier asked for. Read it with
`effort_transport` — under `frontmatter-only` the request never left the orchestrator, so a
difference there says nothing about the session.

##### Step C.0a stamps no approval carrier

Same asymmetry as Step A.4 and Step C: resolving an item settles implementation content, it
approves nothing. Nothing here writes an approval carrier, and both gates keep their existing
firing conditions.

#### Step C.0 — blocking items, at their own boundary

After any stage `<CODE><N>` completes, read the items it just wrote whose `blocks_next_stage` is
true and whose `status` is not `"resolved"` — after § Step C.0a has had its pass, so on the nine
non-exception stages this set is what a resolver could not or must not settle. If none, Step C.0 is
a no-op and the loop proceeds unchanged. Do not assume that is the common case: a single observed
run raised 16 sweep items across four stages, 7 of them blocking, which is what Step C.0a exists
to absorb. Otherwise run C.2 through C.5 on exactly those items, with
`subject:"<CODE><N>"` on every audit row, and only then dispatch the next stage. The next stage would
otherwise build on a guess, which is the whole reason the flag exists.

##### Step C.0 — no new gate, and no deadlock

This creates **no new gate**: it is the same render the FN gate performs, moved earlier for items
whose answers the next stage needs. Under a bypassed lane it degrades exactly as C.5 specifies —
record, never prompt — so no unattended run can deadlock on it.

#### Step C.1 — collect everything not already answered

1. **C.1 — Collect.** Read `facts.open_questions[]` **unioned with the eviction spill** (below) and
   keep the items whose `status` is not `"resolved"`. That status test is the whole filter: an item already answered at its own
   boundary (C.0) or at the plan gate is resolved, so it is excluded by the same rule that excludes
   PL's. Do **not** filter on stage — under `blocks_next_stage` any stage can be answered at its own
   boundary, so a stage-name exclusion would be both wrong and incomplete. **Derive the stage from
   the item id**, whose `sw-<TASK_ID>-<n>` shape is pinned by the schema, for *grouping* — an
   explicit `stage` field takes precedence when present, but it is optional and absent from every
   template, so nothing may depend on it. Resolve each item's `ref` anchor to its full `options[]`
   body in the emitting stage's artifact.

##### Step C.1 — the collection is ledger ∪ spill

The ledger is not the whole record. `state-patch.sh` clamps `facts.open_questions[]` to the newest
four per task and appends every evicted item to `.context/open-questions-<run_index>.jsonl`
(`stage-contracts.md § Ledger bounds — the overflow spill`), so an item reachable **only** through
the spill is an item this gate would otherwise never render — silently, with no error anywhere.

###### Step C.1 — how the two sources are unioned

Union both sources by `.id`, with the **ledger winning on conflict**: a spill line is a snapshot
taken at eviction time and is necessarily staler than an item the ledger later resolved. A missing
spill file is the empty set. A spill that exists but cannot be parsed is a **failure**, never an
empty set — degrading a parse error to "nothing to collect" is how this gate goes quiet in exactly
the case it exists for. `handoff-harness.sh` checks parity against the same union.

###### Step C.1 — the decisions spill is a different reader

`.context/decisions-<run_index>.jsonl` is **not** read here: this gate renders questions. It is no
longer readerless, though — `state-patch.sh --read-decisions` returns `facts.decisions[] ∪ spill`
under the same union rule, and that is the path for anything asking what this run decided. Reading
`facts.decisions[]` alone under-reports the moment one task records more than eight.

##### Step C.1 — the artifact fallback and its warning

Both machine-readable transports — `handoff.open_questions[]` and `facts.open_questions[]` — can still under-report, so count what the artifacts claim. Every `.context/*-N.md`
carries a `## elicitation-sweep` section and its frontmatter carries the stubs. When the collected
count is **below** the number of sweep stubs on disk, render the collected items and warn, naming
the shortfall and the ids that are missing:

```
warn: FN gate collected 9 sweep items; 11 stubs exist on disk (missing: sw-DV1-2, sw-DR0-1)
```

The warning does not block the gate and does not change what is rendered. It is the tripwire for a
transport that lost an item, and the whole point is that it names the loss instead of leaving a
count nobody compares. Read the stubs from artifact frontmatter, never by re-parsing bodies.

#### Step C.2 — classify before anything answers

2. **C.2 — Classify.** Apply § Escalation guard — raise-only self-labels to every collected item.
   Strictly before C.3.

#### Step C stamps no approval carrier

The asymmetry with the FN gate itself is deliberate and mirrors Step A.4: answering a sweep item
settles plan or implementation content, it does not approve finalization. Nothing here writes an
approval carrier, and the gate's own `AskUserQuestion` still fires last and unmodified.

#### Step C.3–C.4 — auto-answer, then render

3. **C.3 — Auto-answer.** Only when `decision_gate == "auto"`: resolve the
   `effective_class == "decision"` items on the § Step C.0a rule — each item's **own emitting
   stage's** agent and model, at `effort_for_resolver` of that stage's ledger effort — grouping the
   batch by originating stage and issuing one dispatch per group. This step and C.0a share one
   resolver contract: the fable-plus-credit-fallback path C.3 used to carry is gone, and with it
   the `fable_dispatch == "credit_blocked"` branch. Audit `auto_decision_dispatched` →
   `auto_decision_resolved`, `subject:"FN<N>"`, carrying the same effort fields C.0a records. A
   stage row with no `metadata.effort` is skipped exactly as at C.0a (`resolver_skipped`,
   `reason: "effort_unstamped"`) and its items render at C.4.
##### Step C.3 — why Step A.4 is not folded in

A.4 answers PL's items at the plan gate. PL is an exception stage whose boundary *is* that gate,
and under `checkpoint` a user is already present, so it keeps its own PM-on-fable dispatch rather
than joining the resolver contract.

##### Step C.4 — where the question text comes from

4. **C.4 — Render.** Present the remaining items through `AskUserQuestion`, grouped by originating
   stage, in calls of **at most 4 questions** (the tool's per-call ceiling). The question text comes
   from the **resolved `ref` anchor body**, not from the stub — the stub carries no `summary`, and
   `handoff-harness.sh check_sweep_ref_anchor` is what guarantees that anchor exists. Options are
   `options[]` with the `recommended: true` entry marked, and the `rationale` is shown with them. These calls **precede** the gate's approve/reject call and never
   merge into it: a merged call overflows at four-plus items and entangles sweep answers with the
   gate's reject/resume path.

#### Step C.5 — record, and the unattended lanes

5. **C.5 — Record.** Write each answer back into the item itself:
   `facts.open_questions[].status = "resolved"` and `facts.open_questions[].resolution = "<answer>"`,
   plus a `sweep_resolved` audit row whose subject is the boundary that rendered it — `FN<N>` from
   C.1–C.5, `<CODE><N>` from C.0. The union refuses a later downgrade of either field, so recording
   once is enough. Answers do **not** go to
   `facts.decisions[]` — see `skills/shared/stage-contracts.md § Closing Elicitation Sweep` for why
   that destination is refused.

##### Step C.5 — the write-back is a whole stub

The write goes through `state-patch.sh --facts` as the **complete** item — `id`, `class`, `ref` and
`blocks_next_stage` alongside `status` and `resolution` — never as `{id, status, resolution}`. The
union REPLACES the incumbent object for that id, so a partial item would drop the very anchor C.4
resolves its question text from; `--facts` now rejects one by name rather than persisting it.

Where C.2 **raised** either axis, write the raised value to **both** transports — the ledger stub
here, and the emitting stage's artifact frontmatter stub. The two copies have one author and
`check_sweep_ledger` refuses a divergence between them, so a ledger-only write leaves the next
`--validate-frontmatter` failing on a value this step itself created.

##### Step C.5 — the unattended lanes

Recording never stops; only prompting does. Under `fn_gate: "bypass"` skip C.4 and record only —
`sweep_recorded`, plus `sweep_escalation_unprompted` for every effective-`escalate` item. Under a
`/megatask` per-issue run an effective-`escalate` item PARKS the issue exactly as § Escalation
guard — unattended `/megatask` per-issue runs (PARK) specifies. Every one of those audit subjects is
the rendering boundary, `<CODE><N>` — `FN<N>` for a batched item, the emitting stage's own id for a
blocking one. Full carrier table: `skills/shared/stage-contracts.md § Unattended fallbacks`.

## Phase 3: Post-Worktask Self-Improvement

After the loop exits (ST completed), run `skills/worktask/SKILL.md § Post-Worktask
Self-Improvement`:

1. If `.context/learnings.md` is absent → worktask done, terminate.
2. If present → display it and **STOP** until the user checks the boxes of proposals they approve
   (`- [ ]` → `- [x]`). Orchestrator MUST NOT auto-check or assume.
3. On the user's approval reply, re-read `learnings.md`, parse the checked items, and delegate to
   `corpflow:prompt-engineer` (`agents/prompt-engineer.md § Self-Improvement Patch Application`).
4. Each applied proposal becomes its own commit with a `version:` bump on the target frontmatter
   (rollback-safe via `git revert <sha>`).

### Phase 3 key invariants

- Never auto-apply — the user must explicitly check boxes AND signal approval.
- Proposals are scoped to agents/skills/commands that actually participated in this worktask's
  context (`skills/self-improvement/SKILL.md § Step 4`).
- Post-ST audit entry in `.context/logs/audit.jsonl` records `applied_count` and `skipped_count`.

## Embedded Command Detection

Slash commands in the task description (e.g. `/skill-creator`,
`/apple-developer:fix-refactor src/Views/SettingsView.swift`) are **embedded commands** that must be
executed during the appropriate worktask stage.

### Detection and execution

1. Scan the description for `/<plugin:command>` / `/<command>`; match against the Skill tool's
   available skills.
2. Store them in `metadata.embedded_commands` on PL0 and the remaining text as the worktask task,
   preserving the arguments; pass the context to PL0 so the product-manager plans around it.
3. In the loop, a DV task whose PL0 has `metadata.embedded_commands` gets a prompt including
   "Execute embedded command(s) via the Skill tool: `<command>` with args: `<args>`", and the DV
   agent invokes `Skill({skill: "<command>", args: "<args>"})` as part of its implementation work.

Example: `/worktask /skill-creator deep analyze /path/to/source` → task
`"deep analyze /path/to/source"`, `metadata.embedded_commands: "skill-creator"`, DV prompt carrying
`Skill('skill-creator', args='deep analyze /path/to/source')`.

### Leading stacked skills

> When the user stacks slash commands (`/worktask /skill-a do XYZ`), Claude Code itself loads up to 5
> **leading** skills before the turn runs — the embedded command's SKILL instructions may already be
> in context at PL0 time. Extraction into `metadata.embedded_commands` is unchanged, and the DV-stage
> `Skill()` invocation stays mandatory (it is the execution trigger, not a context load). Re-invoking
> an already-loaded skill appends no duplicate copy, so the DV invocation is token-safe.

### Error Handling

Embedded command execution MUST NOT silently fall back to generic DV work. On failure the DV stage
records it and escalates — otherwise the user's intent is lost.

| Failure | Detection | Required Behavior |
|---------|-----------|-------------------|
| Skill name not resolvable | `Skill()` returns "skill not found" | Write `.context/errors/developer.md` entry with `Classification: missing_input`; escalate to TL (or PL if no TL0) |
| Skill execution errors mid-run | Skill tool returns non-success | `retry_count++`, append entry to `.context/errors/developer.md`; if `retry_count == 3`, set `error_escalated_to: "TL"` (or `"PL"` if no TL0) |
| Skill args malformed | Skill rejects at parse | Classification `ambiguous_requirements`; escalate to PL (requires planning revision) |
| Skill produces no artifact expected by downstream stage | stage-contract validation fails | Classification `missing_input`; escalate to the stage whose contract was violated |

#### Prohibited fallback and escalation target

> DV MUST NOT proceed with generic implementation when the embedded command fails. The user
> explicitly requested that worktask by embedding the command; ignoring it is a silent deviation from
> their intent.

The DV agent's prompt template enforces this: on Skill failure it halts and writes an error entry
with `metadata.embedded_command_failure: true` before returning. Escalation target: **TL0 if it
exists** (retry, split the work, or revise approach), otherwise **PL**, which may add TL0, revise the
embedded command choice, or remove the embedding.

## Headless Dispatch (external runners)

External orchestrators (CI, cron, the user's shell) can invoke a single stage via
`claude agents run …` instead of the in-process `Task()` path. PL0 populates the optional dispatch
fields documented in `skills/shared/state-ledger.md § Dispatch metadata`; the runner reads them and
builds the flag string. The copy-paste one-liner (task `task.json` metadata + rendered `prompt.txt`),
the `sonnet`-alias / `--permission-mode manual`↔`default` equivalence, the mandatory
`external_dispatch` audit line, and the CI-only `--dangerously-skip-permissions` caveat live in
`skills/agent-coordination/references/headless-dispatch.md`.

## Output Format

One block per stage as it settles, then the run summary:

~~~markdown
# Worktask: <title> · <worktask_id> · <standard|secure|emergency>

## Stage — <CODE><N> · agent · model/effort · verdict (ok|blocked|escalate)
## Artifact — `.context/<stage>-N.md` plus its `handoff.summary` line, verbatim
## Ledger — the `state-patch.sh` call applied and the task ids it moved
## Gates — plan gate and FN gate: reached, bypassed, or approved (and by whom)
## Result — branch, PR URL, issue closed, follow-up issues filed
~~~

A blocked or escalated stage replaces `## Result` with `## Blocker — what stopped, at which stage,
and the decision the user owes`. The ledger stays resumable either way: `/worktask --resume <ID>`.

## See Also

- `skills/worktask/SKILL.md` — execution loop, dynamic sizing, worktask modes
- `commands/megatask.md` / `skills/megatask/SKILL.md` — multi-issue milestone/array orchestration (the former `--milestone` surface)
- `skills/shared/stage-codes.md` — stage codes and track IDs
- `skills/agent-coordination/references/headless-dispatch.md` — `task.metadata` → `claude agents` flag bridge
- `agents/workflow-engineer.md` — troubleshooting
