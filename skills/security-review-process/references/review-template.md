# Security Review Output Template

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
