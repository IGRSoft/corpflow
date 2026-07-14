# OWASP Top 10 Checklist (2021)

## A01: Broken Access Control

```markdown
- [ ] Deny by default (fail closed)
- [ ] Server-side access control enforcement
- [ ] No CORS misconfigurations
- [ ] No directory traversal via user input
- [ ] Resource ownership verified before access
- [ ] Rate limiting on API and controller access
- [ ] JWT tokens invalidated on logout
- [ ] No privilege escalation paths
```

## A02: Cryptographic Failures

```markdown
- [ ] No sensitive data transmitted in cleartext
- [ ] TLS 1.2+ enforced for all connections
- [ ] Strong encryption algorithms (AES-256, RSA-2048+)
- [ ] Passwords hashed with bcrypt/Argon2 (not MD5/SHA1)
- [ ] Cryptographic keys stored securely
- [ ] No deprecated crypto functions
- [ ] PII encrypted at rest
- [ ] Proper key rotation supported
```

## A03: Injection

```markdown
- [ ] Parameterized queries for all database access
- [ ] Input validation with allowlists
- [ ] Output encoding for context (HTML, JS, URL)
- [ ] No dynamic SQL construction
- [ ] Command injection prevention
- [ ] LDAP injection prevention
- [ ] XML/XPath injection prevention
- [ ] NoSQL injection prevention
```

## A04: Insecure Design

```markdown
- [ ] Threat modeling completed
- [ ] Security requirements defined
- [ ] Secure design patterns used
- [ ] Defense in depth implemented
- [ ] Fail securely (not fail open)
- [ ] Principle of least privilege
- [ ] Separation of duties
- [ ] Input validation at trust boundaries
```

## A05: Security Misconfiguration

```markdown
- [ ] Unnecessary features disabled
- [ ] Default credentials changed
- [ ] Error messages don't expose internals
- [ ] Security headers configured (CSP, HSTS, X-Frame)
- [ ] Cloud storage permissions correct
- [ ] Debug mode disabled in production
- [ ] Directory listing disabled
- [ ] Software up to date
```

## A06: Vulnerable & Outdated Components

Audits find **known advisories**; they do not prove trustworthiness or reachability.
Triage findings against the paths that actually execute rather than treating any hit as a
blocker. State commands package-manager-agnostically — the SwiftPM `Package.resolved`
lockfile is the local analog (`npm audit`/`npm ci` are npm-project examples, not the sole
directive).

### Checklist

```markdown
- [ ] Dependency versions current
- [ ] No known CVEs in dependencies
- [ ] Components from trusted sources
- [ ] Unused dependencies removed
- [ ] License compliance verified
- [ ] Automated vulnerability scanning enabled
- [ ] Update process documented
- [ ] SBOM (Software Bill of Materials) maintained
- [ ] Exactly one authoritative lockfile per installation boundary (SwiftPM: Package.resolved), committed and never rewritten by CI
- [ ] Critical/high advisories triaged for reachability (runtime, build, test, deploy) — deferrals carry a reason and review date
- [ ] Forced audit remediation is never automatic; remediation diffs and changelogs are reviewed
- [ ] Dependency lifecycle / build-tool scripts blocked before first execution, approved narrowly
- [ ] Registry signatures / provenance verified where the ecosystem supports it
```

## A07: Authentication Failures

```markdown
- [ ] Multi-factor authentication available
- [ ] Strong password policy enforced
- [ ] Brute force protection (rate limiting, lockout)
- [ ] Secure session management
- [ ] Session timeout implemented
- [ ] Secure password recovery process
- [ ] Credential stuffing protection
- [ ] No default/weak credentials
```

## A08: Data Integrity Failures

```markdown
- [ ] Code and data integrity verified
- [ ] Digital signatures validated
- [ ] CI/CD pipeline secured
- [ ] Deserialization secured
- [ ] Updates verified before install
- [ ] No unsigned/unverified plugins
- [ ] Supply chain security considered
- [ ] Integrity checks on critical data
```

## A09: Logging Failures

```markdown
- [ ] Authentication events logged
- [ ] Authorization failures logged
- [ ] Input validation failures logged
- [ ] No sensitive data in logs
- [ ] Logs protected from tampering
- [ ] Log aggregation configured
- [ ] Alerting for security events
- [ ] Log retention policy defined
```

## A10: SSRF (Server-Side Request Forgery)

```markdown
- [ ] URL validation on user input
- [ ] No internal network access via user URLs
- [ ] Allowlist for external services
- [ ] DNS rebinding protection
- [ ] No raw HTTP responses exposed
- [ ] Network segmentation in place
- [ ] Metadata endpoints blocked
- [ ] URL schema restricted (no file://, etc.)
```
