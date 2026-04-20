---
name: logging-conventions
description: Route runtime log capture to `.context/logs/`. Use when an agent pipes build, test, simulator, Monitor, or incident output via background Bash or `tee`. Covers filename grammar, `error.md` vs `logs/` split, and cleanup.
effort: low
---

# Logging Conventions

Runtime log capture routing for the igrsoft workflow. Pairs with `task-folder-organization`.

## The Split

Two artifacts — two purposes — two locations.

| Artifact | Location | Author | Purpose |
|----------|----------|--------|---------|
| `error.md` | `.context/error.md` | Human / agent narrative | Escalation story: what went wrong, retry count, handoff context |
| `*.log` | `.context/logs/` | Machine-written stdout/stderr | Raw runtime capture for post-hoc inspection |


## Filename Grammar

```
<kind>-<scope>-<YYYYMMDD-HHMMSS>.log
```

### Kind Taxonomy

| Kind | Source | Example |
|------|--------|---------|
| `build` | `build_sim`, SwiftPM, CI builds | `build-ios-sim-20260420-141522.log` |
| `test` | `test_sim`, XCTest, test suites | `test-qa-20260420-143008.log` |
| `monitor` | `Monitor`-tool streams | `monitor-developer-20260420-142250.log` |
| `sim` | `launch_app_logs_sim`, `start_sim_log_cap` | `sim-iphone15-20260420-143201.log` |
| `incident` | IR background tails | `incident-20260420-090512.log` |
| `hotfix` | Emergency DV stream | `hotfix-auth-20260420-103344.log` |

### Scope

Free-form short tag identifying the owner or target. Prefer: agent name (`developer`, `qa-engineer`), simulator id (`iphone15`), stage code (`qa`, `dv`), or feature slug (`auth`, `checkout`). Keep ≤ 24 chars, kebab-case.

### Timestamp

`YYYYMMDD-HHMMSS` in UTC (or host local if agent is human-facing). Generate via `date -u +%Y%m%d-%H%M%S` in Bash.

## Bash Pattern

```bash
# Ensure .context/logs/ exists, then pipe background stdout+stderr.
mkdir -p .context/logs
LOG=".context/logs/build-ios-sim-$(date -u +%Y%m%d-%H%M%S).log"
xcodebuild -scheme App -destination 'platform=iOS Simulator,name=iPhone 15' \
  build 2>&1 | tee "$LOG"
```

When called from Claude Code's `Bash` tool with `run_in_background: true`, use the same `tee` so the stream persists even if the session closes.

## Monitor-Tool Pattern

1. Start background Bash writing to `.context/logs/monitor-<agent>-<ts>.log` (via `tee`).
2. Attach `Monitor` to the running background id for live events.
3. When `Monitor` detaches, the file remains readable via `Read`.
4. Reference the file path in downstream stage docs (`testing.md`, `incident-report.md`, `release-prep.md`).

## Cleanup & Retention

- **Per-task hygiene**: `.context/logs/` is cleared together with the rest of `.context/` when the task archives (workflow FN stage or `/workflow` completion).
- **Size guard**: Each filename has a unique timestamp, so no rotation. Large logs remain readable; agents should stream or truncate on disk if needed.
- **Secrets**: Do not log secrets, tokens, or keychain data. If a tool prints them, redact before `tee` (e.g., `sed -E 's/(authorization|api[_-]?key|password|token|secret|bearer)[=:]\s*\S+/\1=REDACTED/'`). This pattern is starter-level; review the output to ensure no credentials leaked.
- **Git**: `.context/` follows the project's existing ignore policy — no special handling.

## Cross References

- `skills/task-folder-organization/SKILL.md` — canonical `.context/` folder rules.
- `skills/agent-coordination/SKILL.md` §Monitor Tool for Background Events — tool mechanics.
- `skills/incident-response/SKILL.md` — IR-specific log tailing.
- `agents/workflow-engineer.md` §Handle Error — `error.md` escalation (narrative counterpart).

## Common Mistakes

1. **Writing runtime output into `error.md`** — that file is for narrative escalation; raw captures belong in `logs/`.
2. **Missing timestamp** — without it, re-runs clobber prior evidence. Always include `$(date -u +%Y%m%d-%H%M%S)`.
3. **Scattering to `/tmp`** — logs outside `.context/` are invisible to downstream stages and get lost on workspace reset.
4. **Logging secrets** — redact before `tee`; never commit logs that might contain credentials.
5. **Creating a sibling `log/` folder** — canonical name is `logs/` (plural). One folder per project.
