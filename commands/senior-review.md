---
name: senior-review
description: Technical review of estimates by platform specialist
model: sonnet
---

# Senior Review Command

Technical review of estimates by platform specialist.

## Usage

```
/senior-review
/senior-review --platform apple
/senior-review --focus ar,ble
```

## Options

- `--platform <apple|android|web|all>` - Platform context (default: all)
- `--focus <areas>` - Comma-separated focus areas (ar, ble, vision, api, camera, sync)
- `--update` - Auto-update estimation files with adjustments

## Examples

```
/senior-review
/senior-review --platform apple --focus ar,ble
/senior-review --platform android --update
```

## When to Use

- Projects with complexity score >= 15
- AR/ML/Vision framework integration
- BLE/Hardware SDK integration
- Real-time camera processing
- Third-party SDK integration

## Output Format

```markdown
## Senior Developer Review: [Project]

### Adjustment Summary
| Category | Original | Adjusted | Delta | Reason |
|----------|----------|----------|-------|--------|
| AR SDK | L (8) | XL (13) | +5 | Metal pipeline complexity |
| BLE | M (5) | L (8) | +3 | State machine handling |
| Vision | M (5) | L (8) | +3 | Face detection + landmarks |

### Total Impact
- Original SP: 152
- Adjusted SP: 182
- Delta: +30 SP (+20%)
- Hours Impact: +180h

### Risk Flags
1. Third-party SDK iOS version support uncertain
2. BLE background mode reliability concerns
3. App Store AR review requirements

### Recommendations
1. Request SDK documentation from vendor before Phase 3
2. Build BLE mock service for development testing
3. Prepare App Store demo video for AR features
```

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

### Android/Kotlin
| Feature | Adjustment |
|---------|------------|
| NDK/JNI integration | +5 SP |
| BLE background services | +5 SP |
| Camera2 API | +3 SP |
| Play Store compliance | +2 SP |

## Review Checklist

Before finalizing, verify:

- [ ] All SDK integrations identified
- [ ] Background mode requirements assessed
- [ ] Permissions flow complexity included
- [ ] Error handling for network failures
- [ ] Offline mode if required
- [ ] Analytics integration
- [ ] Push notification handling
- [ ] App Store/Play Store requirements

## Integration

This command works with:
- `/estimate --detailed` - Initial estimation
- `/export-estimate` - Updated CSV export
- Platform agents (swift-pro, kotlin-pro, etc.)

## Related

- [senior-developer-review](../skills/senior-developer-review.md) - Review guidelines
- [estimation-methodology](../skills/estimation-methodology.md) - Methodology
