---
name: security-review-process
description: OWASP Top 10 security review checklist, dependency supply-chain triage, and secure coding patterns for SR stage. Use when conducting security reviews, auditing dependencies for vulnerabilities or supply-chain risk, or applying secure coding patterns.
effort: medium
---

# Security Review Process

Comprehensive security review checklist for the SR (Security Review) stage.

For the full OWASP Top 10 checklist, see `${CLAUDE_SKILL_DIR}/references/owasp-checklist.md`

For the security review output template, see `${CLAUDE_SKILL_DIR}/references/review-template.md`

For the SR0 threat-modeling procedure (trust boundaries, attack surface, STRIDE), see
`${CLAUDE_SKILL_DIR}/references/threat-model.md`

## Secrets Scanner (canonical tool)

**Script**: `scripts/scan-secrets.sh`

**Invocation contract** (one line):
```
bash scripts/scan-secrets.sh --path <repo-root>
```

Output: `file:line:severity:pattern` — one finding per line, no surrounding code excerpt.
Exit 0 = no Critical/High findings. Exit 1 = one or more Critical/High findings (triage required). Exit 2 = usage error.

**This is a first-pass FILTER feeding model triage, not an authoritative finding.**
False positives are expected; the model must verify each line before acting.

Optional flags:
- `--format json` — emit newline-delimited JSON objects instead
- `--self-test`   — run built-in fixture tests (no network, no external deps)

**Engine selection**: prefers `gitleaks detect --no-git` when `gitleaks` is on `PATH`; otherwise falls back to the six built-in regexes below (ERE, grep-based). The gitleaks path maps RuleID → severity heuristically; the regex fallback maps directly.

### Secrets Detection Patterns (spec — implemented in scan-secrets.sh)

The table below is the authoritative specification. In the happy path, invoke the script instead of reasoning through these regexes manually.

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

Manual check still warranted for: documentation (accidental exposure), binary assets, and any file type not in the glob list.

## Secure Coding Patterns

### Input Validation

```swift
// Swift - Good
func processInput(_ input: String) throws -> ProcessedData {
    guard input.count <= maxLength else {
        throw ValidationError.tooLong
    }
    guard allowedCharacters.isSuperset(of: CharacterSet(charactersIn: input)) else {
        throw ValidationError.invalidCharacters
    }
    return sanitize(input)
}
```

### Authentication

```swift
// Swift - Secure credential storage
import Security

func storeCredential(_ credential: String, for account: String) throws {
    let data = credential.data(using: .utf8)!
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrAccount as String: account,
        kSecValueData as String: data
    ]
    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else {
        throw KeychainError.unableToStore
    }
}
```

### Authorization

```swift
// Swift - Resource ownership check
func getResource(id: String, requestingUser: User) throws -> Resource {
    let resource = try repository.find(id)
    guard resource.ownerId == requestingUser.id || requestingUser.isAdmin else {
        throw AuthorizationError.forbidden
    }
    return resource
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

A dependency audit reports **known advisories only** — it does not prove a package is
trustworthy or that the vulnerable code is reachable. Use the platform's native audit
against the committed lockfile (SwiftPM: resolve `Package.resolved` and scan advisories
via GitHub/Dependabot or `swift package` tooling; e.g. for npm projects, `npm audit`),
then triage the findings — don't equate a clean audit with a safe dependency.

#### Lockfile and Advisory Triage

- [ ] **One authoritative lockfile per installation boundary**, committed and never
  rewritten by CI. For SwiftPM the local analog is `Package.resolved` (one per
  package/workspace root); CI resolves against it rather than re-pinning. Competing or
  duplicate lockfiles at a single boundary is a red flag.
- [ ] **Critical/high advisories triaged for reachability** across runtime, build, test,
  and deployment paths — not merely "present in the graph". Each deferral carries a reason
  and a review date.
- [ ] **Forced audit remediation is never applied automatically** (`npm audit fix --force`
  or any equivalent that crosses declared version ranges). Preview the remediation, read
  the changelog, and let the test suite decide.

##### Provenance & Package Hygiene

- [ ] **Dependency lifecycle / build scripts are attack surface** — block them before first
  execution, inspect the script source and pinned version, and approve only the minimum
  required. Apple analog: SwiftPM build-tool / prebuild plugins execute arbitrary code
  during the build; vet plugin sources before enabling them.
- [ ] **Registry signatures / provenance verified where supported** (SLSA provenance,
  signed releases, `swift package` checksum pins for binary targets). Absence is a signal
  to investigate, not automatic proof of compromise.
- [ ] No typosquatting risk in package names; new dependencies reviewed for ownership,
  maintenance, release age, and transitive graph.
- [ ] SBOM generated for release artifacts.
- [ ] No dependencies with restrictive/incompatible licenses.

### Cloud Security Posture

| Domain | Checks |
|--------|--------|
| IAM | Least privilege, no wildcard permissions, MFA enforced |
| Network | Security groups locked down, no public access to internals |
| Data | Encryption at rest/in transit, key rotation configured |
| Logging | Audit trails enabled, log integrity protected |
| Secrets | No plaintext secrets, rotation policies in place |

### Claude Code sandbox settings

Settings that harden the agent's own execution surface. Review them when a worktask runs unattended (`/megatask`, `--auto=[finalization]`) or on a shared runner.

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

- **security-reviewer agent**: Uses this checklist for SR stage
- **technical-lead**: Consults for implementation security
- **qa-engineer**: Uses for security testing
- **security-scanning plugin**: Deep vulnerability analysis
