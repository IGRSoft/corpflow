---
name: senior-developer-review
description: Use when conducting senior-level code or estimate reviews. Technical review framework for estimates by platform specialists.
effort: low
---

# Senior Developer Review Guidelines

Technical review of estimates by platform specialists.

## When to Apply

Complexity score >= 15, or the estimate involves: AR/ML/Vision frameworks, BLE/hardware SDKs,
real-time camera processing, third-party SDKs of unknown quality, background processing.

## Adjustment Matrix

Capability-keyed and platform-neutral — the concrete APIs behind each capability live in the
per-platform tables below.

| Category | Trigger | Min Increase | Max Increase |
|----------|---------|-------------|-------------|
| Realtime graphics / camera | GPU pipeline, capture session, marker or face tracking | +3 SP | +5 SP |
| API integration | Media processing, async orchestration, retry/backoff | +1 SP | +2 SP |
| Hardware / peripheral I/O | Connection state machines, background execution | +2 SP | +3 SP |
| On-device inference | Detection, landmarks, model loading and warm-up | +2 SP | +3 SP |
| Offline sync | Conflict resolution, local persistence | +2 SP | +3 SP |
| Third-party SDKs | Unknown documentation quality | +15% buffer | +20% buffer |

## Platform-Specific Adjustments

Apply only the table matching the reviewed platform; each row instantiates an Adjustment
Matrix capability with that platform's concrete APIs.

### Apple/SwiftUI
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

### Backend
| Feature | Min Adjustment | Max Adjustment |
|---------|---------------|---------------|
| Cross-service transaction / idempotency | +3 SP | +5 SP |
| Schema migration against live data | +2 SP | +3 SP |
| Public API contract + versioning | +2 SP | +3 SP |
| AuthN/AuthZ and tenant isolation | +2 SP | +3 SP |
| Queue / event-driven fan-out | +2 SP | +3 SP |

### Systems (C/C++/Python/Bash)
| Feature | Min Adjustment | Max Adjustment |
|---------|---------------|---------------|
| Manual memory ownership redesign | +3 SP | +5 SP |
| FFI / language-boundary bindings | +2 SP | +3 SP |
| Cross-platform build + toolchain matrix | +2 SP | +3 SP |
| Sanitizer / UB triage on existing code | +1 SP | +2 SP |
| ABI-stable public interface | +2 SP | +3 SP |

### AI/ML
| Feature | Min Adjustment | Max Adjustment |
|---------|---------------|---------------|
| Fine-tuning or training run | +5 SP | +8 SP |
| RAG pipeline (ingest, chunk, retrieve) | +3 SP | +5 SP |
| Eval harness + regression baselines | +2 SP | +3 SP |
| Inference serving under a cost/latency budget | +2 SP | +3 SP |

## Review Process

1. **Read estimation artifacts** — `features_breakdown.csv`, `complexity_analysis.csv`,
   `integration_specifics.csv`.
2. **Identify adjustment triggers** — check each feature against the matrix; note
   platform-specific concerns.
3. **Apply adjustments** — update SP Min and SP Max per feature, recalculate hours
   (Hours = SP × 6h, Min and Max independently), add the unknowns buffer to both.
4. **Document changes** — original vs adjusted Min/Max, rationale per adjustment, risk flags.
5. **Update totals** — recalculate the phase summary (Min and Max independently), the budget
   range, and the timeline range if it shifts.

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
- [ ] Distribution-channel requirements (App Store, Play Store, package registry, deploy target)
- [ ] Localization requirements
- [ ] Accessibility requirements

## Risk Flags

| Flag | Action |
|------|--------|
| Third-party SDK not supporting the target platform version | Add contingency phase |
| Bluetooth or peripheral background requirements | Test on real devices early |
| AR / face tracking | Check the distribution channel's review guidelines |
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

A bump is a behavior change you did not write, and bulk "bump deps" merges are the riskiest.
When the review touches a manifest (`Package.swift`, `Podfile`, `*.gradle`,
`requirements.txt`, `package.json`, …) or its lockfile, apply feature-code discipline.

Advisory triage and supply-chain verdicts defer to the `security-review-process` skill: this
is the upgrade *workflow*, that is the security *verdict*.

### Upgrade rules

| Rule | Why |
|------|-----|
| Read the changelog, not the version number | Semver is a promise the maintainer may not have kept; a "patch" can carry behavior change. Major bump → read the migration notes |
| One dependency per change | A bulk bump that breaks the build hides which package did it; single-package changes keep the cause and the revert clean |
| Let the suite decide | Green before *and* after, not "it resolved". Thin coverage around the dependency's behavior is itself the finding — add a test first |
| Mind the transitive graph | Most resolved packages nobody chose directly; review the lockfile / transitive diff, not just the manifest |
| Keep the lockfile honest | Committed, diff reviewed, never hand-edited — `Package.resolved` and equivalents pin what ships |

## Review Feedback Hygiene

Before re-requesting review on acted-on comments:

- [ ] Every blocking comment addressed — fixed, or explicitly justified in a reply
- [ ] Each fix references the comment it resolves (commit message or PR thread reply)
- [ ] No silent scope expansion: changes outside the original request are flagged separately
- [ ] CI/local checks pass on the updated diff before re-requesting
- [ ] Rejected comments carry their rationale in the thread — never closed without a reply
