---
name: improve-yourself
description: Manual entry point for the self-improvement skill. Analyzes user edits since a baseline, classifies diffs, and writes .context/learnings.md with scoped approvable proposals. Complements automatic ST-stage invocation.
argument-hint: '[--since <ref>] [--target agents|skills|commands|all] [--dry-run] [--no-scope-filter] [--apply]'
# tools: bare Bash is deliberate — the self-audit runs the repo's own lints and diff tooling,
# which differ per repository, so no matcher can name them; the bound is that proposals land
# in .context/learnings.md and are applied only under `--apply`.
allowed-tools: Read, Glob, Grep, Bash, Write, Edit, Task(corpflow:prompt-engineer)
estimated-cost:
  min-tokens: 3000
  max-tokens: 20000
  model-distribution:
    sonnet: 80%
    opus: 20%
related:
  - skills/self-improvement/SKILL.md
  - agents/prompt-engineer.md
  - agents/stakeholder.md
  - commands/optimize-agent.md
  - commands/optimize-command.md
  - commands/prompt-audit.md
---

# Improve Yourself Command

Manual entry point for the `self-improvement` skill — run the retrospective **outside** a full worktask (after ad-hoc edits, between worktasks, or to iterate on proposals). The ST-stage invocation is the production path; both run the same pipeline and write the same `.context/learnings.md`. `skills/self-improvement/SKILL.md` does the work; this command is the CLI surface and wires user approval through to `prompt-engineer`.

## Options

| Flag | Effect | Default |
|------|--------|---------|
| `--since <ref>` | Git ref used as diff baseline (`HEAD~N`, SHA, tag, branch) | Last commit with `Agent:` trailer; fallback HEAD |
| `--target <kind>` | `agents`, `skills`, `commands`, or `all` — filters proposals to those target types. Comma-separated for multiple. | `all` |
| `--dry-run` | Write `.context/learnings.md` but never enter the apply phase, even if the user checks boxes. Review only. | off |
| `--no-scope-filter` | Skip the used-in-context filter (Step 4 of the skill): surface all mapped proposals regardless of whether the target participated in any worktask. **Advanced — higher noise.** | off |
| `--apply` | After presenting `learnings.md`, block until the user checks boxes and explicitly approves, then delegate checked items to `corpflow:prompt-engineer`. | off |

## Examples

```bash
/improve-yourself                                  # manual retrospective after a burst of edits
/improve-yourself --since v4.0.0 --dry-run         # review since the last release tag, don't apply
/improve-yourself --target skills --apply          # skills only, apply after review
/improve-yourself --no-scope-filter --dry-run      # include agents that didn't run this session
```

## Behavior

The skill owns the pipeline; this command wires flags around it:

1. Parse flags; resolve baseline (`--since` if given and valid, else `skills/self-improvement/scripts/detect-user-changes.sh` default resolution).
2. Build used-in-context set via `skills/self-improvement/scripts/build-context-set.sh`; `--no-scope-filter` marks it unbounded (mapper keeps every mapped proposal).
3. Run the skill's classify → map → emit pipeline — writes `.context/learnings.md` when proposals survive, `.context/logs/self-improve-<ts>.log` always. Post-filter proposals by `--target`.
4. **Step 5b — append labels** (see below).
5. Present `learnings.md`: proposal count by confidence (high/medium), deferred count, out-of-context discard count, labels appended, and the `self-improve-counts:` line.
6. **Apply phase** — see below.

### Step 4 — Label Append

Runs `bash ${CLAUDE_PLUGIN_ROOT}/skills/self-improvement/scripts/append-labels.sh` with `--plugin-data=${CLAUDE_PLUGIN_DATA}` per `skills/self-improvement/SKILL.md § Step 5b`, which carries the dataset-resolution ladder and the fallback notice. Skipping this discards all labels the pipeline produced.

#### Invocation options

- `--worktask-id` from `.context/state.json`; outside worktask, pass `--since`, uses `manual-<YYYYMMDD-HHMMSS>`.
- `--dry-run` is read-only; reports row count that *would* append. Re-run without `--dry-run` to record.
- `SELF_IMPROVE_LABELS=0` makes this step a no-op.

#### Pipeline closure

The closing `bash ${CLAUDE_PLUGIN_ROOT}/skills/self-improvement/scripts/pipeline-counts.sh` runs last (`skills/self-improvement/SKILL.md § Step 5b — record the four counts`). Under `--dry-run`, pass `--dry-run` to it. Report its stderr line: `self-improve-counts: context_paths=N changed_paths=N mapped_rows=N appended_rows=N`.

#### Aggregating the dataset

Aggregate the accumulated dataset with `bash ${CLAUDE_PLUGIN_ROOT}/skills/self-improvement/scripts/label-stats.sh --plugin-data=${CLAUDE_PLUGIN_DATA}` (`--min-count=<n>` flags repeatedly-corrected targets and categories).

### Step 6 — Apply Phase

Runs only with `--apply`, never under `--dry-run`: STOP for user box-checking (`- [ ]` → `- [x]`) + explicit approval message → re-read checked items → delegate to `corpflow:prompt-engineer` per `agents/prompt-engineer.md § Self-Improvement Patch Application` (one commit + `version:` bump per proposal) → append audit line:

```json
{"actor": "command:/improve-yourself", "action": "self_improvement_applied", "applied_count": N, "skipped_count": M, "result": "ok"}
```

## Output Format

```markdown
# /improve-yourself — Results

**Baseline:** <sha> — **Scope:** <in-context | unbounded> — **Target filter:** <all | agents | skills | commands>

## Summary
- Detected diff hunks: <N>
- In-scope proposals: <N> (high: N, medium: N)
- Deferred (low confidence): <N>
- Out-of-context discards: <N>
- Labels appended to the label dataset (<plugin data | repo fallback>): <N> (dry-run: would append <N>)
- Pipeline counts: `self-improve-counts: context_paths=<N> changed_paths=<N> mapped_rows=<N> appended_rows=<N>`

## Next steps
- Review `.context/learnings.md` (written at <timestamp>)
- Check the boxes next to proposals you want applied
- Re-run with `--apply` (or reply "apply" if the current call used --apply)
```

## Constraints (DO NOT)

- DO NOT apply proposals without `--apply` and explicit user box-checking + approval message.
- DO NOT use `--no-scope-filter` in production worktasks; it exists for diagnostics and edge cases.
- DO NOT run this command while a worktask is active (ST not yet complete) — wait for that worktask's own ST-triggered retrospective.
- DO NOT expect `learnings.md` to accumulate runs: it is single-slot per workspace and a re-run overwrites it.

## Error Handling

| Situation | Command behavior |
|-----------|------------------|
| `--since <ref>` is invalid | Abort with a clear message; do NOT fall back to HEAD silently. |
| No `.context/` present AND no `--since` given | Abort; ask the user to run from a worktask workspace or pass `--since`. |
| Skill writes no `learnings.md` (no changes detected) | Print summary from the log file; exit 0. |
| Context set resolves empty (no `Agent:` provenance to scope against) | Say so explicitly — every change is discarded and zero labels written, indistinguishable from "no edits" unless named. Suggest `--no-scope-filter` for a diagnostic pass. |
| `--apply` given but no boxes ever checked | Log `applied_count: 0, skipped_count: <total>`; exit 0 without calling prompt-engineer. |
| prompt-engineer fails mid-apply | Keep the successfully applied commits; surface the failure for the remaining items; do NOT revert partial work. |
