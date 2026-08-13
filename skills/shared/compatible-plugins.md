# Compatible Dev-Plugin Registry

Canonical for **plugin-level** compatibility metadata: which dev plugins the orchestrator may
route to, their entry agents, functional-role agents, command-set tier, and handoff defaults.

**Not** canonical for agent routing. Marker→platform detection and platform→specialist tables
live in `skills/shared/platform-detection.md`; this file references that map and never copies it.

## Registry

### Identity and routing

| Plugin | Role | Platform key | Version floor | Entry agent |
|--------|------|--------------|---------------|-------------|
| `apple-developer` | Apple platforms (Swift, SwiftUI, UIKit, AppKit) | `apple` | >=1.25.0 | `apple-developer:apple-developer` |
| `system-developer` | C, C++, Python, Bash systems code | `systems` | >=1.5.0 | `system-developer:system-developer` |
| `android-developer` | Android (Kotlin, Compose, Gradle) | `android` | >=1.4.0 | `android-developer:android-developer` |
| `frontend-developer` | Web UI (React, Vue, Svelte, Angular, TS, CSS) | `web` | >=1.2.0 | `frontend-developer:frontend-developer` |
| `backend-developer` | Services, APIs, persistence | `backend` | >=1.3.0 | `backend-developer:backend-developer` |
| `ai-engineer` | AI/ML, LLM applications, MLOps | `ai` | >=1.2.0 | `ai-engineer:ai-engineer` |

### Command set and workflow skill

| Plugin | Command set | Workflow skill |
|--------|-------------|----------------|
| `apple-developer` | core-parity + apple extras | `apple-developer:workflow-integration` |
| `system-developer` | core-parity + `sanitize-check` | `system-developer:workflow-integration` |
| `android-developer` | core-parity | `android-developer:workflow-integration` |
| `frontend-developer` | core-parity + `gen-component` | `frontend-developer:workflow-integration` |
| `backend-developer` | core-parity + `gen-api`, `db-migrate`, `analyze-security` | `backend-developer:workflow-integration` |
| `ai-engineer` | **own set** + `build-test` (documented exception) | `ai-engineer:workflow-integration` |

Apple extras: `analyze-issue`, `analyze-localization`, `gen-mock-api`, `fix-security-hardening`,
`review-swiftui`, `review-uikit`, `review-appkit`.

## Functional-role agents

Used by the stage agents that consult a dev plugin outside DV: AR (`software-architector`),
SR (`security-reviewer`), QA (`qa-engineer`), DR remediation.

### Architect and security auditor

| Plugin | Architect (AR) | Security auditor (SR) |
|--------|----------------|-----------------------|
| `apple-developer` | `apple-architector` | `security-auditor` *(unprefixed)* |
| `system-developer` | `system-architector` | `sys-security-auditor` |
| `android-developer` | `kotlin-architector` | `and-security-auditor` |
| `frontend-developer` | `frontend-architector` | `fe-security-auditor` |
| `backend-developer` | `backend-architector` | `be-security-auditor` |
| `ai-engineer` | `ai-architector` | `ai-security-auditor` |

### Test generator and code fixer

| Plugin | Test generator (QA) | Code fixer (DR) |
|--------|---------------------|-----------------|
| `apple-developer` | `test-generator` *(unprefixed)* | `code-fixer` *(unprefixed)* |
| `system-developer` | `sys-test-generator` | `sys-code-fixer` |
| `android-developer` | `and-test-generator` | `and-code-fixer` |
| `frontend-developer` | `fe-test-generator` (+ `fe-accessibility-auditor`) | `fe-code-fixer` |
| `backend-developer` | `be-test-generator` | `be-code-fixer` |
| `ai-engineer` | `ai-test-generator` | `ai-code-fixer` |

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

### ai-engineer exception

Keeps its domain set — `review-code`, `analyze-security`, `data-audit`, `deploy-check`,
`eval-run`, `finetune-plan`, `prompt-optimize`, `rag-audit` — plus `build-test`, the one core
command the orchestrator structurally requires for a platform to be routable at all (DV/DR/QA
delegate their build gate to it). Only the two names overlapping the standard were renamed.
A wider core-parity pass is optional, not required.

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

`corpflow`, `debugging-toolkit`, `security-scanning`, `skill-creator`, `conductor`, `claude-in-chrome`.

The plugin-prefix regex in `skills/worktask/scripts/publish-pl-issue.sh` MUST equal this list
united with the Plugin column of § Registry. Changing either without the other lets internal
agent identifiers leak into published GitHub issues.

## § Naming — plugin-unique agent prefixes

Functional-role agents MUST carry a plugin-unique prefix: `sys-`, `and-`, `fe-`, `be-`, `ai-`.
Every registered plugin now complies except `apple-developer`, which predates the convention and
keeps the bare names `security-auditor`, `test-generator`, `code-fixer`, `dependency-manager`.

Two things break when two plugins ship the same bare name. Claude Code keys installed agents by
frontmatter `name`, so one silently overwrites the other. And `error_file` derives from the agent
basename, so both would write to the same `.context/errors/test-generator.md` inside one worktask.

`android-developer` held exactly that collision with `apple-developer` and was renamed to the
`and-` prefix in its 1.4.0 release. Since apple-developer is now the only plugin using bare names,
no collision remains — but a *new* plugin using them would re-create one, which is why the prefix
rule is binding for anything added from here.

## Adding or replacing a dev plugin

See `skills/cross-plugin-handoff/references/plugin-contract.md` — the normative contract plus
the ordered touchpoint checklist.
