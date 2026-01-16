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

| Category | Trigger | Typical Increase |
|----------|---------|------------------|
| AR/Camera SDKs | Metal, AVFoundation, face tracking | L → XL (+5 SP) |
| API Integration | Image processing, async handling | +2 SP |
| BLE/Hardware | State machines, background modes | M → L (+3 SP) |
| Vision Framework | Face detection, landmarks | M → L (+3 SP) |
| Offline Sync | Conflict resolution, Core Data | M → L (+3 SP) |
| Third-party SDKs | Unknown documentation quality | +20% buffer |

## Platform-Specific Adjustments

### iOS/SwiftUI
| Feature | Adjustment |
|---------|------------|
| Metal rendering | +5 SP |
| ARKit integration | +8 SP |
| CoreBluetooth state machine | +5 SP |
| Vision face detection | +3 SP |
| App Store review prep | +3 SP |
| Background app refresh | +2 SP |
| Push notifications | +2 SP |
| Deep linking | +2 SP |

### Android/Kotlin
| Feature | Adjustment |
|---------|------------|
| NDK/JNI integration | +5 SP |
| BLE background services | +5 SP |
| Camera2 API | +3 SP |
| Play Store compliance | +2 SP |
| WorkManager setup | +2 SP |

### Web/React
| Feature | Adjustment |
|---------|------------|
| WebGL rendering | +5 SP |
| WebRTC integration | +5 SP |
| Service workers | +3 SP |
| IndexedDB sync | +3 SP |

## Review Process

1. **Read estimation artifacts**
   - features_breakdown.csv
   - complexity_analysis.csv
   - integration_specifics.csv

2. **Identify adjustment triggers**
   - Check each feature against matrix
   - Note platform-specific concerns

3. **Apply adjustments**
   - Update SP for affected features
   - Recalculate hours (SP × 6h)
   - Add buffer for unknowns

4. **Document changes**
   - Original vs adjusted values
   - Rationale for each adjustment
   - Risk flags identified

5. **Update totals**
   - Recalculate phase summary
   - Update budget
   - Adjust timeline if needed

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
| Category | Original | Adjusted | Delta | Reason |
|----------|----------|----------|-------|--------|
| [Feature] | [Size] | [New Size] | +X SP | [Reason] |

### Total Impact
- Original SP: X
- Adjusted SP: Y
- Delta: +Z SP (+N%)
- Hours Impact: +Nh

### Risk Flags
1. [Risk 1]
2. [Risk 2]

### Recommendations
1. [Action 1]
2. [Action 2]
```
