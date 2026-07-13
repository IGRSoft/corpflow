---
name: senior-developer-review
description: Technical review framework for estimates by platform specialists. Use when conducting senior-level code or estimate reviews.
effort: low
---

# Senior Developer Review Guidelines

Technical review of estimates by platform specialists.

## When to Apply

- Projects with complexity score >= 15
- AR/ML/Vision framework integration
- BLE/Hardware SDK integration
- Real-time camera processing
- Third-party SDK integration (unknown quality)
- Background processing requirements

## Adjustment Matrix

| Category | Trigger | Min Increase | Max Increase |
|----------|---------|-------------|-------------|
| AR/Camera SDKs | Metal, AVFoundation, face tracking | +3 SP | +5 SP |
| API Integration | Image processing, async handling | +1 SP | +2 SP |
| BLE/Hardware | State machines, background modes | +2 SP | +3 SP |
| Vision Framework | Face detection, landmarks | +2 SP | +3 SP |
| Offline Sync | Conflict resolution, Core Data | +2 SP | +3 SP |
| Third-party SDKs | Unknown documentation quality | +15% buffer | +20% buffer |

## Platform-Specific Adjustments

### iOS/SwiftUI
| Feature | Min Adjustment | Max Adjustment |
|---------|---------------|---------------|
| Metal rendering | +3 SP | +5 SP |
| ARKit integration | +5 SP | +8 SP |
| CoreBluetooth state machine | +3 SP | +5 SP |
| Vision face detection | +2 SP | +3 SP |
| App Store review prep | +2 SP | +3 SP |
| Background app refresh | +1 SP | +2 SP |
| Push notifications | +1 SP | +2 SP |
| Deep linking | +1 SP | +2 SP |

### Android/Kotlin
| Feature | Min Adjustment | Max Adjustment |
|---------|---------------|---------------|
| NDK/JNI integration | +3 SP | +5 SP |
| BLE background services | +3 SP | +5 SP |
| Camera2 API | +2 SP | +3 SP |
| Play Store compliance | +1 SP | +2 SP |
| WorkManager setup | +1 SP | +2 SP |

### Web/React
| Feature | Min Adjustment | Max Adjustment |
|---------|---------------|---------------|
| WebGL rendering | +3 SP | +5 SP |
| WebRTC integration | +3 SP | +5 SP |
| Service workers | +2 SP | +3 SP |
| IndexedDB sync | +2 SP | +3 SP |

## Review Process

1. **Read estimation artifacts**
   - features_breakdown.csv
   - complexity_analysis.csv
   - integration_specifics.csv

2. **Identify adjustment triggers**
   - Check each feature against matrix
   - Note platform-specific concerns

3. **Apply adjustments**
   - Update SP Min and SP Max for affected features
   - Recalculate hours (Hours Min = SP Min × 6h, Hours Max = SP Max × 6h)
   - Add buffer for unknowns (applied to both Min and Max)

4. **Document changes**
   - Original vs adjusted Min/Max values
   - Rationale for each adjustment
   - Risk flags identified

5. **Update totals**
   - Recalculate phase summary (Min and Max independently)
   - Update budget range
   - Adjust timeline range if needed

## Review Checklist

Before finalizing estimates, verify:

- [ ] All SDK integrations identified
- [ ] Background mode requirements assessed
- [ ] Permissions flow complexity included
- [ ] Error handling for network failures
- [ ] Offline mode if required
- [ ] Analytics integration
- [ ] Deep linking if required
- [ ] Push notification handling
- [ ] App Store/Play Store requirements
- [ ] Localization requirements
- [ ] Accessibility requirements

## Risk Flags

Watch for these during review:

| Flag | Action |
|------|--------|
| Third-party SDK without iOS 18+ support | Add contingency phase |
| Bluetooth background requirements | Test on real devices early |
| AR face tracking | Check App Store guidelines |
| Health/financial data | Security audit required |
| Real-time sync | Load testing required |

## Output Format

```markdown
## Senior Developer Review: [Project]

### Adjustment Summary
| Category | Original (Min-Max) | Adjusted (Min-Max) | Delta | Reason |
|----------|--------------------|--------------------|-------|--------|
| [Feature] | [Size] (Min-Max) | [New Size] (Min-Max) | +X-Y SP | [Reason] |

### Total Impact
- Original SP: X Min - Y Max
- Adjusted SP: X' Min - Y' Max
- Delta: +Z-W SP (+N-M%)
- Hours Impact: +Nh Min - +Mh Max

### Risk Flags
1. [Risk 1]
2. [Risk 2]

### Recommendations
1. [Action 1]
2. [Action 2]
```

## Dependency Upgrade Review

Upgrading an existing dependency is a code change, and the riskiest upgrades are the ones
merged in bulk as "bump deps." When a review request touches a manifest (`Package.swift`,
`Podfile`, `*.gradle`, `requirements.txt`, `package.json`, …) or its lockfile, apply the
same senior discipline you'd apply to feature code:

1. **Read the changelog, not just the version number.** Semver is a promise the maintainer
   may not have kept; a "patch" can carry a behavioral change. For a major bump, read the
   migration notes and find what breaks.
2. **One dependency per change.** Upgrade and merge individually (or in small related
   groups). A bulk bump that breaks the build hides which package did it; single-package
   changes keep the cause obvious and the revert clean.
3. **Let the suite decide.** The upgrade is verified by a green test suite before *and*
   after, not by "it resolved." Thin coverage around the dependency's behavior is itself
   the finding — add a test first.
4. **Mind the transitive graph.** Most resolved packages are ones nobody chose directly.
   Review the lockfile / transitive-graph diff, not just the manifest — one direct bump can
   pull in dozens of indirect changes.
5. **Keep the lockfile honest.** Commit it, review its diff, and never hand-edit it; the
   lockfile (SwiftPM `Package.resolved` and equivalents) is what actually pins what ships.

For advisory triage and supply-chain verdicts, defer to the `security-review-process`
skill — this is the upgrade *workflow*, that is the security *verdict*.

### Red-flag rebuttals

| Rationalization | Reality |
|-----------------|---------|
| "It's just a version bump" | A bump is a behavior change you didn't write. Read the changelog; semver doesn't guarantee no breakage. |
| "I'll upgrade everything in one PR to save time" | A bulk bump that breaks the build hides which package did it. One dependency per change keeps the cause and the revert clean. |

## Review Feedback Hygiene

When acting on review comments before re-requesting review (mirrors the PR-feedback discipline in upstream review-agent-governance pattern):

- [ ] Every blocking comment is addressed (fixed, or explicitly justified in a reply) before re-requesting review
- [ ] Each fix references the specific comment it resolves (commit message or PR thread reply)
- [ ] No silent scope expansion: changes outside the original review request are flagged separately
- [ ] Re-request review only after CI/local checks pass on the updated diff
- [ ] If a comment is rejected, document the rationale in the thread — do not close without reply
