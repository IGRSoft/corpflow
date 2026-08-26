# Compatible Dev-Plugin Registry

Canonical for **plugin-level** compatibility metadata: which dev plugins the orchestrator
may route to, their command-set tier, version floors, and handoff defaults. **Not**
canonical for agent routing — alias→agent routing (entry + functional roles, plus the
project-override mechanism) lives in `skills/shared/routing-matrix.md`; marker→platform
detection and platform→specialist tables live in `skills/shared/platform-detection.md`.
Both are referenced here and never copied.

## Registry

### Identity and routing

| Plugin | Role | Platform key | Version floor | Entry alias |
|--------|------|--------------|---------------|-------------|
| `apple-developer` | Apple platforms (Swift, SwiftUI, UIKit, AppKit) | `apple` | >=1.25.0 | `corpflow:apple-developer` |
| `system-developer` | C, C++, Python, Bash systems code | `systems` | >=1.5.0 | `corpflow:system-developer` |
| `android-developer` | Android (Kotlin, Compose, Gradle) | `android` | >=1.4.0 | `corpflow:android-developer` |
| `frontend-developer` | Web UI (React, Vue, Svelte, Angular, TS, CSS) | `web` | >=1.2.0 | `corpflow:frontend-developer` |
| `backend-developer` | Services, APIs, persistence | `backend` | >=1.3.0 | `corpflow:backend-developer` |
| `ai-engineer` | AI/ML, LLM applications, MLOps | `ai` | >=1.2.0 | `corpflow:ai-engineer` |

Entry aliases resolve to qualified `plugin:agent` targets in
`skills/shared/routing-matrix.md § Entry aliases` — the single copy of the target ids.

### Command set

| Plugin | Command set |
|--------|-------------|
| `apple-developer` | core-parity + apple extras + publishing |
| `system-developer` | core-parity + `sanitize-check` |
| `android-developer` | core-parity + publishing |
| `frontend-developer` | core-parity + `gen-component` |
| `backend-developer` | core-parity + `gen-api`, `db-migrate`, `analyze-security` |
| `ai-engineer` | **own set** + `build-test` (documented exception) |

The integration surface is each plugin's root `CORPFLOW.md`
(`skills/cross-plugin-handoff/references/plugin-contract.md § A.4`), which replaced the
former `workflow-integration` skill.

Apple extras: `analyze-issue`, `analyze-localization`, `gen-mock-api`, `fix-security-hardening`,
`review-swiftui`, `review-uikit`, `review-appkit`.

#### Publishing commands

Publishing commands are store-specific and exist only where there is a store — apple
`gen-appstore-listing`, `gen-appstore-screenshots`, `gen-appstore-iap`; android
`gen-playstore-listing`, `gen-playstore-screenshots` (Play Billing IAP is not ported). They are
reached through `/appstore`, which resolves the platform's release engineer via
`skills/shared/routing-matrix.md § Release-engineer aliases`; they are deliberately **not**
core-parity, since a store command is meaningless on a platform with no store.

## Functional-role agents

Used by stage agents consulting a dev plugin outside DV: AR (`software-architector`),
SR (`security-reviewer`), QA (`qa-engineer`), DR remediation. The per-platform
architect/security-auditor/test-generator/code-fixer targets are canonical in
`skills/shared/routing-matrix.md § Functional-role aliases` — this file keeps no copy.
QA on web additionally consults `fe-accessibility-auditor` (review-only roster:
`skills/shared/platform-detection.md § Review-only specialists`).

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
`eval-run`, `finetune-plan`, `prompt-optimize`, `rag-audit` — plus `build-test`, the one
core command structurally required for a platform to be routable at all (DV/DR/QA delegate
their build gate to it). Only the two names overlapping the standard were renamed; a wider
core-parity pass is optional.

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

The plugin-prefix regex in `skills/worktask/scripts/publish-pl-issue.sh` MUST equal this
list united with the Plugin column of § Registry (equivalently: the plugin set of the
default targets in `skills/shared/routing-matrix.md`). Changing any copy alone lets
internal agent identifiers leak into published GitHub issues.

## § Naming — plugin-unique agent prefixes

Functional-role agents MUST carry a plugin-unique prefix: `sys-`, `and-`, `fe-`, `be-`, `ai-`.
Every registered plugin complies except `apple-developer`, which predates the convention and
keeps the bare names `security-auditor`, `test-generator`, `code-fixer`, `dependency-manager`.

Two things break when two plugins ship the same bare name: Claude Code keys installed agents
by frontmatter `name`, so one silently overwrites the other; and `error_file` derives from
the agent basename, so both write to the same `.context/errors/test-generator.md` inside one
worktask. `android-developer` held exactly that collision and took the `and-` prefix in its
1.4.0 release. No collision remains today, but a *new* plugin using bare names would
re-create one — which is why the prefix rule binds anything added from here.

## Adding or replacing a dev plugin

See `skills/cross-plugin-handoff/references/plugin-contract.md` — the normative contract plus
the ordered touchpoint checklist.
