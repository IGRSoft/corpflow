---
name: release-engineering
description: Semantic versioning, changelog generation, and deployment readiness patterns for RE stage. (user)
---

# Release Engineering

Guidelines for version management, changelog generation, and deployment readiness.

## Semantic Versioning (SemVer)

### Version Format

```
MAJOR.MINOR.PATCH[-PRERELEASE][+BUILD]

Examples:
1.0.0
2.1.3
3.0.0-alpha.1
1.2.3-beta.2+build.456
```

### Version Bump Rules

| Change Type | Bump | Before | After |
|-------------|------|--------|-------|
| Breaking API change | MAJOR | 1.2.3 | 2.0.0 |
| New feature (compatible) | MINOR | 1.2.3 | 1.3.0 |
| Bug fix (compatible) | PATCH | 1.2.3 | 1.2.4 |
| Pre-release | Suffix | 2.0.0 | 2.0.0-alpha.1 |

### Breaking Change Detection

A change is BREAKING if it:
- Removes a public API
- Changes return type of public method
- Adds required parameter to public method
- Changes behavior that clients depend on
- Removes or renames configuration options
- Changes database schema incompatibly

### Pre-release Labels

| Label | Use Case |
|-------|----------|
| `-alpha.N` | Internal testing, unstable |
| `-beta.N` | External testing, feature complete |
| `-rc.N` | Release candidate, production ready |

## Conventional Commits

### Format

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

### Types and Changelog Mapping

| Type | Description | Changelog | Bump |
|------|-------------|-----------|------|
| `feat` | New feature | Added | MINOR |
| `fix` | Bug fix | Fixed | PATCH |
| `docs` | Documentation | - | - |
| `style` | Formatting | - | - |
| `refactor` | Code change | Changed | PATCH |
| `perf` | Performance | Changed | PATCH |
| `test` | Tests | - | - |
| `chore` | Maintenance | - | - |
| `ci` | CI/CD | - | - |
| `build` | Build system | - | - |

### Breaking Changes

```
feat!: remove deprecated login endpoint

BREAKING CHANGE: The /api/v1/login endpoint has been removed.
Use /api/v2/auth instead.
```

## Changelog Generation

### Keep a Changelog Format

```markdown
# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [1.2.0] - 2024-01-15

### Added
- New user dashboard with analytics (#123)
- Dark mode support (#145)

### Changed
- Updated login flow for better security (#156)
- Improved error messages (#167)

### Deprecated
- Legacy API endpoints (removed in 2.0.0)

### Removed
- Support for iOS 14 (#178)

### Fixed
- Crash on large file uploads (#189)
- Memory leak in image processing (#190)

### Security
- Fixed XSS vulnerability in comments (#200)

## [1.1.0] - 2024-01-01
...
```

### Commit to Changelog Mapping

```bash
# Parse commits since last tag
git log v1.1.0..HEAD --pretty=format:"%s" | while read commit; do
  case "$commit" in
    feat:*) echo "### Added\n- ${commit#feat: }" ;;
    fix:*)  echo "### Fixed\n- ${commit#fix: }" ;;
    # ... etc
  esac
done
```

## Deployment Readiness Checklist

### Code Quality

```markdown
- [ ] All CI checks passing
- [ ] Code coverage ≥ threshold (e.g., 80%)
- [ ] No critical static analysis warnings
- [ ] Technical debt within budget
- [ ] All TODOs addressed or tracked
```

### Testing

```markdown
- [ ] Unit tests passing
- [ ] Integration tests passing
- [ ] E2E tests passing
- [ ] Performance benchmarks acceptable
- [ ] Security tests passing
- [ ] Accessibility tests passing
```

### Documentation

```markdown
- [ ] API documentation updated
- [ ] README current
- [ ] CHANGELOG updated
- [ ] Migration guide (if breaking)
- [ ] Release notes drafted
```

### Infrastructure

```markdown
- [ ] Database migrations tested
- [ ] Environment variables documented
- [ ] Secrets configured
- [ ] Monitoring configured
- [ ] Alerting configured
- [ ] Logging configured
```

### Compliance

```markdown
- [ ] Security review complete (SR stage)
- [ ] Privacy review complete
- [ ] Legal review (if required)
- [ ] Accessibility audit passed
```

## Rollback Plan Template

```markdown
## Rollback Plan: v[X.Y.Z]

### Prerequisites
- [ ] Previous version artifacts available
- [ ] Database rollback scripts tested
- [ ] Feature flags identified

### Trigger Conditions
Initiate rollback if:
- Error rate > [threshold]%
- Latency P99 > [threshold]ms
- Critical functionality broken
- Data integrity issues detected

### Rollback Steps

1. **Notify stakeholders**
   - Inform on-call and team leads
   - Update status page

2. **Stop new deployment**
   - Halt any in-progress rollout
   - Remove from deployment queue

3. **Revert application**
   ```bash
   # Example commands
   kubectl rollout undo deployment/app
   # or
   git revert HEAD && git push
   ```

4. **Revert database** (if applicable)
   ```sql
   -- Run rollback migration
   -- Verify data integrity
   ```

5. **Verify rollback**
   - Check error rates
   - Verify functionality
   - Monitor for 30 minutes

6. **Post-rollback**
   - Document incident
   - Schedule post-mortem
   - Plan fix for next release

### Data Considerations
- [Describe any data migration impacts]
- [Describe data recovery steps if needed]

### Communication
- [ ] Internal: [channel]
- [ ] External: [status page]
- [ ] Customers: [if applicable]
```

## Platform-Specific Checklists

### iOS App Store

```markdown
## App Store Release Checklist

### App Store Connect
- [ ] Version number updated in Xcode
- [ ] Build number incremented
- [ ] App Store Connect profile selected

### Metadata
- [ ] Screenshots current (all device sizes)
- [ ] App preview videos updated
- [ ] What's New text written
- [ ] Description updated (if needed)
- [ ] Keywords optimized

### Compliance
- [ ] Export compliance answered
- [ ] Content rights confirmed
- [ ] Age rating accurate
- [ ] Privacy policy URL valid
- [ ] App privacy details current

### Submission
- [ ] Archive built and validated
- [ ] Uploaded to App Store Connect
- [ ] TestFlight testing complete
- [ ] Submit for review
```

### Android Play Store

```markdown
## Play Store Release Checklist

### Build
- [ ] Version code incremented
- [ ] Version name updated
- [ ] Signed release build generated
- [ ] ProGuard/R8 mapping saved

### Play Console
- [ ] Release notes written
- [ ] Screenshots current
- [ ] Feature graphic updated
- [ ] Store listing current

### Compliance
- [ ] Content rating questionnaire current
- [ ] Data safety form accurate
- [ ] Target API level compliant (API 34+)
- [ ] Permissions justified

### Rollout
- [ ] Internal testing complete
- [ ] Closed testing complete
- [ ] Staged rollout percentage set
- [ ] Monitoring configured
```

## Integration Points

- **release-engineer agent**: Uses these patterns for RE stage
- **project-manager**: Uses release artifacts for deployment
- **apple-developer plugin**: iOS/macOS submission coordination
