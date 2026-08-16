---
name: worktask
description: Initialize a new worktask task with proper folder structure and state-ledger integration
argument-hint: '<task description> [--secure] [--emergency] [--auto=[plan, decision, finalization]]'
version: 0.5.0
model: opus
allowed-tools: Read, Glob, Grep, Bash(mkdir:*), Bash(gh:*), Bash(git:*), Bash(bash skills/worktask/scripts/state-patch.sh:*), Bash(bash skills/worktask/scripts/preflight-issue-scan.sh:*), Task(corpflow:product-manager)
---

> **EXECUTION MODEL (BINDING)** — two gates, two human checkpoints, plus an optional decision delegate.
> The **PL gate** is the post-plan human checkpoint: after PL0 completes, the orchestrator
> presents the generated plan and waits for explicit user approval (`AskUserQuestion`) before
> dispatching any implementation stage (AR/DV/...). It is carried by `PL0.metadata.plan_gate`, which
> defaults to `"checkpoint"`; `--auto=[plan]` and `--emergency` stamp `"bypass"` to auto-proceed (a batch orchestrator such as `/megatask` instead stamps it directly on each per-issue PL0).
> The **decision gate** is carried by `PL0.metadata.decision_gate`, default `"user"`: PL open
> questions surface to the user at the plan gate. `--auto=[decision]` stamps `"auto"` — open
> questions are resolved by a Fable-model decision delegate instead of blocking on the user
> (see § Step A.4 Auto-Decision Pre-Pass). Escalation-class questions always fall back to the user.
> The **FN gate** is the pre-finalization human checkpoint: `PL0.metadata.fn_gate` defaults to
> `"checkpoint"`, so the orchestrator STOPs immediately before the FN `Task()` delegation, presents a
> pre-FN summary, and waits for `AskUserQuestion` approval before any commit/push/PR. It is stamped
> `"bypass"` only by `--auto=[finalization]` or `--emergency` (unattended fast-path); `/megatask` stamps it directly on each per-issue PL0.
> Every worktask is worktree-isolated, so the PR is the review surface for the implementation.

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

> **Multi-issue batches moved to `/megatask`.** To execute a GitHub milestone or an array of issues
> with dependency/blocker ordering, use `/megatask N` or `/megatask --issues 12,15,18`. `/worktask`
> is strictly single-issue and milestone-agnostic — it has no `--milestone` flag. See
> `commands/megatask.md` and `skills/megatask/SKILL.md`.

## Worktask Types

| Type | Stages | Entry point |
|------|--------|-------------|
| Standard | PL→AR→TL→DV→DR→QA→DC→FN→ST | `/worktask` |
| Secure | PL→AR→TL→DV→DR→SR→QA→DC→RE→FN→ST | `/worktask --secure` |
| Emergency | IR→DV→DR→QA→RE→FN | `/worktask --emergency` |

AR and TL are optional within the standard and secure pipelines: AR is a tier default PL0 may
override in either direction, and TL is included only when PL0 splits the work across ≥2
developers. Criteria: `skills/estimation-methodology/SKILL.md § Stage Inclusion Criteria (PL0
authority)`.

See `skills/shared/stage-codes.md` for stage details.

## Options

### Gate automation flag (`--auto`)

`--auto=[<values>]` takes an **array** of automation values — any non-empty subset of
`plan`, `decision`, `finalization`, comma-separated. Brackets are optional and whitespace inside
them is tolerated: `--auto=[plan, decision]`, `--auto=plan,finalization`, and `--auto=[decision]`
are all valid. An unknown value is a parse error — reject the invocation and report; do NOT drop
the value silently. Each value is independent (orthogonal carriers on PL0).

#### Gate automation flag — values

| Value | Effect |
|-------|--------|
| `plan` | Stamp `plan_gate: "bypass"` — skip the post-PL plan-approval STOP and auto-proceed into the stage loop (trusted fast-path). FN gate is independent — still checkpoints unless `finalization` is also set. |
| `decision` | Stamp `decision_gate: "auto"` — when PL0 surfaces `open_questions[]`, delegate their resolution to a **Fable-model decision pass** (§ Step A.4) instead of blocking on the user. Bypasses NO gate by itself: under a `checkpoint` plan gate the auto-decisions are presented (marked) for approval. Escalation-class questions (irreversible, scope-expanding, security-posture, spend) always fall back to the user. |
| `finalization` | Stamp `fn_gate: "bypass"` — skip the pre-FN finalization-approval STOP; auto commit/push/PR (trusted fast-path). Plan gate still applies unless `plan` is also set. |

### Scope and pipeline flags

| Option | Effect |
|--------|--------|
| `--priority [High\|Medium\|Low]` | Task priority |
| `--platform <apple\|android\|web\|systems\|backend\|ai\|all>` | Target platform |
| `--ethics-review` | Add ET checkpoint after PL |
| `--sequential` | DC waits for QA |
| `--secure` / `--full` | Use 11-stage worktask |
| `--emergency` | Run the incident pipeline (IR→DV→DR→QA→RE→FN) instead of the standard PL-first pipeline; IR stage owned by `incident-responder`. Replaces the former `emergency:` prefix. |
| `--no-gh-issue` | Skip the post-PL GitHub issue auto-publish step. Sets `metadata.no_gh_issue: true` on the PL0 task; `skills/worktask/scripts/publish-pl-issue.sh` audits `deferred`/`opted_out` and the stage loop continues as normal. |

## Examples

```bash
/worktask "Add dark mode support"        # Standard mode (compose with --priority, --secure)
/worktask --emergency "Production login failing"   # Emergency (incident pipeline)
# Multi-issue: /megatask 1   (milestone)   or   /megatask --issues 12,15,18   (array)
```

## Phase 1: Planning (execute immediately)

> **BINDING CONSTRAINTS FOR PHASE 1**
> 1. **Pre-work Prohibition**: Do NOT create, edit, or modify ANY project files during Phase 1. This includes localization files, accessibility IDs, config files, and source files. Only `mkdir -p .context/designs .context/images .context/errors`, `state-patch.sh` ledger writes, and the Step 2a `.context/gh-issue.json` anchor (reuse path only) are permitted. ALL file modifications belong to DV stage or later.

### Phase 1 binding constraint 2 — Context-Interruption Recovery

> 2. **Context-Interruption Recovery**: If worktask execution is interrupted (auth flows, tool failures), upon resumption MUST verify that the PL0 task exists with status `completed`. If not, restart from the appropriate phase — **except** when PL0 is `in_progress` with stage tasks present and the audit tail has a `plan_revision_dispatched` row with no later `approval_received` for `PL<run_index>`: that is a plan revision in flight, resumed per § Plan-revision re-dispatch (re-dispatch PM with `plan_revision: true`; never the fresh-run path). (There are two human checkpoints — the PL gate at Step A.5 and the FN gate before finalization; the FN gate check applies (STOP on `checkpoint`, proceed on `bypass`) — `skills/worktask/SKILL.md § FN Gate`.)

### Steps 1–2 — Parse flags and detect embedded commands

1. **Parse** task description and flags (`--secure`, `--auto=[plan, decision, finalization]`, `--emergency`, etc.). Resolve the `--auto` array per § Gate automation flag: strip optional brackets, split on commas, trim whitespace, reject unknown values. See **Embedded Command Detection** below.
2. **Detect embedded commands**: If the task description contains `/plugin:command` or `/command` patterns (e.g., `/skill-creator`, `/apple-developer:fix-refactor`), extract them into `metadata.embedded_commands` as a comma-separated list. Remove the command prefix from the task description passed to PL0 but preserve the full arguments.

### Step 2a — Duplicate-issue pre-flight (advisory)

Runs once the request is known and **strictly before** Step 3 creates `.context/`. The
`skills/gh-issue-dedup` anchor binds one issue per `.context/` and so guards *re-runs* only —
a first run of work already filed under different wording still opens a second issue, and by
the time `.context/` exists the duplicate is no longer preventable. This step surfaces the
candidates while it still is.

#### Step 2a snippet — invoke the scan, non-blocking

    PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"  # CC substitutes on load; if empty resolve per skills/shared/plugin-root-resolution.md
    [ -d "$PLUGIN_ROOT" ] || PLUGIN_ROOT="<plugin-root>"
    SCAN="$PLUGIN_ROOT/skills/worktask/scripts/preflight-issue-scan.sh"
    scan_out=""
    if [ -f "$SCAN" ]; then scan_out=$(bash "$SCAN" --goal "<task description>") || true; fi
    scan_result=$(printf '%s\n' "$scan_out" | sed -n 's/^result=//p' | tail -n 1)

Append `--no-gh-issue` to the invocation when that flag was supplied — a run that publishes no
issue has no duplicate to prevent.

#### Step 2a — the gate

Anything other than `result=shown` proceeds to Step 3 unchanged, with no prompt. On
`result=shown`, present each `candidate=<json>` line (number, title, url — at most three, most
likely first) and call `AskUserQuestion` with exactly two outcomes:

- **Start a new worktask** — proceed to Step 3 as normal. Nothing has been written yet, so
  declining leaves no partial or orphaned state behind.
- **Use one of the existing issues** — proceed to Step 3, then bind this context to the chosen
  issue per § Step 2a — reusing an existing issue.

#### Step 2a — reusing an existing issue

Picking a candidate does not abort the worktask; planning still runs, bound to the issue that
already exists. After Step 3a seeds `state.json`, write the dedup anchor for the chosen issue:

    jq -cn --arg url "<chosen url>" --argjson num <chosen number> \
       --arg wid "$(jq -r '.worktask_id // "unknown"' .context/state.json)" \
       --arg ts "$(date -u +%FT%TZ)" \
       '{version:1, url:$url, number:$num, created_run_index:-1, created_worktask_id:$wid,
         created_at:$ts, last_commented_run_index:-1}' > .context/gh-issue.json

`created_run_index: -1` is the "predates this context" value `publish-pl-issue.sh` already uses
for a recovered search hit, so Step A posts a follow-up comment on that issue instead of opening
a second one — the same end state as having resumed that worktask directly.

#### Step 2a invariants

- The trailing `|| true` is mandatory. The helper is **non-blocking by contract**: no network,
  no `gh`, no auth, no remote, an API error, a rate limit, a timeout, a malformed response, or
  zero hits each print `result=skipped`/`result=none` and Step 3 runs unchanged.
- **Advisory only.** It never links, comments, closes, or writes anything, and it does NOT relax
  the exact-title auto-bind in `publish-pl-issue.sh` (`skills/gh-issue-dedup § Resolution order`)
  — an ambiguous match is still refused there rather than bound automatically.
- It writes **no audit row** — the ledger it would append to does not exist yet at this point.

#### Step 2a invariants — runs that skip the question

- **Unattended runs never reach it.** The helper self-skips under `CORPFLOW_NONINTERACTIVE=1`,
  under `/megatask` (`MILESTONE_MODE=1` or a `workspace.json`), and under `--emergency`
  (`INCIDENT_MODE=1`). `PREFLIGHT_ISSUE_SCAN=0` disables it outright.
- A `.context/` that already carries a `gh-issue.json` anchor is a resume, not a first run: the
  helper skips with `reason=already_anchored` and the anchor answers the question authoritatively.

### Step 3 — Create context folders

3. **Create context folders**: `mkdir -p .context/designs .context/images .context/errors .context/logs`

### Step 3a — Initialize state.json (handoff-protocol)

3a. **Initialize state.json (handoff-protocol)**: Atomic-write `.context/state.json` seed using temp+fsync+rename per `skills/worktask/references/handoff-protocol.md#atomic-write`. PL0 stage marked `in_progress`. Schema per `handoff-protocol.md#state-json-schema`. **Re-run aware**: the seed MUST compute the next free planning index from any pre-existing `.context/planning-*.md` (NOT hard-code `0`) — on a re-run in a populated `.context/`, hard-coding `planning-0.md` would pin the old plan and cause PL0 to overwrite it. If creation fails (e.g. read-only filesystem), STOP and report — the ledger is mandatory and there is no degraded mode that keeps the worktask correct without it.

#### Step 3a snippets — init procedure

   The re-run-aware next-free-planning-index resolver (N=0 on a fresh `.context/`, nullglob-safe) and the atomic `state.json` seed write are canonical in `skills/worktask/references/initialization-patterns.md`. Compute N, then atomic-write the seed (`{version:2, worktask_id, plan_file: .context/planning-${N}.md, platform, run_index:N, metadata.workspace_path, tasks.PL0.status:in_progress, facts.goal seeded from the task description plus the otherwise-empty facts incl. dispatched_agents:[], handoffs:{}}`) per `handoff-protocol.md#atomic-write`.

#### Step 3a — seed `metadata.workspace_path` (UNCONDITIONAL)

   Resolve it as `git rev-parse --show-toplevel`, falling back to `pwd` outside a git tree, and
   write it into the seed. This is not a megatask-only field: `dv-tree-preflight.sh` reads
   `.metadata.workspace_path` as its assigned-tree source, the cross-check below reads it, and
   `agents/developer.md`'s path-prefix check is gated on it being set. Each of those degrades to
   a **silent pass** when the field is absent, so omitting it disables all three at once. Rationale
   and the failure it let through: `initialization-patterns.md § Seeded workspace_path`.

#### Step 3a — seed `facts.goal`

   Seed it from the task description, JSON-escaped, truncated to 240 chars. It is the issue title and `## Summary` source for `publish-pl-issue.sh`, and nothing on the PL state-patch path actually writes it, so leaving it to PL0 is what let a run publish a kebab-slug title with an empty Summary (issue #375). PM refines it later; this seed only guarantees it is never absent.

   The seeded `plan_file` is the **path** shape (`.context/planning-${N}.md`), not a bare basename — task metadata carries the basename shape instead. Both are legal; see the `plan_file` shape boundary in `handoff-protocol.md § state.json schema`.

#### Step 3a field notes

   `facts.dispatched_agents: []` is seeded (additive) so the orchestrator loop appends per-`task_id` dispatch entries in place. The other v1 additive fields (`tasks.<ID>.completed_via`/`last_error`/`worktree`, `facts.capabilities`) are written on demand — do NOT seed them; their absence is meaningful. See `handoff-protocol.md#state-json-schema`.
### Step 3b — Verify SubagentStop hook installed

3b. **Verify SubagentStop hook installed**: After state.json seed, verify `.claude/hooks/state-merge.sh` exists and is executable AND the plugin's `plugin.json` registers the SubagentStop hook entry. If the project-local hook is missing, copy from `<plugin-root>/hooks/state-merge.sh` (resolved in the snippet below). This hook is the Layer 2 safety net that patches state.json when agents skip self-patching. See `initialization-patterns.md#hook-installation`.

#### Step 3b hook-install snippet

   ```bash
   PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"  # CC substitutes on load; if empty resolve per skills/shared/plugin-root-resolution.md
   [ -d "$PLUGIN_ROOT" ] || PLUGIN_ROOT="<plugin-root>"
   hook_src="$PLUGIN_ROOT/hooks/state-merge.sh"
   hook_dst=".claude/hooks/state-merge.sh"
   if [[ ! -x "$hook_dst" ]] && [[ -f "$hook_src" ]]; then
     mkdir -p .claude/hooks
     cp "$hook_src" "$hook_dst" && chmod +x "$hook_dst"
   fi
   ```

#### Step 3b regression guard

   **Regression guard**: If neither the plugin-registered hook NOR the project-local copy exist, emit a warning: `"⚠ state-merge.sh hook not installed — state.json will only be patched if agents self-merge (Layer 1) or orchestrator Step 6.5 fires (Layer 3). Run hook-install.sh to fix."` Do NOT block the worktask.
### Step 3c — Name the branch once (PL start)

3c. **Name the branch — UNCONDITIONAL**: after the state.json seed and before seeding PL0
   for PL0, run `bash skills/worktask/scripts/branch-name.sh --goal "<concise imperative title>"`.
   This is the ONLY place a worktask branch is ever renamed — the once-only rule per
   `skills/shared/git-conventions.md § Branch Naming`. The *planned* name on the ledger may
   additionally be refined once, later and without any git mutation — § Step A.4b. Every
   outcome exits 0 (a naming problem must never stop planning) and the step self-disables
   **inside the script** under `/megatask` or `--emergency` routing.

#### Step 3c — the input is a title, not the task description

   **Derive the title from the request; do not pass the request verbatim.** A title is an
   imperative phrase of at most 60 characters naming the thing changed and the change.

   The goal text is slugified into a **48-character** slug and anything past that budget is
   dropped **silently**, so a multi-sentence description yields a name that ends mid-phrase
   and describes nothing:

   - good: `Replace in-house ZIP with upstream ZipArchive`
   - bad: `Replace the in-house ZIP implementation in Sources/Archive/ with the upstream
     ZipArchive package, keeping the existing public API and updating the tests`

#### Step 3c — preview freely before the single rename-mode run

   `BRANCH_NAME_PRINT=1 bash skills/worktask/scripts/branch-name.sh --goal "<title>"` previews
   the derived name: it renames nothing and writes **no audit row**. Previewing before the one
   rename-mode run is expected practice, not an exception — it is how a poor title is caught
   while it is still free to change. A truncated slug is reported on stderr; stdout stays the
   bare name.

#### Step 3c — why it always runs

   **Run it on every worktask, with no precondition of any kind.** The script's own guard
   ladder already contains an "already conventional" arm that is a pure no-op — it prints
   `no-op`, writes one audit row, and changes nothing — so running it on an
   already-named branch costs one process and is the *only* correct way to establish that
   the name is in fact conventional. Skipping the step because the current branch looks
   fine is not an optimisation; it is the check being replaced by a guess.

#### Step 3c — pre-existing branches are covered

   A Conductor workspace, a manual `git checkout -b`, or any branch created outside this
   pipeline still has to pass the predicate. Being already on a branch is not evidence
   that the branch is conventional.

   > **BINDING** — never judge conventionality by eye. The sole authority is
   > `branch_is_conventional()` from `skills/worktask/scripts/branch-lib.sh`, reachable as
   > `bash skills/worktask/scripts/branch-name.sh --check "<name>"` (exit 0 = conventional,
   > 1 = not, 2 = internal fault). An orchestrator that reasons "this branch already looks
   > like a real branch name, skip" is how `fix/catalog-image-blinking` reached `facts.branch`
   > after `fix` had been removed from `BRANCH_TYPES`.

#### Step 3c — host-session authorization (BINDING)

   Invoking `/worktask` **satisfies** a host's "do not rename the current branch unless the
   user explicitly tells you to" session rule (Conductor injects exactly that). A
   conventional branch and a ticket-referencing PR are part of what the pipeline was asked
   to deliver. **Never revert this step's rename, and never suspend the pipeline to re-ask.**
   Rationale and scope: `skills/worktask/references/workspace-modes.md § Host session
   authorization`.

#### Step 3c — host-session authorization inside a linked worktree

   Inside a linked worktree the naming step **renames the local branch**, like any other
   checkout, so `branch=` and `target_branch=` agree. The host's branch↔workspace mapping is
   updated by that rename — deliberately: a host-assigned placeholder is not a name worth
   preserving, and a host may rename the branch again mid-run without telling the pipeline.
   Set `BRANCH_NAME_WORKTREE_RENAME=0` to restore the previous defer-to-host behaviour, in
   which the local name is kept and only `target_branch=` is derived.

   **The "never revert this step's rename" rule therefore applies inside worktrees too.** It
   was previously moot there — nothing was renamed — and is not any more.

#### Step 3c — validate before stamping

   Capture **both** key=value stdout lines: `target_branch=<name>` (the name the PR head
   should carry) and the final `branch=<name>` line (the local branch as it stands).
   **Before stamping, verify the value matches `^[A-Za-z0-9._/-]+$`** (defence in depth
   alongside the script's own emission validation and FN's re-validation before use — see
   `agents/project-manager.md § Final FN steps`) — a value that fails this check MUST be
   stamped as empty, never as-is. Stamp `state.json facts.branch` (the script itself never
   writes state.json — see `skills/worktask/references/handoff-protocol.md § branch`).

#### Step 3c — which of the two names gets stamped

   ```bash
   # A concise imperative TITLE (≤60 chars), never the raw task description — the slug
   # budget is 48 characters and the overflow is dropped silently.
   out=$(bash skills/worktask/scripts/branch-name.sh --goal "<concise imperative title>")
   local_branch=$(printf '%s\n' "$out" | sed -n 's/^branch=//p' | tail -n 1)
   target=$(printf '%s\n' "$out" | sed -n 's/^target_branch=//p' | tail -n 1)
   truncated=$(printf '%s\n' "$out" | sed -n 's/^slug_truncated=//p' | tail -n 1)

   # target_branch wins whenever the local name is unusable as a PR head — that is the
   # whole point of the second line. Falling back to the local name here is what shipped
   # a `<city>-v<n>` branch as a PR head.
   stamp="$local_branch"
   if [ -z "$stamp" ] || ! bash skills/worktask/scripts/branch-name.sh --check "$stamp"; then
     [ -n "$target" ] && stamp="$target"
   fi
   ```

#### Step 3c — an empty stamp is an honest outcome

   `branch-name.sh` already emits both lines empty rather than emit a name that fails the
   predicate, so an empty `stamp` after this is the honest "no planned name" outcome (FN
   pushes plainly) — not a value to patch up by hand.

#### Step 3c — post-check (non-blocking)

   After stamping, assert the stamped value against the predicate — not by eye. Reuse the
   `$target` already captured above. Do not re-invoke the script in **rename mode** to
   re-derive the target (that writes a second audit row). Preview freely with
   `BRANCH_NAME_PRINT=1`, and query freely with `--check` / `--print-target`, which write
   none:

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

   The `slug_truncated=1` line is present ONLY when the budget dropped content. On seeing it,
   append one row naming the input length and the surviving slug — the evidence a human reads
   at the plan gate, and the incumbent-quality signal § Step A.4b reads before spending its
   one refinement window:

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

#### Step 3c — truncation row notes

   `slug` is the post-`<type>/` remainder; when a ticket segment is present it is part of that
   value. `$title` is the title passed to `--goal` above. Non-blocking like every other row
   here — a truncated name is reported, never repaired by a second rename.

#### Step 3c — post-check invariants

   The row MUST name **both** the actual stamped branch and the derived target, so the
   divergence is legible without re-deriving it later. An empty `facts.branch` is a
   documented outcome (detached HEAD, not a git repo) and is not a warning; an empty
   `derived_target` means a guard arm short-circuited before derivation, and `actual` is
   then the load-bearing half of the row. With the stamping rule above, a non-empty
   `derived_target` in this row is now a **bug report**: it means a conventional target was
   available and something stamped past it.

   **This post-check MUST NOT block planning.** It emits a warning row and nothing else —
   no STOP, no retry, no rename. A rename at this point would violate the once-only rule,
   and a naming problem is never worth failing a worktask over.

### Step 4 — attach PL0 metadata

4. **Attach PL0 metadata**: the Step 3a seed already created `tasks.PL0`, so this step MERGES its metadata rather than creating the task — `--task-create` would hit the create op's idempotent early-exit and drop the payload silently. `state-patch.sh --task-meta PL0 --set '{"stage":"PL","agent":"corpflow:product-manager","model":"opus","worktask_id":"<slug>","priority":"<priority>","plan_gate":"checkpoint","decision_gate":"user","fn_gate":"checkpoint","isolation":"worktree","workspace_path":"<resolved root>","description":"<task description>"}'` — `metadata.agent` MUST use fully-qualified `plugin:agent` form (`corpflow:`, `apple-developer:`, etc.).

#### Step 4 — workspace_path stamping

`workspace_path` carries the same value seeded into `state.json` at step 3a (`git rev-parse --show-toplevel`, else `pwd`) and is stamped on **every** run beside `isolation`, not only under `/megatask`. PM propagates it to every stage task it creates. It is what tells a stage agent which tree it was *assigned*, which is a different claim from the tree it happens to have resolved — see `skills/worktask/references/workspace-modes.md § Sibling-worktree hazard`.

#### Step 4 — fn_gate stamping

Stamp `fn_gate`: default `fn_gate: "checkpoint"` (the orchestrator STOPs immediately before the FN `Task()` delegation and asks for finalization approval before any commit/push/PR — handled at SKILL.md loop step 4.9). Stamp `fn_gate: "bypass"` ONLY when the resolved `--auto` array contains `finalization` OR when `--emergency` is set (incident pipeline finalizes unattended). `--auto=[plan]` MUST NEVER stamp `fn_gate: "bypass"` — it is orthogonal and bypasses only the plan gate. (A batch orchestrator such as `/megatask` stamps `fn_gate: "bypass"` directly on each per-issue PL0 — `/worktask` itself has no batch flag.)

#### Step 4 — plan_gate stamping

Also stamp `plan_gate`: default `plan_gate: "checkpoint"` (the orchestrator STOPs after PL0 and asks for plan approval before dispatching stages). Stamp `plan_gate: "bypass"` ONLY when the resolved `--auto` array contains `plan` OR when `--emergency` is set (emergency pipeline runs unattended from IR — no plan approval gate). (A batch orchestrator such as `/megatask` stamps `plan_gate: "bypass"` directly on each per-issue PL0.) `plan_gate`, `decision_gate`, and `fn_gate` are the carriers resume logic branches on after interruption — see `skills/worktask/references/resume.md § State → Action Table`.

#### Step 4 — decision_gate stamping

Also stamp `decision_gate`: default `decision_gate: "user"` (PL open questions surface to the user at the plan gate — existing behavior). Stamp `decision_gate: "auto"` ONLY when the resolved `--auto` array contains `decision`. The carrier is consumed by two readers: the PM agent (holds no gate round-trip for questions — returns them in `open_questions[]`; see `skills/worktask/references/pl0-procedure.md § Plan-Gate Open-Question Batching`) and the orchestrator's Step A.4 auto-decision pre-pass below. `decision_gate` bypasses neither `plan_gate` nor `fn_gate` — it only changes WHO answers PL0's open questions. `--emergency` leaves it at `"user"` (the incident pipeline has no PL stage, so the carrier is inert there). (A batch orchestrator such as `/megatask` stamps `decision_gate: "auto"` directly on each per-issue PL0.)

### Steps 5–6 — Dispatch the PL agent

5. **PL0 → in_progress**: `state-patch.sh --task-status PL0 in_progress`
6. **Delegate to PL agent**: `Task({ subagent_type: "corpflow:product-manager", prompt: "<planning prompt>" })` — PM computes the next free plan filename per `skills/worktask/references/pl0-procedure.md § Plan File & Run Index Naming` (glob+increment: first run `.context/planning-0.md`; subsequent runs `planning-1.md`, `planning-2.md`, ...), writes it, assesses complexity, and creates stage tasks with `metadata.agent` AND `metadata.plan_file = "<plan_file>"`. The `plan_file`/`run_index` already in the seeded `state.json` (step 3a) are provisional — PM recomputes and is authoritative. Glob+increment applies to a **new run** only: a plan-gate revision re-dispatches PM with `plan_revision: true` and reuses the frozen index (§ Plan-revision re-dispatch).
#### Step 6 — record dropped stages

   - **Record dropped and added stages**: when PL0's dynamic sizing omits any of the full 9-stage pipeline (`PL→AR→TL→DV→DR→QA→DC→FN→ST`), PM stamps the PL0 task's `metadata.skipped_stages` (`{stage, reason}` list) so `state.json` self-documents the drops; when PL0 includes a stage beyond the tier default (AR0 forced at a low tier, TL0 at any tier), it stamps the symmetric `metadata.added_stages` with the identical `{stage, reason}` shape. See `skills/worktask/references/pl0-procedure.md § Dynamic Worktask Sizing (PL0 Stage)`.
### Steps 7–8 — Complete PL0 and present the plan

7. **PL0 → completed**: `state-patch.sh --task-status PL0 completed`
8. **Present plan summary**: Show complexity score, stages created (with agents), dependency chain, and key decisions, then continue to Phase 2, which runs the Plan Gate Check (Step A.5) before the stage loop.

## Phase 2: Execute Stages (proceeds automatically)

Phase 2 begins with the Auto-Decision Pre-Pass (Step A.4, no-op unless `decision_gate == "auto"` AND PL0 left open questions), then the Plan Gate Check (Step A.5): on a `checkpoint` plan gate the orchestrator presents the plan and waits for user approval before the stage loop; on `bypass` (`--auto=[plan]` / `--emergency`, or a gate stamped directly by `/megatask`) it proceeds directly.

### Step A.4 — Auto-Decision Pre-Pass (runs before Step A.5)

Read `tasks.PL0.metadata.decision_gate` from the ledger (default `"user"` when absent) and PL0's
`open_questions[]` (typed handoff / plan-frontmatter — the numbered elicitation list from
`skills/worktask/references/pl0-procedure.md § Plan-Gate Open-Question Batching`). This step is a **no-op** when
`decision_gate == "user"` or `open_questions[]` is empty/absent — fall through to Step A.5.

#### Auto-decision dispatch (Fable delegate)

When `decision_gate == "auto"` and `open_questions[]` is non-empty:

1. Append an `auto_decision_dispatched` audit row (`subject:"PL<N>"`, `metadata.questions: <count>`).
2. Re-dispatch the PM as a decision delegate on the **Fable model**:
   `Task({ subagent_type: "corpflow:product-manager", model: "fable", prompt: <decision prompt> })`.
   The prompt carries the open-question list verbatim (each with its recommended default) and the
   plan file path; its duties are § Auto-decision recording contract below. **Model fallback**:
   apply loop step 5f exactly — if `facts.capabilities.fable_dispatch == "credit_blocked"`,
   dispatch on `"opus"` and audit `model_resolution_constrained`.

#### Auto-decision recording contract

The decision prompt instructs the delegate to decide every non-escalation question (default-biased
— deviate from the PM's recommended default only with stated evidence), apply the resulting
amendments to the plan's EXISTING mandatory anchors (`## requirements` / `## acceptance-criteria` /
`## scope`) in ONE batch pass, and return each decision as a typed-return `key_decisions[]` entry
prefixed `(auto-decided)`, plus any `escalate` items. It adds NO new anchor to `planning-N.md` —
the PL anchor set is exact (`skills/worktask/references/handoff-protocol.md § #anchor-allow-list`).
It does NOT re-run `state-patch.sh`: PL0 is already `completed`, so the plan amendments are its
only writes.

#### Auto-decision ledger merge (orchestrator)

3. On return the ORCHESTRATOR — not the delegate — merges the ledger via `atomicMergeStateJson`:
   append each decided item to `state.json facts.decisions[]` marked `(auto-decided)` and remove
   the resolved entries from `facts.open_questions[]`. This is what makes the decisions visible to
   AR/TL/DV, which read `facts.decisions`/`facts.open_questions` on stage entry
   (`skills/shared/stage-contracts.md`).
4. Append one `auto_decision_resolved` audit row (`subject:"PL<N>"`, `metadata: { decided: <count>,
   escalated: <count>, model_resolved: <alias>, decisions: [{question, answer, rationale}] }`) —
   the per-question rationale is carried there, one line each.

#### Escalation guard (BINDING)

The delegate MUST NOT auto-decide **escalation-class** questions: anything irreversible or
destructive (data deletion, force-push, external publication), scope-expanding beyond the task
description, security-posture-weakening, or spend-authorizing. It returns those as `escalate`
items. If any `escalate` items exist, Step A.5 runs as a **`checkpoint`** gate for those items
even when `plan_gate == "bypass"` — the user answers only the escalated questions, the batch
amendment pass applies their answers, then the bypass path resumes. Auto-decision never widens
what runs unattended; it only answers what a human would otherwise be interrupted for.

##### Escalation guard — unattended `/megatask` per-issue runs (PARK)

Under a `/megatask` per-issue run (detected by `PL0.metadata.megatask_group`) there is no user to
stop for. Instead of holding the checkpoint, **PARK the issue**: write
`workspace.json.execution.status: "failed"` with `execution.reason: "parked_escalation"`, append an
`escalation_parked` audit row (`subject:"PL<N>"`, `metadata.escalated: [<questions>]`), and STOP
this worktask without dispatching any stage. Parking rides the monitor's existing failure path
(`hooks/megatask-monitor.sh` settles only `completed`/`failed`): the track is freed, dependents
stay `blocked`, and the batch summary lists the issue with its unanswered escalate questions for a
follow-up interactive `/worktask`.

#### Presentation in the gate summary

On a `checkpoint` plan gate, the Step A.5 summary MUST list every auto-decided question with its
chosen answer marked `(auto-decided by Fable — see facts.decisions[] / audit)`, so the user
approves the decisions together with the plan. On `bypass`, the audit rows plus the merged
`facts.decisions[]` entries are the durable record.

### Step A.4b — Refine the branch target (runs after Step A.4, before Step A.5)

The name stamped at Step 3c was derived from a title written before the plan existed. Now that
the approved plan carries its own `title:`, re-derive the **planned remote target** from it —
at most once per run, and only while no commit exists to disagree with it. This step
**performs no git mutation**: it rewrites `facts.branch` on the ledger and nothing else. The
local branch is untouched and the once-only *rename* rule is unaffected
(`skills/shared/git-conventions.md § Once-only rule`).

#### Step A.4b snippet — invoke the helper, non-blocking

Placed here so the Step A.5 gate summary carries the final name before anything is published
or pushed.

    PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"  # CC substitutes on load; if empty resolve per skills/shared/plugin-root-resolution.md
    [ -d "$PLUGIN_ROOT" ] || PLUGIN_ROOT="<plugin-root>"
    HELPER="$PLUGIN_ROOT/skills/worktask/scripts/refine-branch-target.sh"
    ref_out=""; if [ -f "$HELPER" ]; then ref_out=$(bash "$HELPER") || true; fi
    ledger_branch=$(printf '%s\n' "$ref_out" | sed -n 's/^ledger_branch=//p' | tail -n 1)

#### Step A.4b invariants

- The trailing `|| true` is mandatory — the helper is non-blocking by contract, exactly like
  the Step A publish helper. A helper failure MUST NEVER fail the worktask.
- The helper is **self-guarding**: it scans `audit.jsonl` for a prior successful
  `branch_target_refined` row at this run index, so a duplicate invocation after a resume is a
  `noop`, never a second refinement.

#### Step A.4b invariants — the audit row

- Exactly one audit row per invocation **whenever `jq` is available**. `jq` is what serialises
  the row, so the `jq_unavailable` arm — and only that arm — writes none, announcing itself on
  stdout instead. This matches `branch-lib.sh audit_fn`, which no-ops without `jq` for every
  caller.
- The row is `branch_target_refined`, `ok` or `noop` with a reason from its closed set. A `noop`
  is a normal outcome, not a failure: the helper declines whenever a commit exists, an upstream
  is configured, the plan carries no `title:`, the candidate is unusable or unchanged, or the
  candidate would truncate while the incumbent name has no recorded truncation.

#### Step A.4b invariants — the returned value

- `ledger_branch` is the value on the ledger **after** this step, refined or not. Use it in the
  Step A.5 summary rather than re-reading `state.json`.
- FN's re-validation of `facts.branch` against `^[A-Za-z0-9._/-]+$` is unchanged and still runs
  — the refined value passes through the identical check because FN reads the ledger.

### Step A.5 — Plan Gate Check (runs after Step A.4, before Step A publish)

Read `tasks.PL0.metadata.plan_gate` from the ledger (default `"checkpoint"` when absent). Resolve the run
index `N` from `state.json.run_index` (default `0`).

#### Plan gate checkpoint path

**If `plan_gate == "checkpoint"`** (default — plain `worktask` with no bypass flag):
1. Read `state.json.plan_file` to locate the plan; accept either shape (`handoff-protocol.md § plan_file shape boundary`).
2. Present the plan summary to the user: complexity score, stages created (with agents),
   dependency chain, key decisions, and both inclusion decisions (see below).
3. Call `AskUserQuestion`:
   *"Here is the generated plan for your worktask. Approve to begin implementation, or describe
   any changes you want first."*
   (`AskUserQuestion` does not auto-continue on idle by default — the gate holds
   until a human answers. Keep the `/config` idle-timeout opt-in OFF on hosts that run gated
   worktasks; an idle auto-answer would count as an approval the operator never gave. A
   background-task completion notification is never this approval either — it explicitly
   states no human input occurred, so do not treat it as the operator's answer.)

##### Stage-inclusion decisions in the gate summary

The step-2 summary MUST show both decisions explicitly, each with its one-line reason drawn from
`skipped_stages`/`added_stages`:

- **AR** — included or excluded, and whether that deviates from the tier default (flag the
  deviation; a tier-default AR still states its reason for being kept).
- **TL** — included or excluded on the split-work test, naming the workstreams when included.

##### Branch name in the gate summary

The step-2 summary MUST also show `Branch (PR head): <ledger_branch>` (the value Step A.4b
returned), so the user sees the name the PR will carry before anything is published.

An empty `ledger_branch=` means **unknown**, not absent: the helper's `jq_unavailable` arm cannot
read the ledger and prints it empty even when a good name is stamped. So on an empty value, read
`facts.branch` directly and print `Branch (PR head): — (none planned)` only if that read is also
empty. One extra read, only on the degraded path.

##### Branch name in the gate summary — conditional additions

- `⚠ name truncated at 48 chars (<input_len> chars of input)` when a `branch_slug_truncated`
  row exists for `PL<N>` — the Step 3c row above.
- `(refined from <old> via plan title)` when the Step A.4b row is `result: "ok"`.
- `⚠ renamed inside a linked worktree — your host's workspace↔branch mapping may need to
  re-sync; set BRANCH_NAME_WORKTREE_RENAME=0 to keep the host's name` when the Step 3c
  `branch_renamed / ok` row carries `in_worktree: "true"`. The rename already happened at
  Step 3c (Phase 1, before this gate), so this line reports it rather than asking — it is
  reversible with `git branch -m <original>`.

This is the last point at which a name is free to change: a user who dislikes it says so here,
and the plan revision path re-derives nothing (§ Plan-revision invariants row 5).

#### Plan gate approval / rejection audit rows

4. **On approval**, append one line to `.context/logs/audit.jsonl`, then proceed to Step A:
   ```json
   {"ts":"<ISO>","actor":"orchestrator","action":"approval_received","subject":"PL<N>","result":"ok"}
   ```
5. **On rejection / revision request**, append:
   ```json
   {"ts":"<ISO>","actor":"orchestrator","action":"approval_rejected","subject":"PL<N>","result":"rejected"}
   ```
   STOP — do NOT enter the stage loop. Surface the user's feedback. If the user wants revisions,
   re-dispatch PM per § Plan-revision re-dispatch below — a revision is NOT a new run.

##### Plan-revision re-dispatch (gate rejection only)

A gate rejection revises the run **in flight**; it never starts a new one. `run_index` and
`plan_file` are FROZEN for the life of a run — allocating `planning-<N+1>.md` here forks the plan,
wipes the `facts.decisions[]` the user just supplied at this gate, strands the stage-task chain on
the old index, and splits the published-issue record. Re-dispatch product-manager with
`plan_revision: true` in the prompt, carrying the user's feedback verbatim.

##### Plan-revision invariants (BINDING)

| # | Do | Never |
|---|---|---|
| 1 | Edit the existing `planning-<N>.md` in place | Allocate `planning-<N+1>.md` |
| 2 | Patch `facts.*` additively — `facts.decisions[]` survives | Run the state.json reset |
| 3 | Patch the existing stage tasks | Seed a second stage chain |
| 4 | Leave the published GitHub issue as-is | Re-publish or re-anchor the issue |
| 5 | Leave the refined `facts.branch` as-is | Re-run Step A.4b or re-refine — a revision is not a new naming window |

PM's own arm of this contract: `skills/worktask/references/pl0-procedure.md § Revision of the run in flight`.

##### Plan-revision bookkeeping

Set the PL0 task back to `in_progress`, increment `metadata.revision_count` (absent → `1`), and
append exactly one audit row before dispatching:

```json
{"ts":"<ISO>","actor":"orchestrator","action":"plan_revision_dispatched","subject":"PL<N>","result":"ok","metadata":{"revision_count":<count>}}
```

On PM's return, re-enter the plan gate at Step A.5 — the revised plan needs its own approval, and
Step A still runs exactly once per run (the issue is published after the *approved* plan).

#### Plan gate bypass path

**If `plan_gate == "bypass"`** (stamped by `--auto=[plan]` or `--emergency`, or directly by `/megatask` on a per-issue PL0): proceed directly to
Step A. No prompt, no approval line. Exception: unresolved `escalate` items from Step A.4 force a
`checkpoint`-style stop for those items first (§ Step A.4 Escalation guard) — once the user has
answered them, append the standard `approval_received subject:"PL<N>"` row (that row is what
§ PRECONDITION CHECK Signal 2b requires as the escalate resolution) and then resume the bypass path.

### Step A — Publish plan to GitHub (run BEFORE the stage loop)

    PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"  # CC substitutes on load; if empty resolve per skills/shared/plugin-root-resolution.md
    [ -d "$PLUGIN_ROOT" ] || PLUGIN_ROOT="<plugin-root>"
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

- The trailing `; true` is mandatory — the helper is non-blocking by contract.
  A helper failure MUST NEVER fail the worktask.
- The helper self-skips (`--no-gh-issue`, megatask per-issue mode — detected via
  `workspace.json` presence / `metadata.milestone`, already published,
  missing `gh`/auth/remote) — each exits 0 and audits a `deferred` row.
  Sanitiser rules + non-blocking guarantee: `skills/worktask/SKILL.md § PL Issue Publish`.
- One `.context/` ↔ one GitHub issue: a second or later run in the same `.context/`
  resolves the run-independent `.context/gh-issue.json` anchor and posts a follow-up
  comment instead of opening a duplicate. Protocol: `skills/gh-issue-dedup`.
- This step is NOT optional. Do not skip it because SKILL.md describes it —
  the orchestrator MUST run the command above as written.

#### After Step A — run the stage loop

Execute the orchestrator execution loop from `skills/worktask/SKILL.md § Orchestrator Execution Loop`. Before the FN `Task()` delegation the orchestrator applies the FN gate check (STOP on `checkpoint`, proceed on `bypass`) — see `skills/worktask/SKILL.md § FN Gate`.

#### Workspace-root cross-check (BINDING)

**BINDING: Workspace-root cross-check before every `Task()` delegation** — Conductor-managed sessions spawn the orchestrator inside a workspace clone whose `pwd` differs from the canonical plugin source repo. Before every `Task()` call in the stage loop, the orchestrator MUST verify that the working tree matches the task's declared workspace, and MUST inject the resolved root into the stage prompt so the subagent targets the right directory:

##### Cross-check snippet and prompt-banner injection

```bash
# Workspace-root cross-check (runs in orchestrator turn, not in subagent)
_orch_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
_task_root=$(jq -r '.metadata.workspace_path // empty' .context/state.json)
# Unset is a DEFECT, not a mode — see § Unset workspace_path below.
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

##### Unset workspace_path is a defect

This step previously defaulted `_task_root="${_task_root:-$_orch_root}"` — comparing a value to
itself, so the cross-check passed unconditionally and an unstamped ledger read as clean. Step 3a
now stamps the field on every run; its absence means the seed did not run, which leaves this
check, `dv-tree-preflight.sh`, and `agents/developer.md`'s path-prefix check all inert at once.

##### Banner injection

The orchestrator MUST also append `WORKSPACE_ROOT=$_orch_root` as the first line of every stage prompt banner (section [7] suffix per the cache-prefix spec) so the subagent knows which directory to target. See `skills/worktask/references/workspace-modes.md § Conductor Workspace Topology` for the failure mode this guard prevents.

#### Post-delegation state.json enforcement (BINDING)

**BINDING: Post-delegation state.json enforcement** — After every `Task()` return (the *completed stage result* — under background-default subagents, that is the completion notification, not the launch acknowledgement; see `skills/worktask/SKILL.md § Orchestrator Execution Loop` Step 6.5), before the `completed` patch: re-read `.context/state.json`; if `tasks.<ID>.status` is NOT `completed`, run
   ```bash
   CLAUDE_ARTIFACT_PATH=".context/<artifact>-N.md" \
   CLAUDE_TASK_METADATA_STAGE="<CODE>" \
   STATE_MERGE_VIA=step6_5 \
   bash .claude/hooks/state-merge.sh
   ```

##### Layer-3 stamp and F3 fallback

   `STATE_MERGE_VIA=step6_5` stamps `tasks.<ID>.completed_via=step6_5` so this synchronous Layer-3 path is distinguishable from the SubagentStop-hook Layer-2 default (`hook`). Then re-read; if STILL not `completed`, apply the F3 fallback (derive minimal patch from agent return text — the F3 patch stamps `completed_via: "f3"`). This covers environments where the SubagentStop hook never fired. Full three-layer logic: `skills/worktask/SKILL.md § Orchestrator Execution Loop` Step 6.5.

### Step B — AR-reference check at DV completion

Runs only when `.context/state.json` has a `tasks.AR0` entry (AR is optional — see `skills/estimation-methodology/SKILL.md § Stage Inclusion Criteria`). After DV0 completes and before dispatching DR0:

```bash
STRICT_FLAG=""
[ "${CORPFLOW_AR_REF_STRICT:-0}" = "1" ] && STRICT_FLAG="--strict"
# shellcheck disable=SC2086
skills/worktask/scripts/handoff-harness.sh --validate-frontmatter ".context/development-${N}.md" \
  --state .context/state.json $STRICT_FLAG
```

#### Step B rollout and opt-in

**Rollout — warn-only in 3.42.0.** With no opt-in the harness emits `warn:` lines and exits 0. Record each warning as an audit row and carry it into the DR dispatch prompt so DR checks the linkage:

```json
{"ts":"<ISO>","actor":"orchestrator","action":"ar_ref_check","subject":"DV<N>","result":"warn"}
```

A warning is **not** a `missing_input` block and never stops the transition.

**Early opt-in — `CORPFLOW_AR_REF_STRICT=1`.** Set the env var and the orchestrator passes `--strict`; violations become `fail:` lines with exit 1 and block the DR dispatch until DV fixes the reference. Use it to shake out dangling references before the next minor, which flips `--strict` to the default. The inverse guard (an architecture reference with no `tasks.AR0` entry) warns in both modes and never fails.

## Phase 3: Post-Worktask Self-Improvement

After the execution loop exits (ST completed), run the Post-Worktask Self-Improvement procedure from `skills/worktask/SKILL.md § Post-Worktask Self-Improvement`.

### Phase 3 flow

1. Check whether `.context/learnings.md` exists. If absent → worktask done, terminate.
2. If present → display its contents and **STOP**. Wait for the user to check the boxes of proposals they approve (`- [ ]` → `- [x]`). Orchestrator MUST NOT auto-check or assume.
3. User replies with approval ("apply checked", "go", or similar). Orchestrator then re-reads `learnings.md`, parses the checked items, and delegates to `corpflow:prompt-engineer` for application (see `agents/prompt-engineer.md § Self-Improvement Patch Application`).
4. Each applied proposal becomes its own commit with a `version:` bump on the target frontmatter (rollback-safe via `git revert <sha>`).

### Phase 3 key invariants

- Never auto-apply proposals — the user must explicitly check boxes AND signal approval.
- Proposals are scoped to agents/skills/commands that actually participated in this worktask's context (see `skills/self-improvement/SKILL.md § Step 4`).
- Post-ST audit entry written to `.context/logs/audit.jsonl` records `applied_count` and `skipped_count`.

## Embedded Command Detection

When the task description contains slash commands (e.g., `/skill-creator`, `/apple-developer:fix-refactor`), these are **embedded commands** that must be executed during the appropriate worktask stage.

### Detection Rules

1. Scan the task description for patterns matching `/<plugin:command>` or `/<command>`
2. Match against available skills listed in the system (Skill tool's available skills)
3. Store detected commands in `metadata.embedded_commands` on the PL0 task
4. Pass the embedded command context to PL0 so the product-manager can plan around it

> **Leading stacked skills**: when the user stacks slash commands
> (`/worktask /skill-a do XYZ`), Claude Code itself loads up to 5 **leading** skills before the
> turn runs — the embedded command's SKILL instructions may already be in context at PL0 time.
> Extraction into `metadata.embedded_commands` is unchanged, and the DV-stage `Skill()` invocation
> stays mandatory (it is the execution trigger, not a context load). Re-invoking an already-loaded
> skill does not append a duplicate copy of its instructions, so the DV
> invocation is token-safe.

### Execution

During the orchestrator execution loop, when executing a DV stage task:

1. Check if the worktask's PL0 task has `metadata.embedded_commands`
2. If present, the DV stage agent prompt MUST include: "Execute embedded command(s) via the Skill tool: `<command>` with args: `<args>`"
3. The DV agent invokes `Skill({skill: "<command>", args: "<args>"})` before or as part of its implementation work

### Examples

```
# User input:
/worktask /skill-creator deep analyze /path/to/source

# Parsed as:
# - Worktask task: "deep analyze /path/to/source"
# - Embedded command: skill-creator with args "deep analyze /path/to/source"
# - metadata.embedded_commands: "skill-creator"
# - DV stage prompt includes: "Invoke Skill('skill-creator', args='deep analyze /path/to/source')"

# User input:
/worktask /apple-developer:fix-refactor src/Views/SettingsView.swift

# Parsed as:
# - Worktask task: "fix-refactor src/Views/SettingsView.swift"
# - Embedded command: apple-developer:fix-refactor with args "src/Views/SettingsView.swift"
# - metadata.embedded_commands: "apple-developer:fix-refactor"
```

### Error Handling

Embedded command execution MUST NOT silently fall back to generic DV work.
If the Skill invocation fails, the DV stage MUST record the failure and
escalate — otherwise the user's intent is lost.

#### Failure Modes

| Failure | Detection | Required Behavior |
|---------|-----------|-------------------|
| Skill name not resolvable | `Skill()` returns "skill not found" | Write `.context/errors/developer.md` entry with `Classification: missing_input`; escalate to TL (or PL if no TL0) |
| Skill execution errors mid-run | Skill tool returns non-success | `retry_count++`, append entry to `.context/errors/developer.md`; if `retry_count == 3`, set `error_escalated_to: "TL"` (or `"PL"` if no TL0) |
| Skill args malformed | Skill rejects at parse | Classification `ambiguous_requirements`; escalate to PL (requires planning revision) |
| Skill produces no artifact expected by downstream stage | stage-contract validation fails | Classification `missing_input`; escalate to the stage whose contract was violated |

#### Prohibited Fallback

> DV MUST NOT proceed with generic implementation when the embedded command
> fails. The user explicitly requested that specific worktask by embedding
> the command; ignoring it is a silent deviation from their intent.

The DV agent's prompt template enforces this: on Skill failure, it halts and
writes an error entry with `metadata.embedded_command_failure: true` before
returning to the orchestrator.

#### Escalation Target

- **If TL0 exists**: escalate to TL (team lead decides whether to retry,
  split the work, or revise approach).
- **If no TL0 (low-complexity worktask)**: escalate to PL. PL may add TL0 to
  the worktask, revise embedded command choice, or remove the embedding.

## Headless Dispatch (external runners)

External orchestrators (CI, cron, the user's shell) can invoke a single stage via `claude agents run …` instead of the in-process Task() path. PL0 populates the optional dispatch fields documented in `skills/shared/state-ledger.md § Dispatch metadata`; the runner reads them and builds the flag string. Full table and per-stage examples live in `skills/agent-coordination/references/headless-dispatch.md`.

### Canonical one-liner & runner rules

The copy-paste `claude agents run` one-liner (reads a task's `task.json` metadata + rendered `prompt.txt`), the `sonnet`-alias / `--permission-mode manual`↔`default` equivalence, the mandatory `external_dispatch` audit line, and the CI-only `--dangerously-skip-permissions` caveat all live in `skills/agent-coordination/references/headless-dispatch.md`.

## See Also

- `skills/worktask/SKILL.md` — execution loop, dynamic sizing, worktask modes
- `commands/megatask.md` / `skills/megatask/SKILL.md` — multi-issue milestone/array orchestration (the former `--milestone` surface)
- `skills/shared/stage-codes.md` — stage codes and track IDs
- `skills/agent-coordination/references/headless-dispatch.md` — `task.metadata` → `claude agents` flag bridge
- `agents/workflow-engineer.md` — troubleshooting
