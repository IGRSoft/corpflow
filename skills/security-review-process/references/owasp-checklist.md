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
- [ ] No hardcoded secrets; API keys scoped and rotatable
- [ ] No deprecated crypto functions
- [ ] PII encrypted at rest
- [ ] Proper key rotation supported
```

## A03: Injection

```markdown
- [ ] Parameterized queries for all database access
- [ ] Input validation with allowlists, length limits, and correct character encoding
- [ ] File uploads validated (type, size, content)
- [ ] Output encoding for context (HTML, JS, URL)
- [ ] No dynamic SQL construction
- [ ] Command injection prevention
- [ ] LDAP injection prevention
- [ ] XML/XPath injection prevention
- [ ] NoSQL injection prevention
```

## A04: Insecure Design

Threat modeling is the SR0 procedure in `threat-model.md` — one methodology, not a second
one. The sub-items below are its completion criteria, not a separate method.

```markdown
- [ ] Trust boundaries the diff crosses enumerated (both sides + asset named)
- [ ] Attack surface enumerated per boundary — entry points the diff adds or widens, with the
      origin of each attacker-controlled input
- [ ] Each entry point categorized with STRIDE (severity stays the SR severity table)
- [ ] Every threat carries a `T<n>` ID and every finding cites the threat it realizes
- [ ] Every Critical/High threat answered by a finding or a recorded mitigation + control
- [ ] "No material threat surface" recorded with a reason when the diff crosses nothing
```

### A04 design principles

```markdown
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

Audits find **known advisories**; they prove neither trustworthiness nor reachability.
Triage against the paths that actually execute instead of treating any hit as a blocker.
State commands package-manager-agnostically — SwiftPM's `Package.resolved` is the local
lockfile analog (`npm audit`/`npm ci` are npm-project examples, not the directive).

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
```

### Supply-chain checklist

```markdown
- [ ] Exactly one authoritative lockfile per install boundary (SwiftPM: Package.resolved), committed, never rewritten by CI
- [ ] Critical/high advisories triaged for reachability (runtime, build, test, deploy) — deferrals carry a reason and review date
- [ ] Forced audit remediation is never automatic; remediation diffs and changelogs are reviewed
- [ ] Dependency lifecycle / build-tool scripts blocked before first execution, approved narrowly
- [ ] Registry signatures / provenance verified where the ecosystem supports it
- [ ] No typosquatting risk in package names; new dependencies reviewed for ownership, maintenance, release age, and transitive graph
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
