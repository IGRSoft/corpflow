# Plugin-Specific Protocols

## apple-developer Plugin

| company-workflow Stage | apple-developer Agent | Handoff Data |
|---------------|----------------------|--------------|
| AR (Architecture) | apple-architector | planning context + system constraints |
| DV (Development) | ios-developer, macos-developer, etc. | planning + architecture context |
| SR (Security) | security-auditor | development context + Apple security checklist (Keychain, ATS, entitlements, TCC, privacy manifest) |
| QA (Quality) | test-generator | development context + test requirements |
| DC (Documentation) | gen-docs (command) | development context + API surface |
| RE (Release) | ios-developer, macos-developer | App Store/TestFlight submission data, notarization |
| IR (Incident) | All platform agents | incident context + hotfix constraints (no App Store rollback) |

## system-developer Plugin

### system-developer — core stage handoffs

| company-workflow Stage | system-developer Agent | Handoff Data |
|---------------|------------------------|--------------|
| AR (Architecture) | system-architector | planning context + system constraints (consultation model, like apple-architector) |
| DV (Development) | system-developer (router), c-developer, cpp-developer, python-developer, bash-developer | planning + architecture context; `requires_screenshots: false` for CLI work (Build Evidence = terminal transcripts) |
| DR (Developer Review) | sys-code-fixer | gate blockers (`metadata.gate_blockers[]`) + minimal-diff remediation |

### system-developer — review, support & incident handoffs

| company-workflow Stage | system-developer Agent | Handoff Data |
|---------------|------------------------|--------------|
| SR (Security) | sys-security-auditor | development context + systems security checklist (sanitizers, CWE Top 25, injection, hardening flags) |
| QA (Quality) | sys-test-generator | development context + test requirements; QA gate includes ASan+UBSan clean on changed components |
| DV-support (performance) | sys-performance-engineer | profiling artifacts under `.context/logs/profile-*/` |
| DV-support (dependencies) | sys-dependency-manager | manifest paths (vcpkg.json, conanfile, pyproject.toml + uv.lock) + CVE audit scope |
| IR (Incident) | All language agents | incident context + hotfix constraints |

## android-developer Plugin

### android-developer — architecture & development handoffs

| company-workflow Stage | android-developer Agent | Handoff Data |
|---------------|-------------------------|--------------|
| AR (Architecture) | kotlin-architector | planning context + Android architecture constraints (Clean Architecture, modularization, Hilt DI — consultation model, like apple-architector) |
| DV (Development) | android-developer (router), android-phone-developer | planning + architecture context; `requires_screenshots: true` (Build Evidence = `adb exec-out screencap -p` via `android_adapter` + Gradle build/test transcripts); no Android build MCP — scoped `Bash(gradle:*\|./gradlew\|adb:*)` |

### android-developer — review, QA & dependency handoffs

| company-workflow Stage | android-developer Agent | Handoff Data |
|---------------|-------------------------|--------------|
| DR (Developer Review) | code-fixer | gate blockers (`metadata.gate_blockers[]`) + ktlint/detekt minimal-diff remediation |
| SR (Security) | security-auditor | development context + Android security checklist (EncryptedSharedPreferences/Keystore, no-cleartext, exported-component validation, no hardcoded secrets) |
| QA (Quality) | test-generator | development context + test requirements; JUnit4/5, MockK, Turbine, Roborazzi screenshot tests |
| DV-support (dependencies) | dependency-manager | version catalog (`libs.versions.toml`) + Gradle dependency CVE audit scope |

## frontend-developer Plugin

### frontend-developer — architecture & development handoffs

| company-workflow Stage | frontend-developer Agent | Handoff Data |
|---------------|--------------------------|--------------|
| AR (Architecture) | frontend-architector | planning context + rendering-strategy constraints (CSR/SSR/SSG/ISR, state management, design system — consultation model, like apple-architector) |
| DV (Development) | frontend-developer (router), react-developer, vue-developer, svelte-developer, angular-developer, typescript-developer, css-developer | planning + architecture context; `requires_screenshots: true` (Build Evidence = `web_adapter` → Playwright / Chrome MCP + Lighthouse and axe reports) |

### frontend-developer — review, QA & support handoffs

| company-workflow Stage | frontend-developer Agent | Handoff Data |
|---------------|--------------------------|--------------|
| DR (Developer Review) | fe-code-fixer | gate blockers (`metadata.gate_blockers[]`) + ESLint/Biome minimal-diff remediation |
| SR (Security) | fe-security-auditor | development context + web security checklist (XSS, CSP, auth-token storage, dependency supply chain) |
| QA (Quality) | fe-test-generator | development context + test requirements; Vitest/Jest, Testing Library, Playwright |
| QA-support (accessibility) | fe-accessibility-auditor | WCAG 2.2 audit scope + axe/Lighthouse reports |
| DV-support (performance) | fe-performance-engineer | Lighthouse, Core Web Vitals, bundle-analysis artifacts under `.context/logs/` |
| DV-support (dependencies) | fe-dependency-manager | `package.json` + lockfile paths + CVE audit scope |

## backend-developer Plugin

### backend-developer — architecture & development handoffs

| company-workflow Stage | backend-developer Agent | Handoff Data |
|---------------|-------------------------|--------------|
| AR (Architecture) | backend-architector | planning context + service decomposition and data constraints (consultation model, like apple-architector) |
| DV (Development) | backend-developer (router), node-developer, go-developer, jvm-backend-developer, python-backend-developer, api-designer, database-engineer | planning + architecture context; `requires_screenshots: false` (Build Evidence = API request/response transcripts, test output, k6 load reports, migration logs) |

### backend-developer — review, QA & support handoffs

| company-workflow Stage | backend-developer Agent | Handoff Data |
|---------------|-------------------------|--------------|
| DR (Developer Review) | be-code-fixer | gate blockers (`metadata.gate_blockers[]`) + minimal-diff remediation |
| SR (Security) | be-security-auditor | development context + OWASP API Top 10 checklist (authz boundaries, injection, secret handling, dependency CVEs) |
| QA (Quality) | be-test-generator | development context + test requirements; unit, integration (Testcontainers), contract tests |
| DV-support (performance) | be-performance-engineer | k6 load reports, hot-path profiles, slow-query analysis under `.context/logs/` |
| DV-support (dependencies) | be-dependency-manager | per-ecosystem manifests + CVE audit scope |

## ai-engineer Plugin

### ai-engineer — architecture & development handoffs

| company-workflow Stage | ai-engineer Agent | Handoff Data |
|---------------|-------------------|--------------|
| AR (Architecture) | ai-architector | planning context + model/pipeline constraints (consultation model, like apple-architector) |
| DV (Development) | ai-engineer (router), llm-engineer, ml-engineer, mlops-engineer | planning + architecture context; `requires_screenshots: false` (Build Evidence = eval reports, metric tables, training transcripts under `.context/logs/`) |

### ai-engineer — review, QA & support handoffs

| company-workflow Stage | ai-engineer Agent | Handoff Data |
|---------------|-------------------|--------------|
| DR (Developer Review) | ai-code-fixer | gate blockers (`metadata.gate_blockers[]`) + minimal-diff remediation |
| SR (Security) | ai-security-auditor | development context + AI security checklist (prompt injection, training/inference data leakage, model supply chain) |
| QA (Quality) | ai-test-generator | development context + eval/test requirements |
| DV-support (performance) | ai-performance-engineer | inference latency and throughput profiles under `.context/logs/` |
| DV-support (prompts) | ai-prompt-engineer | prompt-tuning scope + eval baselines |
| DV-support (dependencies) | ai-dependency-manager | ML dependency manifests + CVE audit scope |

## security-scanning Plugin

| company-workflow Stage | security-scanning Agent | Handoff Data |
|---------------|------------------------|--------------|
| SR (Security) | security-auditor | code + OWASP checklist |
| SR (Security) | threat-modeling-expert | architecture + threat analysis |

## debugging-toolkit Plugin

| company-workflow Stage | debugging-toolkit Agent | Handoff Data |
|---------------|------------------------|--------------|
| DV (Development) | debugger | error logs, stack traces |
| DV (Development) | dx-optimizer | worktask friction points |
| IR (Incident) | debugger | production logs, RCA context |

## Future Plugin Integration (Not Yet Installed)

The following marketplace plugins are planned but not currently installed. Do NOT invoke these agents until the corresponding plugin is added to the project configuration. `frontend-developer`, `backend-developer`, and `ai-engineer` have graduated out of this table — their stage handoffs are documented above and their registry entries are in `skills/shared/compatible-plugins.md`.

| Plugin | Agent | Use Case |
|--------|-------|----------|
| `code-documentation` | `code-reviewer` | PR code review |
| `application-performance` | `performance-engineer` | Performance analysis |
| `cicd-automation` | `deployment-engineer` | CI/CD automation |
| `accessibility-compliance` | `ui-visual-validator` | WCAG auditing |

## Error Handling

### External Agent Failure

```typescript
IF external_agent_fails:
  1. Log failure: "Agent {name} failed: {error}"
  2. IF critical_task:
       Retry with same context (max 3 attempts)
       IF still_fails:
         TaskUpdate({ taskId, status: "pending" })  // Reset for manual handling
         Create blocker task
     ELSE:
       Mark partial completion
       Document what was achieved
  3. Include failure in handoff:
     PARTIAL_FAILURES:
     - Agent: {name}, Error: {error}, Impact: {impact}
```

#### Child tool restrictions

> **Child tool restrictions**: when handing off to an external-plugin agent, a `disallowedTools` entry may use MCP **server-level** specs (`mcp__server`, `mcp__*`) and is honored on the child — deny a whole MCP server in one rule instead of enumerating tools. `WebSearch` works in subagents, so a delegated agent can rely on it. Auth-capable MCP servers do not leak auth-stub tools to headless / SDK children. See `skills/agent-coordination/references/headless-dispatch.md`.

### Context Overflow

If handoff exceeds token budget:
1. Compress P2/P3 items
2. Reference full output via file path
3. Include only critical items inline

## Model Configuration

> Agent frontmatter accepts full model IDs (e.g., `claude-opus-5`) in addition to aliases (`opus`). Cross-plugin handoffs can specify exact model versions when precision matters for provider-specific behavior.

> The Agent tool `resume` parameter is removed. Use `SendMessage` to communicate with running background agents. `SendMessage` auto-resumes stopped agents in the background.
