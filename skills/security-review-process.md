---
name: security-review-process
description: OWASP Top 10 security review checklist and secure coding patterns for SR stage. (user)
---

# Security Review Process

Comprehensive security review checklist for the SR (Security Review) stage.

## OWASP Top 10 Checklist (2021)

### A01: Broken Access Control

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

### A02: Cryptographic Failures

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

### A03: Injection

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

### A04: Insecure Design

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

### A05: Security Misconfiguration

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

### A06: Vulnerable Components

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

### A07: Authentication Failures

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

### A08: Data Integrity Failures

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

### A09: Logging Failures

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

### A10: SSRF (Server-Side Request Forgery)

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

## Secrets Detection Patterns

### Common Secrets to Find

| Pattern | Regex Example | Severity |
|---------|---------------|----------|
| AWS Keys | `AKIA[0-9A-Z]{16}` | Critical |
| Private Keys | `-----BEGIN.*PRIVATE KEY-----` | Critical |
| JWT Secrets | `eyJ[A-Za-z0-9-_=]+\.eyJ` | High |
| API Keys | `[a-zA-Z0-9_-]{32,45}` in config | High |
| Passwords | `password\s*=\s*['"][^'"]+['"]` | Critical |
| Database URLs | `(mysql\|postgres\|mongodb):\/\/[^@]+@` | Critical |

### Where to Check

- Source code files
- Configuration files (.env, config.json)
- Docker files and compose
- CI/CD configurations
- Documentation (accidental exposure)
- Test fixtures

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

## Security Review Output Template

```markdown
## Security Review: [Feature/PR Name]

### Review Scope
- Files reviewed: [count]
- Lines of code: [count]
- Security-sensitive areas: [list]

### OWASP Compliance
| Category | Status | Notes |
|----------|--------|-------|
| A01 Access Control | ✅/⚠️/❌ | |
| A02 Cryptography | ✅/⚠️/❌ | |
| A03 Injection | ✅/⚠️/❌ | |
| ... | | |

### Findings

#### Critical
- [ ] [Finding]: [Description] → [Remediation]

#### High
- [ ] [Finding]: [Description] → [Remediation]

#### Medium
- [ ] [Finding]: [Description] → [Remediation]

### Secrets Scan
- [ ] No hardcoded secrets found
- [ ] API keys properly externalized
- [ ] Credentials use secure storage

### Recommendations
1. [Recommendation]
2. [Recommendation]

### Sign-off
- Reviewer: [name]
- Date: [date]
- Status: [Approved/Blocked/Conditional]
```

## Integration Points

- **security-reviewer agent**: Uses this checklist for SR stage
- **technical-lead**: Consults for implementation security
- **qa-engineer**: Uses for security testing
- **security-scanning plugin**: Deep vulnerability analysis
