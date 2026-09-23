# corpflow Plugin Memory

Repository-tracked memory (lean rolling format). Narratives live in git history, `CHANGELOG.md`, and the CC band files indexed below. Release tooling reads the `Plugin version:` line; keep its format. Hard cap ~5KB; Release History keeps 12 rows.

## Version Tracking

- Plugin version: **4.0.32** (released 2026-09-11; carried while develop is in progress. Unreleased on develop: correctness pass, `/cc-update` 0.3.0 passes, CC 2.1.252→2.1.270 band, CC 2.1.271→2.1.280 band. Version bumps only at release.)
- Claude Code min required: **2.1.280** (README.md is authoritative; load-bearing: 2.1.271 closes the silent-failure class for cross-session messages held by the receiver's own permission-mode policy — headless senders now get a delivery notice, matching the 2.1.238 precedent this floor already tracks)
- Claude Code latest integrated band: **2.1.271→2.1.280**

## CC Feature Band Index

Canonical band files live in the authoritative memory directory (`~/.claude/projects/<slug>/memory/`).

| Band | Canonical file | Plugin release |
|------|----------------|----------------|
| 2.1.271→2.1.280 | cc-features-2.1.271-280.md | v4.0.32 develop (Opus 5.5 default, workflow-size 15→10, TaskOutput removal, held-message delivery notice; min CC → 2.1.280) |
| 2.1.252→2.1.270 | cc-features-2.1.252-270.md | v4.0.32 develop (queued reattach, SessionEnd timeout, FORCE preflight; min CC → 2.1.270) |
| 2.1.234→2.1.251 | cc-features-2.1.234-251.md | v4.0.27 (cross-session comms, delivery-checked reattach, PreModelSwitch gate; min CC → 2.1.251) |
| 2.1.221→2.1.233 | cc-features-2.1.221-233.md | v4.0.15 (Todo-tool removal → state ledger) |
| 2.1.216→2.1.220 | cc-features-2.1.216-220.md | v3.37.0 (nesting depth 3; Opus 5 default) |
| 2.1.210→2.1.215 | cc-features-2.1.210-215.md | v3.35.0 (MCP auto-background, spawn cap) |
| 2.1.203→2.1.209 | cc-features-2.1.203-209.md | v3.34.0 (background-agent/worktree stabilization) |
| 2.1.185→2.1.202 | cc-features-2.1.185-202.md | v3.30.0 (background-default dispatch, Sonnet 5) |
| 2.1.176→2.1.183 | cc-features-2.1.176-183.md | v3.24.0 (agent-teams API) |
| 2.1.171→2.1.175 | cc-features-2.1.171-175.md | v3.17.0 (nested sub-agents) |
| 2.1.166→2.1.170 | cc-features-2.1.166-170.md | v3.13.0 (Fable 5) |
| 2.1.157→2.1.165 | cc-features-2.1.157-165.md | v3.12.0 |
| 2.1.151→2.1.156 | cc-features-2.1.151-156.md | v3.10.13 |
| 2.1.143→2.1.150 | cc-features-2.1.143-150.md | v3.10.6 |
| 2.1.141→2.1.142 | cc-features-2.1.141-142.md | v3.9.3 |
| 2.1.129→2.1.140 | cc-features-2.1.129-140.md | v3.9.2 |
| 2.1.122→2.1.128 | cc-features-2.1.122-128.md | v3.8.1 |
| 2.1.115→2.1.121 | cc-features-2.1.115-121.md | v3.6.1 |
| 2.1.102→2.1.114 | cc-features-2.1.102-114.md | v3.6.0 |
| 2.1.92→2.1.101 | cc-features-2.1.92-101.md | v3.5.0 |
| 2.1.87→2.1.91 | cc-features-2.1.87-91.md | v3.4.0 |
| 2.1.77→2.1.86 | cc-features-2.1.77-86.md | v3.3.0 |
| 2.1.51→2.1.76 | cc-features-2.1.51-76.md | v3.1.0/v3.2.0 |

> Band files before 2.1.221 are missing from disk (likely the CC 2.1.228 memory-folder cleanup bug); rows kept as the record.

## Release History (last 12, newest first)

- 2026-09-23: v4.0.32 (develop) — Claude Code 2.1.280 update (6 files, min CC → 2.1.280, Opus 5.5 default, workflow-size 15→10, TaskOutput removal, held-message delivery notice).
- 2026-09-13: v4.0.32 (develop) — Claude Code 2.1.270 update (18 files, min CC → 2.1.270, queued reattach row, SessionEnd hook timeout, FORCE preflight).
- 2026-09-09: v4.0.31 — leaderboard V1 fix plan phases A–E: discovered-vs-executed evidence, sweep transport for five agents, AR contract before DV fan-out.
- 2026-09-08: v4.0.30 (cont.) — prompt-audit remediation, 26 findings across agents/commands/skills; tool-grant coverage and template backfill.
- 2026-09-08: v4.0.30 — leaderboard V1 self-hosting findings; breaking `handoffs` re-key per task id, per-task decision clamps.
- 2026-09-03/04: v4.0.29 — `fn-preflight base-sanity` for wrong PR bases on stacked branches, plus 13 run-remediation findings.
- 2026-09-03: v4.0.28 — closing-sweep transport divergence: `blocks_next_stage` stickiness and harness class checks.
- 2026-08-29: v4.0.27 — CC 2.1.234→2.1.251 band; delivery-checked reattach, cross_session_ask, PreModelSwitch gate; min CC → 2.1.251.
- 2026-08-26: v4.0.26 — command-surface reorganization: 38 → 28 commands, 26 → 23 skills; cost observability retired.
- 2026-08-24: v4.0.25 — plan-approval carrier `PL0.metadata.approved` gets writers at all three approval arms.
- 2026-08-22: v4.0.23 — CI pipeline from scratch with pipefail gate; POSIX `df -Pk` ENOSPC guard.
- 2026-08-21: v4.0.22 — trigger-first descriptions, rationalization tables, desc-lint G1–G6, proactive PL sizing.
