---
name: improve-yourself
description: Manual entry point for the self-improvement skill. Analyzes user edits since a baseline, classifies diffs, and writes .context/learnings.md with scoped approvable proposals. Complements automatic ST-stage invocation.
argument-hint: '[--since <ref>] [--target agents|skills|commands|all] [--dry-run] [--no-scope-filter] [--apply]'
allowed-tools: Read, Glob, Grep, Bash, Write, Edit, Task(company-workflow:prompt-engineer), TaskCreate, TaskUpdate, TaskGet, TaskList
model: sonnet
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

Manual entry point for the `self-improvement` skill. Use when you want to run the retrospective **outside** of a full worktask — e.g., after ad-hoc edits, between worktasks, or to iterate on proposals.

Invokes `skills/self-improvement/SKILL.md`. The skill handles the heavy lifting; this command provides the CLI surface and wires user approval through to `prompt-engineer` for application.

## Usage

```
/improve-yourself                          # auto-detect baseline; scope to in-context items
/improve-yourself --since HEAD~5           # explicit baseline SHA/ref
/improve-yourself --target agents          # restrict proposals to agents only
/improve-yourself --dry-run                # produce learnings.md but never apply (read-only)
/improve-yourself --no-scope-filter        # allow proposals to files outside in-context set (advanced)
/improve-yourself --apply                  # after writing learnings.md, wait for user to check boxes, then apply
```

## Options

| Flag | Effect | Default |
|------|--------|---------|
| `--since <ref>` | Git ref used as diff baseline (`HEAD~N`, SHA, tag, branch) | Last commit with `Agent:` trailer; fallback HEAD |
| `--target <kind>` | `agents`, `skills`, `commands`, or `all` — filters proposals to the listed target type(s). Comma-separated for multiple. | `all` |
| `--dry-run` | Write `.context/learnings.md` but do not enter apply phase, even if user checks boxes. Useful for review only. | off |
| `--no-scope-filter` | Skip the used-in-context filter (Step 4 of the skill). All mapped proposals are surfaced regardless of whether the target participated in any worktask. **Advanced — use with caution** (higher noise). | off |
| `--apply` | After presenting `learnings.md`, block until the user checks boxes and explicitly approves, then delegate checked items to `company-workflow:prompt-engineer`. | off |

## Examples

```bash
# Typical manual retrospective after a burst of edits
/improve-yourself

# Review since the last release tag, don't apply
/improve-yourself --since v3.6.0 --dry-run

# Focus on skills only, apply after review
/improve-yourself --target skills --apply

# Allow cross-context proposals (e.g., when editing agents that didn't run)
/improve-yourself --no-scope-filter --dry-run
```

## Behavior

The skill owns the pipeline; this command wires flags around it:

1. Parse flags; resolve baseline (`--since` if given and valid, else `skills/self-improvement/scripts/detect-user-changes.sh` default resolution).
2. Build used-in-context set via `skills/self-improvement/scripts/build-context-set.sh`; `--no-scope-filter` marks it unbounded (mapper keeps every mapped proposal).
3. Run the skill's classify → map → emit pipeline — writes `.context/learnings.md` when proposals survive, `.context/logs/self-improve-<ts>.log` always. Post-filter proposals by `--target`.
4. Present `learnings.md` to the user: proposal count by confidence (high/medium), deferred count, out-of-context discard count.
5. **Apply phase** — see below.

### Step 5 — Apply Phase

Runs only with `--apply`, never under `--dry-run`: STOP for user box-checking (`- [ ]` → `- [x]`) + explicit approval message → re-read checked items → delegate to `company-workflow:prompt-engineer` per `agents/prompt-engineer.md § Self-Improvement Patch Application` (one commit + `version:` bump per proposal) → append audit line:

```json
{"actor": "command:/improve-yourself", "action": "self_improvement_applied", "applied_count": N, "skipped_count": M, "result": "ok"}
```

## Output Format

```markdown
# /improve-yourself — Results

**Baseline:** <sha>
**Scope:** <in-context | unbounded>
**Target filter:** <all | agents | skills | commands>

## Summary
- Detected diff hunks: <N>
- In-scope proposals: <N> (high: N, medium: N)
- Deferred (low confidence): <N>
- Out-of-context discards: <N>

## Next steps
- Review `.context/learnings.md` (written at <timestamp>)
- Check the boxes next to proposals you want applied
- Re-run with `--apply` (or reply "apply" if the current call used --apply)
```

## Relationship to Automatic ST Invocation

Same skill, same `.context/learnings.md`. The ST-stage invocation is the production path; use this command outside a full worktask, to iterate on proposals (`--since`/`--target`), or to `--dry-run` the proposal set before applying.

## Constraints (DO NOT)

- DO NOT apply proposals without `--apply` and explicit user box-checking + approval message.
- DO NOT use `--no-scope-filter` in production worktasks; it exists for diagnostics and edge cases.
- DO NOT run this command if a worktask is active (ST has not yet completed). Wait for the worktask's own ST-triggered retrospective instead.
- DO NOT write to `learnings.md` with the same timestamp if a prior run exists in the same second — the skill handles this by overwriting; callers must understand the file is single-slot per workspace.

## Error Handling

| Situation | Command behavior |
|-----------|------------------|
| `--since <ref>` is invalid | Abort with clear message; do NOT fall back to HEAD silently. |
| No `.context/` directory present AND no `--since` given | Abort; ask user to run from a worktask workspace or pass `--since`. |
| Skill writes no `learnings.md` (no changes detected) | Print summary from log file; exit 0. |
| `--apply` given but user never checks any boxes | Log `applied_count: 0, skipped_count: <total>`; exit 0 without calling prompt-engineer. |
| prompt-engineer fails mid-apply | Commit any successfully applied proposals; surface the failure for the remaining items; do NOT revert partial work. |
