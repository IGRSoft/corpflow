---
name: swift-arch-review
description: Swift architecture review with per-pattern checklists, anti-pattern detection, and 5-dimension scoring rubric.
effort: medium
---

# Swift Architecture Review Skill

Review Swift code for architecture pattern conformance, anti-patterns, and best practices.

## When to Use

- Swift PR review requiring architecture conformance check
- DV/QA stages validating implementation against chosen pattern
- Code audit scanning for architecture anti-patterns
- Pre-merge review of structural changes

## Pattern Detection

When the architecture pattern is not specified, detect it from codebase signals:

| Signal | Pattern |
|--------|---------|
| `@Observable` / `ObservableObject` ViewModel + View binding | MVVM |
| `Intent` / `Action` enums + `Reducer` + `Effect` types | MVI |
| `@Reducer` macro, `StoreOf`, `TestStore`, `@Dependency` | TCA |
| `Domain/` + `Data/` + `Presentation/` layers, use-case protocols | Clean Architecture |
| `Publisher` / `Observable` chains, `switchToLatest`, `debounce` | Reactive |
| `ViewProtocol` with command methods, Presenter with `weak var view` | MVP |
| `Coordinator` protocol, `childCoordinators`, navigation state | Coordinator |

Also check `.context/analyzing.md` for the architecture pattern selected during the AR stage.

## Review Process

1. **Detect pattern** — from code signals, analyzing.md, or `--pattern` argument
2. **Load checklist** — from `${CLAUDE_SKILL_DIR}/references/review-checklists.md`
3. **Scan for anti-patterns** — from `${CLAUDE_SKILL_DIR}/references/anti-patterns.md`
4. **Score** — rate each of 5 dimensions
5. **Report** — output findings with file:line references and fix suggestions

## Scoring Rubric

Rate each dimension 0 (violation) or 1 (compliant):

| Dimension | What to Check |
|-----------|---------------|
| **Pattern Conformance** | Components follow chosen pattern boundaries; no role leakage |
| **State Management** | Correct state modeling; no stale overwrites; single source of truth |
| **DI Quality** | Protocol-based injection; no singletons; assembly at composition root |
| **Concurrency Safety** | Cancellation handling; `@MainActor` for UI; no data races |
| **Testability** | Deterministic tests; controlled stubs; success/failure/cancellation paths |

**Score interpretation**: 5=Excellent, 4=Good, 3=Usable with gaps, ≤2=Needs rework

## Output Format

```markdown
# Swift Architecture Review

## Pattern: {detected or specified pattern}
Detection method: {code signals | analyzing.md | --pattern flag}

## Score
| Dimension | Score | Notes |
|-----------|-------|-------|
| Pattern Conformance | 1/1 | All boundaries respected |
| State Management | 0/1 | Stale overwrite risk in ProfileViewModel |
| DI Quality | 1/1 | Protocol injection throughout |
| Concurrency Safety | 1/1 | Cancellation handled |
| Testability | 0/1 | Missing failure path tests |
| **Total** | **3/5** | **Usable with gaps** |

## Findings

### Violations
1. **{Anti-pattern name}**
   - Location: `path/File.swift:45`
   - Issue: {description}
   - Fix: {concrete fix}

### Checklist Results
- [x] {passed item}
- [ ] {failed item — with explanation}

## Recommendations
### Must Fix (Before Merge)
1. {critical issue}

### Should Fix (Soon)
1. {important issue}
```

## Integration

- **AR stage**: Validate architecture selection fits project constraints
- **DV stage**: Developer self-checks before marking DV complete
- **QA stage**: QA engineer validates architecture conformance
- **Pre-merge**: Reviewer applies pattern-specific checklist
- **`/swift-arch-review` command**: Invokes this skill directly

## References

- Checklists: `${CLAUDE_SKILL_DIR}/references/review-checklists.md`
- Anti-patterns: `${CLAUDE_SKILL_DIR}/references/anti-patterns.md`
- Pattern details: `skills/swift-architecture/references/{pattern}.md`
