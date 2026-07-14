# Skills Index

All available skills for the igrsoft worktask plugin.

## Skills


### Capture, coordination & context

| Skill | Description | Effort |
|-------|-------------|--------|
| [dv-screenshot-capture](dv-screenshot-capture/SKILL.md) | Capture screenshots during DV stage as visual evidence for QA acceptance and DR review; platform-aware adapters (apple/web/android/cli-fallback) | medium |
| [agent-coordination](agent-coordination/SKILL.md) | Multi-agent coordination, handoffs, parallel execution, and error escalation | medium |
| [appstore-screenshots](appstore-screenshots/SKILL.md) | Device specs, layout patterns, typography, and Pencil MCP worktask for App Store screenshots | high |
| [claude-constitution](claude-constitution/SKILL.md) | Constitutional principles, ethics, and behavioral guidelines for AI agent behavior | medium |
| [context-compression](context-compression/SKILL.md) | Context compression between agent handoffs preserving critical information | medium |

### Cost, export & estimation

| Skill | Description | Effort |
|-------|-------------|--------|
| [cost-optimization](cost-optimization/SKILL.md) | Cost tracking and optimization strategies for AI agent worktasks | medium |
| [cross-plugin-handoff](cross-plugin-handoff/SKILL.md) | Protocol for handoffs between igrsoft worktask and external plugins | medium |
| [csv-export-templates](csv-export-templates/SKILL.md) | 13-category CSV export structure for Google Sheets import | low |
| [estimation-methodology](estimation-methodology/SKILL.md) | Complexity scoring (0-50 scale) and T-shirt sizing for project estimation | low |
| [gh-issue-dedup](gh-issue-dedup/SKILL.md) | One GitHub issue per `.context/` across worktask runs — follow-up runs comment on the existing issue instead of opening a duplicate | low |
| [incident-response](incident-response/SKILL.md) | Incident classification, hotfix worktask, rollback procedures, and post-mortem templates | high |

### Incident, logging & orchestration

| Skill | Description | Effort |
|-------|-------------|--------|
| [logging-conventions](logging-conventions/SKILL.md) | Route runtime log capture to `.context/logs/` with filename conventions and cleanup patterns | low |
| [megatask](megatask/SKILL.md) | Meta-orchestration of many worktasks across a GitHub milestone or issue array — dependency/blocker DAG, priority ordering, isolated per-issue worktrees, completion-driven monitor hook (the `/megatask` command) | high |
| [pencil-design-worktask](pencil-design-worktask/SKILL.md) | Design mockup generation worktask using Pencil MCP tools | high |
| [preview-ensurer](preview-ensurer/SKILL.md) | Detect SwiftUI View files without previews and auto-add minimal `#Preview` blocks | medium |
| [release-engineering](release-engineering/SKILL.md) | Semantic versioning, changelog generation, and deployment readiness patterns | high |

### Preview, release & review

| Skill | Description | Effort |
|-------|-------------|--------|
| [request-plan](request-plan/SKILL.md) | Lightweight context-aware plan (goal, scope, phases, rough effort, risks) from a free-form request, with a worktask-trigger handoff | medium |
| [senior-developer-review](senior-developer-review/SKILL.md) | Technical review framework for estimates by platform specialists | low |
| [security-review-process](security-review-process/SKILL.md) | OWASP Top 10 security review checklist, dependency supply-chain triage, and secure coding patterns | medium |
| [self-improvement](self-improvement/SKILL.md) | ST-stage retrospective: diff-based learning from user edits; writes `.context/learnings.md` with per-proposal approval checklist | medium |
| [task-folder-organization](task-folder-organization/SKILL.md) | Context folder structure (.context/) with artifact naming and path resolution | medium |

### Self-improvement, tasks & worktask

| Skill | Description | Effort |
|-------|-------------|--------|
| [worktask](worktask/SKILL.md) | Complete staged worktask system with dynamic sizing and stage management | high |
| [worktask-testing-strategy](worktask-testing-strategy/SKILL.md) | Test strategy planning guidance for PL and AR worktask stages | medium |

## Shared Utilities

Files in `shared/` are referenced by skills and agents, not loaded independently — **except `milestone-helpers/`**, which ships its own `SKILL.md` and loads as the `igrsoft:milestone-helpers` skill.

| File | Purpose |
|------|---------|
| [constitutional-base.md](shared/constitutional-base.md) | Base constitutional principles |
| [five-whys.md](shared/five-whys.md) | Five Whys root cause analysis technique |
| [git-conventions.md](shared/git-conventions.md) | Conventional Commits format, PR template, git safety rules |
| [stage-codes.md](shared/stage-codes.md) | Worktask stage code definitions |
| [task-system.md](shared/task-system.md) | Task System integration patterns |
| [worktask-invocation.md](shared/worktask-invocation.md) | Worktask invocation rule + execution model |
| [milestone-helpers/](shared/milestone-helpers/) | Milestone worktask helper utilities |
