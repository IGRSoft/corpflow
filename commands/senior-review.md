---
name: senior-review
description: Technical review of estimates by platform specialist
argument-hint: <estimate or task to review>
model: sonnet
allowed-tools: Read, Glob, Grep
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
| Category | Original (Min-Max) | Adjusted (Min-Max) | Delta | Reason |
|----------|--------------------|--------------------|-------|--------|
| AR SDK | L (5-10) | XL (13-21) | +8-11 | Metal pipeline complexity |
| BLE | M (3-5) | L (5-10) | +2-5 | State machine handling |
| Vision | M (3-5) | L (5-10) | +2-5 | Face detection + landmarks |

### Total Impact
- Original SP: 120-152
- Adjusted SP: 150-193
- Delta: +30-41 SP (+25-27%)
- Hours Impact: +180-246h

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

### Android/Kotlin
| Feature | Min Adjustment | Max Adjustment |
|---------|---------------|---------------|
| NDK/JNI integration | +3 SP | +5 SP |
| BLE background services | +3 SP | +5 SP |
| Camera2 API | +2 SP | +3 SP |
| Play Store compliance | +1 SP | +2 SP |

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
- Platform agents (apple-developer, ios-developer, kotlin-pro, etc.)

## Related

- [senior-developer-review](../skills/review/SKILL.md) - Review guidelines
- [estimation-methodology](../skills/estimation/SKILL.md) - Methodology
