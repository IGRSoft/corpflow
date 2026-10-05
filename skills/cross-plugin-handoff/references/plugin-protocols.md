# Plugin-Specific Protocols

Per-plugin stage→agent routing. The *plugin* serving each platform is subject to project
override (`skills/shared/routing-matrix.md § Project override`); the stage→agent shape
*within* a plugin is that plugin's contract and is not overridable row-by-row. Two rules
apply to every table below, so the cells do not repeat them:

- **AR is a consultation model** everywhere — the platform architect writes `.context/<platform>-architecture.md` and returns ≤500 tokens; `corpflow:software-architector` keeps the stage.
- **Evidence defaults** (`requires_screenshots`, Build Evidence adapter, `error_file` example) live in `skills/shared/compatible-plugins.md § Handoff defaults`. DV-support agents return findings to the parent DV agent and own no stage; their artifacts land under `.context/logs/`.

## apple-developer Plugin

| corpflow Stage | apple-developer Agent | Handoff Data |
|---------------|----------------------|--------------|
| AR | apple-architector | planning context + system constraints |
| DV | ios-developer, macos-developer, etc. | planning + architecture context |
| DR | code-fixer | `metadata.gate_blockers[]` + minimal-diff remediation |
| SR | security-auditor | development context + Apple security checklist (Keychain, ATS, entitlements, TCC, privacy manifest) |
| QA | test-generator | development context + test requirements |
| DC | gen-docs (command) | development context + API surface |
| RE | ios-developer, macos-developer | App Store/TestFlight submission data, notarization |
| IR | All platform agents | incident context + hotfix constraints (no App Store rollback) |

## system-developer Plugin

### system-developer — core stage handoffs

| corpflow Stage | system-developer Agent | Handoff Data |
|---------------|------------------------|--------------|
| AR | system-architector | planning context + system constraints |
| DV | system-developer (router), c-developer, cpp-developer, python-developer, bash-developer | planning + architecture context; CLI work carries terminal transcripts as Build Evidence |
| DR | sys-code-fixer | `metadata.gate_blockers[]` + minimal-diff remediation |

### system-developer — review, support & incident handoffs

| corpflow Stage | system-developer Agent | Handoff Data |
|---------------|------------------------|--------------|
| SR | sys-security-auditor | development context + systems security checklist (sanitizers, CWE Top 25, injection, hardening flags) |
| QA | sys-test-generator | development context + test requirements; QA gate includes ASan+UBSan clean on changed components |
| DV-support (performance) | sys-performance-engineer | profiling artifacts under `.context/logs/profile-*/` |
| DV-support (dependencies) | sys-dependency-manager | manifest paths (vcpkg.json, conanfile, pyproject.toml + uv.lock) + CVE audit scope |
| IR | All language agents | incident context + hotfix constraints |

## android-developer Plugin

### android-developer — architecture & development handoffs

| corpflow Stage | android-developer Agent | Handoff Data |
|---------------|-------------------------|--------------|
| AR | kotlin-architector | planning context + Android architecture constraints (Clean Architecture, modularization, Hilt DI) |
| DV | android-developer (router), android-phone-developer | planning + architecture context; no Android build MCP — builds run through scoped `Bash(gradle:*\|./gradlew\|adb:*)`, with Gradle transcripts alongside the screencap evidence |

### android-developer — review, QA & dependency handoffs

| corpflow Stage | android-developer Agent | Handoff Data |
|---------------|-------------------------|--------------|
| DR | and-code-fixer | `metadata.gate_blockers[]` + ktlint/detekt minimal-diff remediation |
| SR | and-security-auditor | development context + Android security checklist (DataStore + Tink/Keystore, no-cleartext, exported-component validation, no hardcoded secrets) |
| QA | and-test-generator | development context + test requirements; JUnit4/5, MockK, Turbine, Roborazzi screenshot tests |
| DV-support (dependencies) | and-dependency-manager | version catalog (`libs.versions.toml`) + Gradle dependency CVE audit scope |

## frontend-developer Plugin

### frontend-developer — architecture & development handoffs

| corpflow Stage | frontend-developer Agent | Handoff Data |
|---------------|--------------------------|--------------|
| AR | frontend-architector | planning context + rendering-strategy constraints (CSR/SSR/SSG/ISR, state management, design system) |
| DV | frontend-developer (router), react-developer, vue-developer, svelte-developer, angular-developer, typescript-developer, css-developer | planning + architecture context |

### frontend-developer — review, QA & support handoffs

| corpflow Stage | frontend-developer Agent | Handoff Data |
|---------------|--------------------------|--------------|
| DR | fe-code-fixer | `metadata.gate_blockers[]` + ESLint/Biome minimal-diff remediation |
| SR | fe-security-auditor | development context + web security checklist (XSS, CSP, auth-token storage, dependency supply chain) |
| QA | fe-test-generator | development context + test requirements; Vitest/Jest, Testing Library, Playwright |
| QA-support (accessibility) | fe-accessibility-auditor | WCAG 2.2 audit scope + axe/Lighthouse reports |
| DV-support (performance) | fe-performance-engineer | Lighthouse, Core Web Vitals, bundle-analysis artifacts |
| DV-support (dependencies) | fe-dependency-manager | `package.json` + lockfile paths + CVE audit scope |

## backend-developer Plugin

### backend-developer — architecture & development handoffs

| corpflow Stage | backend-developer Agent | Handoff Data |
|---------------|-------------------------|--------------|
| AR | backend-architector | planning context + service decomposition and data constraints |
| DV | backend-developer (router), node-developer, go-developer, jvm-backend-developer, python-backend-developer, api-designer, database-engineer | planning + architecture context |

### backend-developer — review, QA & support handoffs

| corpflow Stage | backend-developer Agent | Handoff Data |
|---------------|-------------------------|--------------|
| DR | be-code-fixer | `metadata.gate_blockers[]` + minimal-diff remediation |
| SR | be-security-auditor | development context + OWASP API Top 10 checklist (authz boundaries, injection, secret handling, dependency CVEs) |
| QA | be-test-generator | development context + test requirements; unit, integration (Testcontainers), contract tests |
| DV-support (performance) | be-performance-engineer | k6 load reports, hot-path profiles, slow-query analysis |
| DV-support (dependencies) | be-dependency-manager | per-ecosystem manifests + CVE audit scope |

## ai-engineer Plugin

| corpflow Stage | ai-engineer Agent | Handoff Data |
|---------------|-------------------|--------------|
| AR | ai-architector | planning context + model/pipeline constraints |
| DV | ai-engineer (router), llm-engineer, ml-engineer, mlops-engineer | planning + architecture context |
| DR | ai-code-fixer | `metadata.gate_blockers[]` + minimal-diff remediation |
| SR | ai-security-auditor | development context + AI security checklist (prompt injection, training/inference data leakage, model supply chain) |
| QA | ai-test-generator | development context + eval/test requirements |
| DV-support (performance) | ai-performance-engineer | inference latency and throughput profiles |
| DV-support (prompts) | ai-prompt-engineer | prompt-tuning scope + eval baselines |
| DV-support (dependencies) | ai-dependency-manager | ML dependency manifests + CVE audit scope |

## security-scanning Plugin

| corpflow Stage | security-scanning Agent | Handoff Data |
|---------------|------------------------|--------------|
| SR | security-scanning-security-auditor | code + OWASP checklist |
| SR | threat-modeling-expert | architecture + threat analysis |

## debugging-toolkit Plugin

| corpflow Stage | debugging-toolkit Agent | Handoff Data |
|---------------|------------------------|--------------|
| DV | debugging-toolkit-debugger | error logs, stack traces |
| DV | debugging-toolkit-dx-optimizer | worktask friction points |
| IR | debugging-toolkit-debugger | production logs, RCA context |

Support-plugin invocation ids double the plugin slug (`skills/shared/routing-matrix.md § Support-plugin aliases`).

## Error Handling

### External Agent Failure

1. Log the failure: `Agent {name} failed: {error}`.
2. Critical task → retry with the same context, max 3 attempts. Still failing: reset for manual handling (`state-patch.sh --task-status "<ID>" pending`) and create a blocker task.
3. Non-critical → mark partial completion and document what was achieved.
4. Either way, carry it into the handoff as `PARTIAL_FAILURES: - Agent: {name}, Error: {error}, Impact: {impact}`.

Tool restrictions on the child (server-level MCP denials, `WebSearch`): `skills/agent-coordination/references/headless-dispatch.md § Child tool grants`.

### Context Overflow

If a handoff exceeds its token budget: compress P2/P3 items, reference the full output by file path, and keep only critical items inline.
