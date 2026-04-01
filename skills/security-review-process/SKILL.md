---
name: security-review-process
description: OWASP Top 10 security review checklist and secure coding patterns for SR stage. Use when conducting security reviews or applying secure coding patterns.
effort: medium
---

# Security Review Process

Comprehensive security review checklist for the SR (Security Review) stage.

For the full OWASP Top 10 checklist, see `${CLAUDE_SKILL_DIR}/security-review-process/references/owasp-checklist.md`

For the security review output template, see `${CLAUDE_SKILL_DIR}/security-review-process/references/review-template.md`

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

## Integration Points

- **security-reviewer agent**: Uses this checklist for SR stage
- **technical-lead**: Consults for implementation security
- **qa-engineer**: Uses for security testing
- **security-scanning plugin**: Deep vulnerability analysis
