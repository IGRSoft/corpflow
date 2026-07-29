# Compatible Dev-Plugin Registry

Canonical for **plugin-level** compatibility metadata: which dev plugins the orchestrator may
route to, their entry agents, functional-role agents, command-set tier, and handoff defaults.

**Not** canonical for agent routing. Marker→platform detection and platform→specialist tables
live in `skills/shared/platform-detection.md`; this file references that map and never copies it.

## Registry

| Plugin | Role | Platform key | Version floor | Entry agent | Command set | Workflow skill |
|--------|------|--------------|---------------|-------------|-------------|----------------|
| `apple-developer` | Apple platforms (Swift, SwiftUI, UIKit, AppKit) | `apple` | >=1.25.0 | `apple-developer:apple-developer` | core-parity + apple extras | `apple-developer:workflow-integration` |
| `system-developer` | C, C++, Python, Bash systems code | `systems` | >=1.5.0 | `system-developer:system-developer` | core-parity + `sanitize-check` | `system-developer:workflow-integration` |
| `android-developer` | Android (Kotlin, Compose, Gradle) | `android` | >=1.3.0 | `android-developer:android-developer` | core-parity | `android-developer:workflow-integration` |
| `frontend-developer` | Web UI (React, Vue, Svelte, Angular, TS, CSS) | `web` | >=1.2.0 | `frontend-developer:frontend-developer` | core-parity + `gen-component` | `frontend-developer:workflow-integration` |
| `backend-developer` | Services, APIs, persistence | `backend` | >=1.3.0 | `backend-developer:backend-developer` | core-parity + `gen-api`, `db-migrate`, `analyze-security` | `backend-developer:workflow-integration` |
| `ai-engineer` | AI/ML, LLM applications, MLOps | `ai` | >=1.1.0 | `ai-engineer:ai-engineer` | **own set** (documented exception) | *(add when available)* |

Apple extras: `analyze-issue`, `analyze-localization`, `gen-mock-api`, `fix-security-hardening`,
`review-swiftui`, `review-uikit`, `review-appkit`.

## Functional-role agents

Used by the stage agents that consult a dev plugin outside DV: AR (`software-architector`),
SR (`security-reviewer`), QA (`qa-engineer`), DR remediation.

| Plugin | Architect (AR) | Security auditor (SR) | Test generator (QA) | Code fixer (DR) |
|--------|----------------|-----------------------|---------------------|-----------------|
| `apple-developer` | `apple-architector` | `security-auditor` *(unprefixed)* | `test-generator` *(unprefixed)* | `code-fixer` *(unprefixed)* |
| `system-developer` | `system-architector` | `sys-security-auditor` | `sys-test-generator` | `sys-code-fixer` |
| `android-developer` | `kotlin-architector` | `security-auditor` *(unprefixed — collision, see § Naming)* | `test-generator` *(unprefixed — collision)* | `code-fixer` *(unprefixed — collision)* |
| `frontend-developer` | `frontend-architector` | `fe-security-auditor` | `fe-test-generator` (+ `fe-accessibility-auditor`) | `fe-code-fixer` |
| `backend-developer` | `backend-architector` | `be-security-auditor` | `be-test-generator` | `be-code-fixer` |
| `ai-engineer` | `ai-architector` | `ai-security-auditor` | `ai-test-generator` | `ai-code-fixer` |

## Core-parity command set

Every registered platform plugin exposes these 15 commands under its own namespace
(`/<plugin>:<command>`):

```
analyze-tech-debt   analyze-accessibility   arch-select    arch-review    review-code
fix-quick           fix-modernize           fix-performance   fix-refactor
gen-tests           gen-docs                deps           debug
build-test          develop-feature
```

Naming grammar: `analyze-*` read-only assessment (never Write/Edit) · `arch-*` architecture
selection and review · `review-*` code review · `fix-*` mutating remediation · `gen-*` artifact
generation · bare verbs for lifecycle (`deps`, `debug`, `build-test`, `develop-feature`).

**ai-engineer exception**: keeps its domain set — `review-code`, `analyze-security`, `data-audit`,
`deploy-check`, `eval-run`, `finetune-plan`, `prompt-optimize`, `rag-audit`. Only the two names
overlapping the standard were aligned. A future core-parity pass is optional, not required.

## Handoff defaults

| Plugin | `requires_screenshots` default | Evidence adapter | `error_file` example |
|--------|-------------------------------|------------------|----------------------|
| `apple-developer` | `true` | `apple-canvas` / simulator | `.context/errors/ios-developer.md` |
| `android-developer` | `true` | `android_adapter` (`adb exec-out screencap`) | `.context/errors/android-phone-developer.md` |
| `frontend-developer` | `true` | `web_adapter` (Playwright / Chrome MCP) + Lighthouse/axe | `.context/errors/react-developer.md` |
| `system-developer` | `false` | `cli_fallback_adapter` (build/test transcripts) | `.context/errors/c-developer.md` |
| `backend-developer` | `false` | `cli_fallback_adapter` (API transcripts, k6, migration logs) | `.context/errors/node-developer.md` |
| `ai-engineer` | `false` | `cli_fallback_adapter` (eval reports, metrics, training logs) | `.context/errors/llm-engineer.md` |

## Support (non-dev) plugins

`igrsoft`, `debugging-toolkit`, `security-scanning`, `skill-creator`, `conductor`, `claude-in-chrome`.

The plugin-prefix regex in `skills/worktask/scripts/publish-pl-issue.sh` MUST equal this list
united with the Plugin column of § Registry. Changing either without the other lets internal
agent identifiers leak into published GitHub issues.

## § Naming — agent-name collision warning

`android-developer` ships `security-auditor`, `test-generator`, and `code-fixer` under the same
bare names as `apple-developer`. Qualified `Task(plugin:agent)` IDs disambiguate at the call site,
but two things still break:

1. `error_file` derives from the agent basename, so both plugins write
   `.context/errors/test-generator.md` — a same-worktask collision.
2. Bare-name tables (e.g. `commands/pm-milestone.md`) become ambiguous without a Plugin column.

**Rule for new or replacement plugins**: functional-role agents MUST carry a plugin-unique prefix
(the `sys-` / `fe-` / `be-` / `ai-` pattern). Renaming android's three agents is a tracked
migration owned by that plugin, not by igrsoft.

## Adding or replacing a dev plugin

See `skills/cross-plugin-handoff/references/plugin-onboarding.md` — compatibility contract plus
the ordered touchpoint checklist.
