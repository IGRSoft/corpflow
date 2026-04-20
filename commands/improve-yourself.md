---
name: improve-yourself
description: Manual entry point for the self-improvement skill. Analyzes user edits since a baseline, classifies diffs, and writes .context/learnings.md with scoped approvable proposals. Complements automatic ST-stage invocation.
argument-hint: '[--since <ref>] [--target agents|skills|commands|all] [--dry-run] [--no-scope-filter] [--apply]'
allowed-tools: Read, Glob, Grep, Bash, Write, Edit, Task(igrsoft:prompt-engineer), TaskCreate, TaskUpdate, TaskGet, TaskList
model: sonnet
estimated-cost:
  min-tokens: 3000
  max-tokens: 20000
  model-distribution:
    sonnet: 80%
    opus: 20%
---

# Improve Yourself Command

Manual entry point for the `self-improvement` skill. Use when you want to run the retrospective **outside** of a full workflow — e.g., after ad-hoc edits, between workflows, or to iterate on proposals.

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
| `--no-scope-filter` | Skip the used-in-context filter (Step 4 of the skill). All mapped proposals are surfaced regardless of whether the target participated in any workflow. **Advanced — use with caution** (higher noise). | off |
| `--apply` | After presenting `learnings.md`, block until the user checks boxes and explicitly approves, then delegate checked items to `igrsoft:prompt-engineer`. | off |

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

### Phase 1 — Skill invocation

1. Parse flags.
2. Determine baseline SHA:
   - If `--since` present, use it (verify it's a valid git ref).
   - Else, delegate to `skills/self-improvement/scripts/detect-user-changes.sh` default resolution.
3. Build used-in-context set:
   - Default: via `skills/self-improvement/scripts/build-context-set.sh` (Task System + `.context/*.md` + git trailers).
   - If `--no-scope-filter` is set, mark the set as "unbounded" so the mapper keeps every mapped proposal.
4. Invoke the skill's classify → map → emit pipeline. Writes:
   - `.context/learnings.md` if any proposal survives; and
   - `.context/logs/self-improve-<ts>.log` always.
5. Filter proposals by `--target` (post-emit): drop items whose target path doesn't match the selected kind(s).

### Phase 2 — Present to user

Read `.context/learnings.md` back to the user, highlighting:
- Proposal count by confidence (high/medium).
- Deferred count.
- Out-of-context discard count (from log file).

### Phase 3 — Apply (only when `--apply` and not `--dry-run`)

1. STOP. Wait for the user to check the boxes (`- [ ]` → `- [x]`) of proposals they accept, then signal approval ("apply", "go").
2. Re-read `.context/learnings.md`; collect checked items.
3. Delegate to `igrsoft:prompt-engineer` with the protocol from `agents/prompt-engineer.md § Self-Improvement Patch Application`. Each applied proposal becomes its own commit with a `version:` bump on the target.
4. Append an audit entry to `.context/logs/audit.jsonl`:
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

This command and the ST-stage automatic invocation share the same skill and write the same `.context/learnings.md`. Use the manual command when:

- You are **not** running a full `/workflow` — e.g., touching up prompts after ad-hoc edits.
- You want to **iterate** on the proposals (re-run with `--since` or `--target` to narrow).
- You want to **dry-run** to inspect the proposal set before committing to apply.

The ST-stage invocation is the production path — this command is for tooling and iteration.

## Constraints (DO NOT)

- DO NOT apply proposals without `--apply` and explicit user box-checking + approval message.
- DO NOT use `--no-scope-filter` in production workflows; it exists for diagnostics and edge cases.
- DO NOT run this command if a workflow is active (ST has not yet completed). Wait for the workflow's own ST-triggered retrospective instead.
- DO NOT write to `learnings.md` with the same timestamp if a prior run exists in the same second — the skill handles this by overwriting; callers must understand the file is single-slot per workspace.

## Related

- [self-improvement skill](../skills/self-improvement/SKILL.md) — the engine this command invokes
- [prompt-engineer](../agents/prompt-engineer.md) — applies approved proposals (Self-Improvement Patch Application section)
- [stakeholder](../agents/stakeholder.md) — automatic ST-stage invocation
- [optimize-agent](./optimize-agent.md) — on-demand agent scoring (complementary)
- [optimize-command](./optimize-command.md) — on-demand command scoring (complementary)
- [prompt-audit](./prompt-audit.md) — ecosystem-wide audit (complementary)

## Error Handling

| Situation | Command behavior |
|-----------|------------------|
| `--since <ref>` is invalid | Abort with clear message; do NOT fall back to HEAD silently. |
| No `.context/` directory present AND no `--since` given | Abort; ask user to run from a workflow workspace or pass `--since`. |
| Skill writes no `learnings.md` (no changes detected) | Print summary from log file; exit 0. |
| `--apply` given but user never checks any boxes | Log `applied_count: 0, skipped_count: <total>`; exit 0 without calling prompt-engineer. |
| prompt-engineer fails mid-apply | Commit any successfully applied proposals; surface the failure for the remaining items; do NOT revert partial work. |
