---
name: security-review-process
description: OWASP Top 10 security review checklist, dependency supply-chain triage, and secure coding patterns for SR stage. Use when conducting security reviews, auditing dependencies for vulnerabilities or supply-chain risk, or applying secure coding patterns.
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

### Claude Code path & config hardening

| Behavior | Effect |
|----------|--------|
| Symlink hardening | Workflow saves and scheduled-task writes no longer follow a symlink at `.claude`, and `/rewind` no longer restores or deletes through symlinks or hard links at tracked paths (it reports how many paths it skipped). A repo with a symlinked `.claude` no longer redirects writes outside the project |
| Managed MCP allowlist `${VAR}` | Resolves from the **startup environment** and managed-settings env — not the settings-file env. A settings-file variable will not expand there |

## Integration Points

`agents/security-reviewer.md` runs this checklist at the SR stage; `agents/technical-lead.md`
consults it for implementation security, `agents/qa-engineer.md` for security testing, and the
`security-scanning` plugin for deep vulnerability analysis.
