# Security Review Output Template

Standalone reviews only. The SR-stage artifact `.context/security-review-N.md` uses the
four mandatory kebab H2 anchors instead (`agents/security-reviewer.md § Output Artifact`);
anchor-lint rejects the headings below. Threat-model procedure: `threat-model.md`.

```markdown
## Security Review: [Feature/PR Name]

### Review Scope
- Files reviewed: [count]
- Lines of code: [count]
- Security-sensitive areas: [list]

### Threat Model

One row per threat, columns per `threat-model.md § Output shape`; or the single line
`No material threat surface: [why nothing crosses a boundary].`

```

## Compliance and findings

```markdown
### OWASP Compliance
| Category | Status | Notes |
|----------|--------|-------|
| A01 Access Control | ✅/⚠️/❌ | |
| A02 Cryptography | ✅/⚠️/❌ | |
| A03 Injection | ✅/⚠️/❌ | |
| ... | | |

### Findings

Each finding opens with the threat it realizes; `[—]` marks one with no threat-model row yet.

#### Critical
- [ ] **[T1]** [Finding]: [Description] → [Remediation]

#### High
- [ ] **[T2]** [Finding]: [Description] → [Remediation]

#### Medium
- [ ] **[—]** [Finding]: [Description] → [Remediation]

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
