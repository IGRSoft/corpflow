# Target Mapping Rules

Every classified diff hunk must be mapped to exactly one owning file (the "target"). After mapping, the target is **filtered** against the used-in-context set from `SKILL.md § Step 1`. Out-of-context targets are discarded.

## Mapping Rules (apply first match)

| # | Pattern of changed file | Target | Notes |
|---|--------------------------|--------|-------|
| 1 | `agents/<name>.md`, `skills/**/SKILL.md`, `commands/<name>.md` | The file itself | User edited the prompt directly — self-signal. Map to that file. |
| 2 | `.context/planning-*.md` (numbered, e.g. `planning-0.md`, `planning-1.md`) | `agents/product-manager.md` | Producer lookup via stage-contracts. Match the glob — every numbered plan is owned by PM. |
| 3 | `.context/analyzing-*.md` | `agents/software-architector.md` | Match the glob — every numbered artifact owned by AR. |
| 4 | `.context/coordination-*.md` | `agents/team-lead.md` | |
| 5 | `.context/development-*.md` | `metadata.agent` of the DV task (resolve from `TaskList`) | Platform-aware: could be `igrsoft:developer`, `apple-developer:ios-developer`, etc. |
| 6 | `.context/developer-review-*.md` | `agents/technical-lead.md` | |
| 7 | `.context/security-review-*.md` | `agents/security-reviewer.md` | |
| 8 | `.context/testing-*.md` | `agents/qa-engineer.md` | |
| 9 | `.context/documentation-*.md` | `agents/technical-writer.md` | |
| 10 | `.context/release-*.md` | `agents/release-engineer.md` | |
| 11 | `.context/complete-summary-*.md` | `agents/project-manager.md` | |
| 12 | `.context/retrospective-*.md` | `agents/stakeholder.md` | Edits to own artifact — self-improvement for ST itself. |
| 13 | Source code (`src/**`, `app/**`, `lib/**`, `Sources/**`) | Resolved DV agent (same lookup as row 5) | Default to `agents/developer.md` if DV agent missing. |
| 14 | `README.md`, `docs/**`, `*.md` at repo root | `agents/technical-writer.md` | Only if DC stage ran in this workflow. |
| 15 | Tests (`tests/**`, `**/*Tests.swift`, `**/*_test.py`, `spec/**`) | `agents/qa-engineer.md` | Only if QA stage ran. |
| 16 | Config (`*.json`, `*.toml`, `*.yml`, `*.yaml`, `Makefile`, `Package.swift`) | Resolved DV agent (row 5) | Exception: `plugin.json` → `agents/workflow-engineer.md`. |
| 17 | No rule matched | Discard (logged) | Log under `## Out-of-Context Discards` in the run log. |

## In-Context Filter (mandatory)

After mapping, compare the target path against the used-in-context set:

```
if target_path in used_in_context_set:
    keep the proposal
else:
    log under "Out-of-Context Discards"; do NOT include in learnings.md
```

**Why:** if the user edited an artifact produced by an agent that did not participate in this workflow (e.g., user tweaked `.context/security-review-N.md` from a previous run while running a non-secure workflow), we must not propose updates to `agents/security-reviewer.md` — SR did not participate, so the edit belongs to a different feedback loop.

## Platform-Aware Resolution

When a stage was delegated to a cross-plugin agent (e.g., `apple-developer:ios-developer`):

- Target path = `plugins/<plugin>/agents/<basename>.md` where plugin comes from the qualified agent name.
- If the target plugin is outside this repo (external), discard the proposal and log:
  ```
  Cross-plugin target skipped: <qualified-agent> lives in <plugin>, not editable from this workflow.
  ```

## Edge Cases

| Situation | Rule |
|-----------|------|
| Hunk touches multiple files | Split into per-file hunks before mapping. |
| File moved/renamed in diff | Use the NEW path for mapping. |
| Binary file edited | Discard; log under `Discards` with reason `binary`. |
| File in `.context/logs/` edited | Discard; logs are ephemeral, not a learning signal. |
| File in `.context/errors/` edited | Discard; error narratives are already captured. |
| File matches `skills/self-improvement/**` | Discard; self-edits to this skill go through normal code review, not self-improvement loop (avoid recursion). |

## Data Sources for "Used-in-Context Set"

`SKILL.md § Step 1` defines precedence; this section lists the exact query shape.

### From TaskList

```
For each task where status == "completed":
  add metadata.agent  (normalize `igrsoft:<name>` → agents/<name>.md path)
  add metadata.embedded_commands (comma-split → commands/<name>.md paths)
```

### From `.context/*.md` metadata

Each stage artifact may include a trailer like:
```
---
metadata:
  agent: igrsoft:developer
  embedded_commands: apple-developer:code-refactor
---
```

Parse this block (if present) and add to the set.

### From git trailers

If the project policy uses `Agent:` / `Stage:` git trailers, scan `git log <agent_sha>..HEAD --format=%B` for trailer lines:
```
Agent: igrsoft:developer
Stage: DV
```

### Normalization

All sources produce file paths. Deduplicate. Drop paths that don't exist on disk.

## Cross References

- `skills/shared/stage-contracts.md` — stage → artifact producer mapping (rows 2–12)
- `skills/shared/task-system.md § Metadata Fields` — `agent`, `embedded_commands` schema
- `SKILL.md § Step 1` / `§ Step 4` — invocation of these rules in the pipeline
