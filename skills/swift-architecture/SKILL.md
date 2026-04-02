---
name: swift-architecture
description: Swift iOS architecture patterns (MVVM, MVI, TCA, Clean, Reactive, MVP, Coordinator) with selection guide and cross-cutting patterns.
effort: high
---

# Swift Architecture Skill

Select and apply the right Swift architecture pattern for SwiftUI/UIKit projects.

**Scope boundary**: This skill covers *how to structure a Swift app* (patterns, boundaries, DI, state management). For Swift language features, concurrency, and platform APIs, defer to the `apple-developer` plugin agents (swift-pro, ios-developer, etc.).

## When to Use

- New feature requiring architecture design
- Refactoring existing code to a cleaner pattern
- PR review checking architecture conformance
- Greenfield pattern selection for a new project/module

## Pattern Selection Guide

### Quick Decision Flow

```
1. Stream-heavy (search, live feeds, WebSocket)?
   YES → Reactive. If also needs strict state-machine, combine with MVI.

2. Strict unidirectional data flow / state-machine required?
   YES → TCA dependency acceptable? → TCA. Otherwise → MVI.

3. Strict layer isolation with replaceable infrastructure?
   YES → Clean Architecture.

4. Primary goal: decouple navigation from screens (deep linking, reusable flows)?
   YES → Coordinator (pair with a presentation pattern below).

5. UIKit-primary, fully passive View with zero logic?
   YES → MVP.

6. Default → MVVM.
```

### Signal Words → Pattern

| Signal | Pattern |
|--------|---------|
| "simple feature", "screen-level state", "standard iOS" | MVVM |
| "state machine", "deterministic transitions", "unidirectional" | MVI |
| "composable", "TestStore", "pointfree", existing TCA codebase | TCA |
| "layers", "use cases", "dependency rule", "hexagonal" | Clean Architecture |
| "streams", "Combine", "RxSwift", "real-time", "search" | Reactive |
| "passive view", "presenter drives view", "UIKit no observable" | MVP |
| "navigation", "deep linking", "flow", "routing" | Coordinator |

### Valid Hybrid Combinations

- MVVM + Coordinator — screen state + navigation decoupling
- MVVM + Reactive — MVVM structure with Combine/Rx pipelines in ViewModels
- Clean Architecture + MVVM — Clean layers for domain/data, MVVM for presentation
- Clean Architecture + TCA — Clean layers for domain/data, TCA for features
- MVP + Coordinator — MVP for presentation, Coordinator for routing
- MVP + Reactive — MVP structure with reactive Interactors

### Decision Matrix

| Factor | MVVM | MVI | TCA | Clean | Reactive | MVP | Coordinator |
|--------|------|-----|-----|-------|----------|-----|-------------|
| State complexity | Low–Med | High | High | Med–High | Med | Low–Med | N/A |
| Unidirectional flow | Optional | Strict | Strict | N/A | Stream | Optional | N/A |
| Testing determinism | Good | Very high | Very high | Good | Good | Good | Good |
| Boilerplate | Low | Medium | Med–High | Med–High | Low–Med | Medium | Low–Med |
| SwiftUI fit | Excellent | Good | Excellent | Good | Good | Fair | Good |
| UIKit fit | Good | Good | Good | Good | Good | Excellent | Excellent |
| Learning curve | Low | Medium | High | Medium | Medium | Low | Low |
| Framework dependency | None | None | TCA lib | None | Combine/Rx | None | None |

### Validating User-Requested Architectures

When user pre-selects a pattern:
1. Check fit: UI stack, state complexity, effect orchestration, team familiarity, existing conventions
2. Result: `fit` or `mismatch` with 1-2 reasons
3. If mismatch: recommend closest-fit alternative; if user insists, proceed with risk-mitigation plan

## Cross-Cutting Patterns

These apply to ALL architecture patterns. Individual reference files only note pattern-specific variations.

### Protocol-Based Dependency Injection

- Define service protocols in the domain/feature layer
- Inject via initializer — never use global singletons
- Assembly/composition root wires concrete implementations
- Test doubles implement the same protocols

### @MainActor for UI Mutations

- All UI state writes must be `@MainActor`-isolated
- ViewModels/Presenters: annotate the class or individual methods
- Never dispatch to main queue manually when `@MainActor` is available

### Task Cancellation Strategies

| Pattern | Strategy |
|---------|----------|
| MVVM | Cancel previous `Task` before starting new one |
| MVI | Request ID versioning — guard stale responses in reducer |
| TCA | `.cancellable(id:cancelInFlight:true)` — built-in |
| Clean | `async let` + natural cancellation propagation |
| Reactive | `switchToLatest()` — auto-cancels previous subscription |
| MVP | Request ID versioning — guard stale responses in Presenter |
| Coordinator | N/A — delegates to child pattern |

### Deterministic Testing

- Inject controlled stubs (not real network/DB)
- Use `TestClock` / `DispatchQueue.test` for time-dependent tests
- Test paths: success, failure, cancellation, stale-response handling
- Avoid `sleep`/`Task.sleep` — use continuations or controlled clocks

### Navigation Patterns

| Stack | Approach |
|-------|----------|
| SwiftUI | `NavigationStack` + `@Observable` coordinator + `Hashable` destination enum |
| UIKit | `UINavigationController` + Router/Coordinator wrapper |
| Hybrid | Coordinator owns navigation; ViewModels receive navigation closures |
| Deep linking | Centralized `DeepLinkHandler` updates coordinator state |

## Pattern Reference Files

| Pattern | Best For | Reference |
|---------|----------|-----------|
| MVVM | Screen-level state, flexible navigation | `${CLAUDE_SKILL_DIR}/references/mvvm.md` |
| MVI | Strict unidirectional flow, deterministic state | `${CLAUDE_SKILL_DIR}/references/mvi.md` |
| TCA | Strong composition, TestStore testing | `${CLAUDE_SKILL_DIR}/references/tca.md` |
| Clean Architecture | Layer isolation, replaceable infrastructure | `${CLAUDE_SKILL_DIR}/references/clean-architecture.md` |
| Reactive | Stream-driven features (search, live feeds) | `${CLAUDE_SKILL_DIR}/references/reactive.md` |
| MVP | Passive View, UIKit-native testability | `${CLAUDE_SKILL_DIR}/references/mvp.md` |
| Coordinator | Navigation decoupling, deep linking | `${CLAUDE_SKILL_DIR}/references/coordinator.md` |

## Workflow

### Step 1: Analyze Request Context

Capture: task type (new feature, refactor, PR review, debugging), UI stack (SwiftUI, UIKit, mixed), scope (single screen, multi-screen, app-wide), existing conventions.

### Step 2: Select Architecture

- If user names a pattern → run fit check → proceed or recommend alternative
- If no pattern named → use Quick Decision Flow above → explain recommendation

### Step 3: Analyze Existing Codebase (When Applicable)

- Detect current architecture and DI style
- Note concurrency model (async/await, Combine, GCD, mixed)
- Align recommendations to local conventions

### Step 4: Produce Deliverables

Load the selected pattern reference and produce:
- **File and module structure** — directory layout with file names
- **State and dependency boundaries** — concrete types, protocols, injection points
- **Async strategy** — cancellation, actor isolation, error paths
- **Testing strategy** — what to test, how to stub, example test structure
- **Migration path** (for refactors) — incremental steps from current to target
- **UI stack adaptation** — where SwiftUI and UIKit guidance differ

### Step 5: Validate with Checklist

Apply the pattern-specific PR review checklist from the reference file, adapted to the user's feature.

## Output Requirements

- Scope recommendations to the requested feature or review task
- Flag anti-patterns found in existing code with direct fixes
- Include cancellation and error handling in all async flows
- For explicit architecture requests, include fit result (`fit`/`mismatch`) with reasons
- When writing code, include only patterns relevant to the task — do not dump entire playbooks
- Ask only blocking questions; proceed with explicit assumptions stated up front
