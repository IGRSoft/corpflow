---
name: security-review-process
description: Use when conducting a security review, threat-modeling a diff, scanning for secrets, or triaging dependency and supply-chain risk. OWASP Top 10 checklist, STRIDE threat model, secrets scanner, and secure coding patterns for the SR stage.
---

# Security Review Process

Security review checklist for the SR (Security Review) stage.

| Reference | Read for |
|-----------|----------|
| `${CLAUDE_SKILL_DIR}/references/threat-model.md` | SR0 procedure — trust boundaries, attack surface, STRIDE |
| `${CLAUDE_SKILL_DIR}/references/owasp-checklist.md` | SR1 — the full OWASP Top 10 checklist (A01–A10) |
| `${CLAUDE_SKILL_DIR}/references/review-template.md` | Standalone security-review output template |
| `${CLAUDE_SKILL_DIR}/references/claude-code-hardening.md` | Diffs touching Claude Code permission rules, settings, sandbox, or plugin manifests |

## Secrets Scanner (canonical tool)

```
bash ${CLAUDE_PLUGIN_ROOT}/skills/security-review-process/scripts/scan-secrets.sh --path <repo-root>
```

Output: `file:line:severity:pattern` — one finding per line, no surrounding code excerpt.
Exit 0 = no Critical/High findings. Exit 1 = one or more Critical/High findings (triage required). Exit 2 = usage error.

It is a first-pass filter feeding triage, not an authoritative finding: false positives are
expected, so verify each line before acting.

Optional flags: `--format json` (newline-delimited JSON objects), `--self-test` (built-in
fixture tests; no network, no external deps).

Engine: `gitleaks detect --no-git` when `gitleaks` is on `PATH` (RuleID → severity mapped heuristically), else the six built-in regexes below (mapped directly).

### Secrets Detection Patterns (spec — implemented in scan-secrets.sh)

Authoritative spec; invoke the script rather than reasoning through the regexes.

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

## DevSecOps Pipeline Integration

### Shift-Left Security Checklist

| Phase | Security Activity | Tools |
|-------|-------------------|-------|
| Code | SAST scanning, secrets detection | Semgrep, CodeQL, `scripts/scan-secrets.sh` |
| Build | Dependency scanning, SBOM generation | Snyk, OWASP Dependency-Check |
| Container | Image scanning, runtime policies | Trivy, Aqua, Docker Scout |
| Deploy | Config validation, IaC scanning | Checkov, tfsec |
| Runtime | DAST scanning, monitoring | OWASP ZAP, runtime protection |

### Supply Chain Security

Run the platform's native audit against the committed lockfile (SwiftPM: `Package.resolved`
via GitHub/Dependabot or `swift package` tooling; npm: `npm audit`), then triage per
`references/owasp-checklist.md § A06` — a clean audit is not a safe dependency. SwiftPM
build-tool and prebuild plugins execute arbitrary code during the build, so vet plugin sources
and pinned versions before enabling them.

### Cloud Security Posture

| Domain | Checks |
|--------|--------|
| IAM | Least privilege, no wildcard permissions, MFA enforced |
| Network | Security groups locked down, no public access to internals |
| Data | Encryption at rest/in transit, key rotation configured |
| Logging | Audit trails enabled, log integrity protected |
| Secrets | No plaintext secrets, rotation policies in place |
