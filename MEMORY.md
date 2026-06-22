# igrsoft Plugin Memory

Repository-tracked memory note (lean rolling format). The authoritative cross-conversation memory lives at `~/.claude/projects/<slug>/memory/MEMORY.md`; full per-release narratives live in git history (`git log --grep="<version>"`) and in the CC band files indexed below. Release tooling reads the `Plugin version:` line — keep its exact format. Hard cap ~5KB: when Release History exceeds 12 rows, delete the oldest.

## Version Tracking

- Plugin version: **3.24.1** (Removed worktask prefix-trigger convention — `worktask:`/`emergency:` prefixes retired; launch only via `/worktask` command (`--emergency` for incidents) or `Skill`; `worktask-triggers.md`→`worktask-invocation.md`. ~19 files, docs/metadata only)
- Claude Code min required: **2.1.183** (README.md is authoritative; Fable alias resolves only on CC ≥ 2.1.170)
- Claude Code latest integrated band: **2.1.176→2.1.183**

## CC Feature Band Index

Canonical band files live in the authoritative memory directory (`~/.claude/projects/<slug>/memory/`).

| Band | Canonical file | Plugin release |
|------|----------------|----------------|
| 2.1.176→2.1.183 | cc-features-2.1.176-183.md | v3.24.0 (agent-teams API) |
| 2.1.171→2.1.175 | cc-features-2.1.171-175.md | v3.17.0 (nested sub-agents) |
| 2.1.166→2.1.170 | cc-features-2.1.166-170.md | v3.13.0 (Fable 5) |
| 2.1.157→2.1.165 | cc-features-2.1.157-165.md | v3.12.0 |
| 2.1.151→2.1.156 | cc-features-2.1.151-156.md | v3.10.13 (Opus 4.8) |
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

## Release History (last 12, newest first)

- 2026-06-22: v3.24.1 — removed worktask prefix-trigger convention: `worktask:`/`emergency:` message prefixes retired (pure doc convention, never parsed by hook/settings). Pipeline launches only via `/worktask` (`--emergency` for incidents, `--secure`/`--full` for 11-stage) or `Skill({skill:"igrsoft:worktask"})`. `skills/shared/worktask-triggers.md` → `worktask-invocation.md` (§BLOCKING + INVOCATION GATE rekeyed to command/skill; dynamic-sizing + plan_gate/fn_gate preserved); 3 inbound links fixed. request-plan/estimation handoff now emits `/worktask "<goal>"`; estimate/cost sizing tables de-prefixed; incident-responder/release-engineer/security-reviewer/incident-response emergency docs reframed (dead `secure-worktask:`/`full-worktask:` prefixes + dangling `commands/emergency.md` ref cleaned). ~19 files across agents/, commands/, skills/, README, MEMORY.
- 2026-06-22: v3.25.0 — restored PL plan-approval gate + single `worktask` trigger: `plan_gate` defaults to `"checkpoint"` (was `bypass` for /worktask); new `commands/worktask.md § Step A.5` Plan Gate Check STOPs after PL0, presents the plan, `AskUserQuestion`, logs `approval_received` `subject:"PL<run_index>"`; `SKILL.md` PRECONDITION CHECK requires the approval line on `checkpoint`. New `--auto-plan` flag → `plan_gate:"bypass"` (trusted fast-path); `--milestone:N` bypasses both gates. FN gate unchanged (`fn_gate:"bypass"`). Removed triggers `micro:`/`quick:`/`fworktask:` (single `worktask` trigger; PL0 dynamic sizing drops stages for small work), deleted `--auto-continue` flag and `skills/worktask/references/approval-gate-hook.md`. Reconciled trigger/estimation/cost/request-plan docs. ~17 files across agents/, commands/, skills/, README, MEMORY.
- 2026-06-19: v3.24.0 — CC 2.1.176→2.1.183 band (agent-teams API + auto-mode guardrails): `TeamCreate`/`TeamDelete` removed → implicit per-session team, spawn via `Agent(name: …)`, `team_name` ignored (v2.1.178) — rewritten across `task-system.md`, `worktask-milestone/references/agent-teams.md`, `agent-coordination/*`, `worktask/references/stage-details.md`; auto-mode git safety (destructive-git / non-agent `--amend` / IaC `destroy` blocks) + `attribution.sessionUrl` in `git-conventions.md` + `create-pr.md`; scheduled/webhook trigger deliveries can't satisfy an approval park (`resume.md`); pre-launch spawn classification + fg/bg 5-level depth parity + `Tool(param:value)` syntax (`agent-coordination/SKILL.md`); subagent MCP server-level `disallowedTools` + WebSearch (`headless-dispatch.md`, `plugin-protocols.md`); compaction `--fallback-model` (`context-compression/SKILL.md`); model-governance (`model-selection.md`); workflow auto-engage scoping (`dynamic-workflow.md`); `cc-update.md` mapping refresh. Min CC 2.1.169→2.1.183. Docs/metadata only.
- 2026-06-19: v3.23.2 — recall-first DR review gate: `commands/code-review-dev.md` (v0.1.2) rewritten around recall — decoupled Phase 1 DETECTION / Phase 2 VERIFY+FILTER / Phase 3 completeness, 12-class bug checklist, mandatory read-beyond-the-diff, BLOCKED-keep rule, P0/P1/P2 severity routing, explicit decision+coverage output; Conductor review tools adapted → read-only git (`git diff origin/master...HEAD`) + findings to `developer-review-N.md` (`allowed-tools` declares read-only `git diff`/`log`/`show`); added Escalation-to-DV loop (read-confirmed sound P0/P1 → `verdict: fail` re-dispatches DV, then DR re-review). `agents/technical-lead.md` (v0.2.1): DR cross-ref + routing fix — DR3.5/visual-evidence escalation classification `ambiguous_requirements` (matrix→PL) → `missing_input` (matrix→previous stage=DV), correcting a mis-route of DV-owned escalations to PL. Also retired two unused commands (`/api-docs`, `/onboard-task`) — deleted from `commands/` + `.claude-plugin/marketplace.json` (45→43 commands).
- 2026-06-19: v3.23.1 — OV-131 worktask guardrails (#164/#165): new canonical `skills/shared/worktask-triggers.md` (§BLOCKING first-action rule + trigger table) repairing dangling refs in `skills/SKILL.md` + `skills/worktask/SKILL.md`; INVOCATION GATE banner in worktask SKILL.md; PL0 stamps `metadata.skipped_stages` [{stage,reason}] when dynamic sizing drops standard stages (state.json self-documents); new `metadata.plan_gate` carrier (`bypass` for /worktask|worktask:|fworktask:, `checkpoint` for micro:|quick:, mirrors `fn_gate`) so `resume.md` honors the post-plan human checkpoint on interruption.
- 2026-06-17: v3.23.0 — worktask always worktree-isolated + fully unattended: removed `--worktree` flag, complexity-30 isolation gate, and legacy `.workspaces/` milestone mode; dropped both human approval gates (post-PL0 and pre-FN); PL0 now stamps `metadata.isolation:"worktree"` and `fn_gate:"bypass"` unconditionally; ~20 files updated across agents/, commands/, skills/.
- 2026-06-15: v3.22.1 — PL plan-file overwrite fix: on a worktask re-run in a populated `.context/`, `commands/worktask.md` step 3a hard-coded `planning-0.md`/`run_index:0`, colliding with PL0's increment algorithm → PL sometimes overwrote `planning-0.md`. Seed is now re-run aware (bash glob+increment to next free `planning-N`); product-manager.md marks PL0 the authoritative writer (recompute N, never overwrite existing); handoff-protocol.md + initialization-patterns.md seeds reconciled (`run_index` restored — was schema-required but omitted). Related: v3.12.1.
- 2026-06-15: v3.22.0 — request-plan skill + /request-plan command: lightweight context-aware plan-from-request bridge (goal/scope/P0-P1-P2 phases/rough effort/risks) → worktask trigger handoff; reuses estimation tier-selection + three-stage-planning phasing instead of duplicating /pm-requirements or /estimate. Registered in marketplace.json + skills index.
- 2026-06-14: v3.21.0 — android-developer plugin routing: developer.md `android` detection row retargeted from dead "kotlin patterns" to `android-developer:android-developer`, Android Platform Specialization + Direct Routing tables (phone/architecture/test/code-fix), `Task(android-developer:*)` delegations, cross-plugin-handoff android-developer protocol table + error_file rule, `android_adapter` (adb screencap, `requires_screenshots: true`) Build Evidence. No Android build MCP — scoped `Bash(gradle/./gradlew/adb)`. Requires android-developer plugin installed alongside igrsoft.
- 2026-06-12: v3.18.0 — system-developer plugin routing: developer.md detection rules + specialist tables for C/C++/Python/Bash (closes unhandled `.py` gap), `systems` platform enum + cli-fallback screenshot row, cross-plugin-handoff system-developer protocol table.
- 2026-06-12: v3.17.0 — CC 2.1.171→2.1.175 band (15 files): 5-level nested sub-agents, availableModels/enforceAvailableModels caveats, Fable-1M degrade + R8, fable-blind drift fixes.
- 2026-06-12: v3.16.0 — screenshot-attachment wiring (#150): PL stamps `requires_screenshots` (detect-ui-change.sh S1–S4, fail-safe-true), PR `## Visual evidence` embed + marker-deduped issue comment via attach-visual-evidence.sh (PUBLISH_LIB_ONLY host-tier reuse; UI change ⇒ screenshots on BOTH issue and PR).
## Token Baselines

Authoritative per-surface baselines: `skills/cost-optimization/references/token-baselines.md`. This file no longer mirrors them.
