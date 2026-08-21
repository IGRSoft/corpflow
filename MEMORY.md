# corpflow Plugin Memory

Repository-tracked memory note (lean rolling format). The authoritative cross-conversation memory lives at `~/.claude/projects/<slug>/memory/MEMORY.md`; full per-release narratives live in git history (`git log --grep="<version>"`) and in the CC band files indexed below. Release tooling reads the `Plugin version:` line — keep its exact format. Hard cap ~5KB: when Release History exceeds 12 rows, delete the oldest.

## Version Tracking

- Plugin version: **4.0.20** — prompt surface compressed 19.7% behavior-preserving (#313): canonical-copy dedup into `skills/shared/` and skill references, tables over prose, all tool grants/gate language/test-pinned anchors verbatim; sweep also fixed dead links, a drifted stage→model table, and six dangling anchors
- Claude Code min required: **2.1.233** (README.md is authoritative; pinned to the band top per the v3.35.0/v3.37.0 precedent — the ledger cutover itself no longer depends on any CC task tool)
- Claude Code latest integrated band: **2.1.221→2.1.233**

## CC Feature Band Index

Canonical band files live in the authoritative memory directory (`~/.claude/projects/<slug>/memory/`).

| Band | Canonical file | Plugin release |
|------|----------------|----------------|
| 2.1.221→2.1.233 | cc-features-2.1.221-233.md | v4.0.15 (Todo-tool removal → state-ledger cutover; 200-spawn cap gone; fork-by-default) |
| 2.1.216→2.1.220 | cc-features-2.1.216-220.md | v3.37.0 (nesting depth 5→3 + 20-concurrent cap; Opus 5 default; min CC → 2.1.220) |
| 2.1.210→2.1.215 | cc-features-2.1.210-215.md | v3.35.0 (MCP auto-background + spawn cap + "Needs input"; min CC → 2.1.215, version-gate cleanup) |
| 2.1.203→2.1.209 | cc-features-2.1.203-209.md | v3.34.0 (background-agent/worktree stabilization) |
| 2.1.185→2.1.202 | cc-features-2.1.185-202.md | v3.30.0 (background-default dispatch + Sonnet 5) |
| 2.1.176→2.1.183 | cc-features-2.1.176-183.md | v3.24.0 (agent-teams API) |
| 2.1.171→2.1.175 | cc-features-2.1.171-175.md | v3.17.0 (nested sub-agents) |
| 2.1.166→2.1.170 | cc-features-2.1.166-170.md | v3.13.0 (Fable 5) |
| 2.1.157→2.1.165 | cc-features-2.1.157-165.md | v3.12.0 |
| 2.1.151→2.1.156 | cc-features-2.1.151-156.md | v3.10.13 (top-Opus refresh) |
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

> Band files before 2.1.221 are missing from disk — plausibly collateral from the CC 2.1.228 bug "session cleanup deleting contents inside a project's memory folder". Index rows kept as the record of what existed.

## Release History (last 12, newest first)

- 2026-08-21: v4.0.20 — prompt-surface compression, 145 files 240k→193k words (#313): commands −27.6%, agents −20.9%, skills −16.3%; dedup one-directional into canonical copies with 605 citations re-verified; collateral fixes include the drifted `stage-codes.md § Model Lookup` table and the stale `stage-contracts.md` atomic-merge snippet.
- 2026-08-17: v4.0.19 — the three plugin rules the OV-184 test-strategy violation exposed: brief invocations derive from `<plan_file>` frontmatter (never a project README's core-commands snippet, which is full-suite-shaped and pre-empts QA's gate), `build-only` is selected rather than opt-in when the planned diff is comment/doc-only (and a post-QA doc-only change never re-triggers QA), and FN reverts build-tool churn as its last action before `git add`. The mechanical gate needed no change — it already denied the incident's exact `xcodebuild test -destination '…'` shape.
- 2026-08-17: v4.0.18 — local-path leaks in published PR/issue bodies from two directions, comment-density gate vs. per-declaration DocC, `hooks/lib/` self-test selection failing closed to FULL, duplicate-issue preflight scan, test-run dedupe keyed on the tree. (Row backfilled at 4.0.19 — the 4.0.18 cut did not update this file.)
- 2026-08-16: v4.0.17 — `state-merge.sh` consolidated into `hooks/` with the rest; the relative `state-patch.sh` arm went from `../..` to `..`, without which the Layer-2 net would have exited 0 and merged nothing. Version parity (AC-4) was already red in HEAD and is now green. Docs: skill eval sets are a specification, not a result — no case has ever been graded against model output; test counts re-derived (1374).
- 2026-08-16: v4.0.16 — five fail-open/silent-default fixes surfaced by a 4-platform 11-stage stress test: `scan-secrets.sh` returned 0 on a crashed regex engine; `state-merge.sh` resolved `.context/` from cwd, so the Layer-2 net never worked inside a DV worktree; the test-execution denial never named `--no-test`; tier extraction required parentheses; preflight now reports split worktree parents.
- 2026-08-15: v4.0.15 — CC 2.1.233 removed the Todo/task tools on every model the plugin dispatches; full cutover to a `state.json` `tasks{}` ledger, no mirror, no fallback.
- 2026-08-15: v4.0.14 — megatask conflict-prevention tooling from a 9-issue parallel-batch post-mortem (#291): condition-first conflict recovery, worktree scratch exclusion, pbxproj union resolver.
- 2026-08-13: v4.0.13 — plugin renamed `company-workflow` → `corpflow`; ids, env vars, and repo slug moved, vendor identity unchanged. BREAKING, no alias.
- 2026-08-12: v4.0.12 — activated guards already written: `metadata.workspace_path` now stamped by `/worktask`, unset is a loud failure, `dv-tree-preflight.sh` actually invoked.
- 2026-08-10: v4.0.11 — fail-loud worktask tooling from the #431 retrospective (9 proposals).
- 2026-08-07: v4.0.10 — eval audit (#279): held-out oracle grades each arm's binary against 30 cases.
- 2026-08-06: v4.0.9 — opt-in change→test selection behind `./run-tests.sh --changed`.

## Token Baselines

Authoritative per-surface baselines: `skills/cost-optimization/references/token-baselines.md`. This file no longer mirrors them.
