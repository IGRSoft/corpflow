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
