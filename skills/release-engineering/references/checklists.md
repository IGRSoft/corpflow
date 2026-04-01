# Deployment Readiness Checklists

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
