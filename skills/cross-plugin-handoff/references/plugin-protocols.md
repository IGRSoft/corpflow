# Plugin-Specific Protocols

## apple-developer Plugin

| igrsoft Stage | apple-developer Agent | Handoff Data |
|---------------|----------------------|--------------|
| AR (Architecture) | apple-architector | planning context + system constraints |
| DV (Development) | ios-developer, macos-developer, etc. | planning + architecture context |
| SR (Security) | security-auditor | development context + Apple security checklist (Keychain, ATS, entitlements, TCC, privacy manifest) |
| QA (Quality) | test-generator | development context + test requirements |
| DC (Documentation) | generate-dooc (command) | development context + API surface |
| RE (Release) | ios-developer, macos-developer | App Store/TestFlight submission data, notarization |
| IR (Incident) | All platform agents | incident context + hotfix constraints (no App Store rollback) |

## system-developer Plugin

### system-developer — core stage handoffs

| igrsoft Stage | system-developer Agent | Handoff Data |
|---------------|------------------------|--------------|
| AR (Architecture) | system-architector | planning context + system constraints (consultation model, like apple-architector) |
| DV (Development) | system-developer (router), c-developer, cpp-developer, python-developer, bash-developer | planning + architecture context; `requires_screenshots: false` for CLI work (Build Evidence = terminal transcripts) |
| DR (Developer Review) | sys-code-fixer | gate blockers (`metadata.gate_blockers[]`) + minimal-diff remediation |

### system-developer — review, support & incident handoffs

| igrsoft Stage | system-developer Agent | Handoff Data |
|---------------|------------------------|--------------|
| SR (Security) | sys-security-auditor | development context + systems security checklist (sanitizers, CWE Top 25, injection, hardening flags) |
| QA (Quality) | sys-test-generator | development context + test requirements; QA gate includes ASan+UBSan clean on changed components |
| DV-support (performance) | sys-performance-engineer | profiling artifacts under `.context/logs/profile-*/` |
| DV-support (dependencies) | sys-dependency-manager | manifest paths (vcpkg.json, conanfile, pyproject.toml + uv.lock) + CVE audit scope |
| IR (Incident) | All language agents | incident context + hotfix constraints |

## android-developer Plugin

### android-developer — architecture & development handoffs

| igrsoft Stage | android-developer Agent | Handoff Data |
|---------------|-------------------------|--------------|
| AR (Architecture) | kotlin-architector | planning context + Android architecture constraints (Clean Architecture, modularization, Hilt DI — consultation model, like apple-architector) |
| DV (Development) | android-developer (router), android-phone-developer | planning + architecture context; `requires_screenshots: true` (Build Evidence = `adb exec-out screencap -p` via `android_adapter` + Gradle build/test transcripts); no Android build MCP — scoped `Bash(gradle:*\|./gradlew\|adb:*)` |

### android-developer — review, QA & dependency handoffs

| igrsoft Stage | android-developer Agent | Handoff Data |
|---------------|-------------------------|--------------|
| DR (Developer Review) | code-fixer | gate blockers (`metadata.gate_blockers[]`) + ktlint/detekt minimal-diff remediation |
| SR (Security) | security-auditor | development context + Android security checklist (EncryptedSharedPreferences/Keystore, no-cleartext, exported-component validation, no hardcoded secrets) |
| QA (Quality) | test-generator | development context + test requirements; JUnit4/5, MockK, Turbine, Roborazzi screenshot tests |
| DV-support (dependencies) | dependency-manager | version catalog (`libs.versions.toml`) + Gradle dependency CVE audit scope |

## security-scanning Plugin

| igrsoft Stage | security-scanning Agent | Handoff Data |
|---------------|------------------------|--------------|
| SR (Security) | security-auditor | code + OWASP checklist |
| SR (Security) | threat-modeling-expert | architecture + threat analysis |

## debugging-toolkit Plugin

| igrsoft Stage | debugging-toolkit Agent | Handoff Data |
|---------------|------------------------|--------------|
| DV (Development) | debugger | error logs, stack traces |
| DV (Development) | dx-optimizer | worktask friction points |
| IR (Incident) | debugger | production logs, RCA context |

## Future Plugin Integration (Not Yet Installed)

The following marketplace plugins are planned but not currently installed. Do NOT invoke these agents until the corresponding plugin is added to the project configuration.

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

> Agent frontmatter accepts full model IDs (e.g., `claude-opus-4-5`) in addition to aliases (`opus`). Cross-plugin handoffs can specify exact model versions when precision matters for provider-specific behavior.

> The Agent tool `resume` parameter is removed. Use `SendMessage` to communicate with running background agents. `SendMessage` auto-resumes stopped agents in the background.
