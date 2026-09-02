---
name: security-review-process
description: Use when conducting security reviews, auditing dependencies for vulnerabilities or supply-chain risk, or applying secure coding patterns. OWASP Top 10 security review checklist, dependency supply-chain triage, secure coding patterns for SR stage.
effort: medium
---

# Security Review Process

Security review checklist for the SR (Security Review) stage.

| Reference | Read for |
|-----------|----------|
| `${CLAUDE_SKILL_DIR}/references/threat-model.md` | SR0 procedure — trust boundaries, attack surface, STRIDE |
| `${CLAUDE_SKILL_DIR}/references/owasp-checklist.md` | SR1 — the full OWASP Top 10 checklist (A01–A10) |
| `${CLAUDE_SKILL_DIR}/references/review-template.md` | Standalone security-review output template |

## Secrets Scanner (canonical tool)

**Invocation contract** (one line):
```
bash scripts/scan-secrets.sh --path <repo-root>
```

Output: `file:line:severity:pattern` — one finding per line, no surrounding code excerpt.
Exit 0 = no Critical/High findings. Exit 1 = one or more Critical/High findings (triage required). Exit 2 = usage error.

**This is a first-pass FILTER feeding model triage, not an authoritative finding.**
False positives are expected; the model must verify each line before acting.

Optional flags: `--format json` (newline-delimited JSON objects), `--self-test` (built-in
fixture tests; no network, no external deps).

**Engine selection**: prefers `gitleaks detect --no-git` when `gitleaks` is on `PATH`, else the six built-in ERE/grep regexes below. The gitleaks path maps RuleID → severity heuristically; the regex fallback maps directly.

### Secrets Detection Patterns (spec — implemented in scan-secrets.sh)

Authoritative spec. In the happy path invoke the script rather than reasoning through the regexes.

| Pattern | Regex Example | Severity |
|---------|---------------|----------|
| AWS Keys | `AKIA[0-9A-Z]{16}` | Critical |
| Private Keys | `-----BEGIN [A-Z ]*PRIVATE KEY-----` | Critical |
| JWT Secrets | `eyJ[A-Za-z0-9_-]{10,}\.[Ee][Yy][Jj]` | High |
| API Keys | `[Aa][Pp][Ii][_-]?[Kk][Ee][Yy]\s*=\s*[A-Za-z0-9_-]{32,45}` in config | High |
| Passwords | `password[[:space:]]*=[[:space:]]*['"][^'"]{3,}['"]` | Critical |
| Database URLs | `(mysql\|postgres\|mongodb)://[^@[:space:]]{3,}@` | Critical |

### Where to Check

Scanned automatically by the script: source files (`*.swift *.go *.py *.js *.ts …`), config files (`.env`, `*.json`, `*.yaml`, `*.toml`, `*.ini`, `*.conf`), Docker files, CI/CD configs (`Jenkinsfile`, `.travis.yml`, `*.gitlab-ci.yml`), shell scripts.

Still check manually: documentation (accidental exposure), binary assets, and file types outside the glob list.

## Secure Coding Patterns

| Pattern | Rule |
|---------|------|
| Input validation | Validate at the trust boundary before use: length bound, allowlisted character set, then sanitize — reject (throw) rather than coerce |
| Authentication | Credentials go to the platform secret store, never `UserDefaults`/plain files; check the store's status code and fail closed |
| Authorization | Re-check resource ownership server-side on every access (`owner == caller \|\| caller.isAdmin`), never trust a client-supplied identity |

### Canonical example

Keychain credential storage — the shape all three rules follow (guard, throw on failure, no
silent fallback):

```swift
func storeCredential(_ credential: String, for account: String) throws {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrAccount as String: account,
        kSecValueData as String: Data(credential.utf8)
    ]
    guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else {
        throw KeychainError.unableToStore
    }
}
```

## DevSecOps Pipeline Integration

### Shift-Left Security Checklist

| Phase | Security Activity | Tools |
|-------|-------------------|-------|
| Code | SAST scanning, secrets detection | Semgrep, CodeQL, `scripts/scan-secrets.sh` (wraps gitleaks or built-in regex) |
| Build | Dependency scanning, SBOM generation | Snyk, OWASP Dependency-Check |
| Container | Image scanning, runtime policies | Trivy, Aqua, Docker Scout |
| Deploy | Config validation, IaC scanning | Checkov, tfsec |
| Runtime | DAST scanning, monitoring | OWASP ZAP, runtime protection |

### Supply Chain Security

A dependency audit reports **known advisories only** — never proof that a package is
trustworthy or that the vulnerable code is reachable. Run the platform's native audit
against the committed lockfile (SwiftPM: `Package.resolved` scanned via GitHub/Dependabot or
`swift package` tooling; npm projects: `npm audit`), then triage. A clean audit is not a safe
dependency.

The checkbox set — lockfile discipline, reachability triage, no forced remediation, build-script
blocking, provenance verification, typosquatting, SBOM, licenses — is
`references/owasp-checklist.md § A06`; run it there rather than a second copy. Apple-specific
addition: SwiftPM build-tool / prebuild plugins execute arbitrary code during the build, so vet
plugin sources and pinned versions before enabling them.

### Cloud Security Posture

| Domain | Checks |
|--------|--------|
| IAM | Least privilege, no wildcard permissions, MFA enforced |
| Network | Security groups locked down, no public access to internals |
| Data | Encryption at rest/in transit, key rotation configured |
| Logging | Audit trails enabled, log integrity protected |
| Secrets | No plaintext secrets, rotation policies in place |

### Claude Code sandbox settings

Hardening for the agent's own execution surface — review when a worktask runs unattended (`/megatask`, `--auto=[finalization]`) or on a shared runner.

| Setting | Effect |
|---------|--------|
| `sandbox.network.strictAllowlist` | Denies non-allowlisted hosts for sandboxed commands **without prompting**, rather than asking. Prefer for unattended batches — a prompt in an unattended run is an indefinite stall |
| `sandbox.filesystem.disabled` | Skips filesystem isolation while **keeping** network egress control. Narrow escape hatch; document the justification, never set it to silence a failing command |

#### Sandbox settings — the restricted posture

| Setting | Effect |
|---------|--------|
| `--restricted` / `CLAUDE_CODE_RESTRICTED=1` | Removes the built-in tools that run commands or code plus `WebFetch` (unless named in `--tools`), keeps file tools inside the working directory, refuses `bypassPermissions`, and **ignores user, project and local settings files**. The strongest available posture for running untrusted or third-party plugin content; too restrictive for a normal worktask, since no stage could build or test |

### Claude Code path & config hardening

| Behavior | Effect |
|----------|--------|
| Symlink hardening | Workflow saves and scheduled-task writes no longer follow a symlink at `.claude`, and `/rewind` no longer restores or deletes through symlinks or hard links at tracked paths (it reports how many paths it skipped). A repo with a symlinked `.claude` no longer redirects writes outside the project |
| Managed MCP allowlist `${VAR}` | Resolves from the **startup environment** and managed-settings env — not the settings-file env. A settings-file variable will not expand there |

#### Path & config hardening — 2.1.234→2.1.251

| Behavior | Effect |
|----------|--------|
| TOCTOU on file tools | Read/Write/Edit no longer follow a symlink swapped inside the working directory *after* the permission check, which could read or write outside the approved location. Grep and Glob now apply `Read(...)` deny rules to files reached through a symlinked search path, and the Workflow tool no longer reads (or quotes in errors) a `scriptPath` outside what the session may read. Closes the check-then-use window the plugin's own scripts already guard by resolving through a `readlink` loop |

#### Path & config hardening — marketplace paths

| Behavior | Effect |
|----------|--------|
| Marketplace command path traversal | Plugin commands declared in a marketplace entry can no longer point outside the plugin directory; such paths are rejected as path traversal. **Directly relevant here** — this repo is both a marketplace and the plugin it publishes. Verified this band: every `commands[]`, `agents[]` and `skills[]` entry in `.claude-plugin/marketplace.json` is `./`-relative, with no `../`, absolute path, or external URL |

#### Path & config hardening — settings scope

| Behavior | Effect |
|----------|--------|
| Project settings cannot widen tracing | Project settings can no longer enable detailed beta tracing or raw API body logging, nor bypass an OTLP collector pinned by managed settings. Project `.claude/settings.json` `env` no longer sets `CLAUDE_CONFIG_DIR`, `CLAUDE_CODE_TMPDIR`, or `TMPDIR`/`TMP`/`TEMP` — a hostile repo can no longer redirect config or scratch state by shipping a settings file |
| Bash arithmetic auto-approve | Permission checks no longer auto-approve a command assigning an arithmetic expression to an integer shell variable (`OPTIND=1/0`, `RANDOM=2+2`); these now prompt |

## Integration Points

`agents/security-reviewer.md` runs this checklist at the SR stage; `agents/technical-lead.md`
consults it for implementation security, `agents/qa-engineer.md` for security testing, and the
`security-scanning` plugin for deep vulnerability analysis.
