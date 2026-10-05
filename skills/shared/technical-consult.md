---
name: technical-consult
---

# Technical Consult (TC) Reference

Read on demand by `agents/technical-lead.md` when answering a technical consult (stage TC) on technology choice, tech debt or implementation risk. The DR review never needs it.

## Technology Evaluation Framework

Prefer, in order: battle-tested (mature, documented, proven, strong community), then serious newcomers (established vendor, clear maintenance commitment). Avoid anonymous, untested, unmaintained, or deprecated technologies.

Score options with the weighted criteria in `commands/arch-decision.md § Evaluation Framework` (team expertise 20%, then community, viability, performance and security at 15% each, integration and cost at 10%). TDR template and the full decision worktask: `commands/arch-decision.md`. Non-markdown documents or document URLs: use pandoc (`skills/shared/pandoc-ingestion.md`).

## Technical Debt Management

Score each debt item 1-5 per PAID dimension: Principal (cost of the shortcut), Accumulated interest (ongoing maintenance burden), Impact on delivery (feature slowdown), Dependency risk (cascade to other systems).

| Type | Interest | Priority Action |
|------|----------|-----------------|
| Security | Critical | Fix now |
| Architecture | High | Schedule (escalate to AR stage) |
| Code | Medium | Fix now or schedule |
| Test | Medium | Schedule |
| Dependency | Variable | Track or schedule |
| Documentation | Low | Track or accept |

The 20% rule: allocate 20% of sprint capacity to debt reduction, high-impact low-effort first, linking items to business metrics (customer issues, maintenance time) to prioritize by actual impact.

## Technical Risk Assessment

| Category | Examples | Mitigation |
|----------|----------|------------|
| Complexity | Tight coupling, deep nesting | Refactor, simplify |
| Performance | O(n²) algorithms, memory leaks | Profile, optimize |
| Security | Injection, auth weaknesses | Review, harden |
| Dependency | Abandoned libraries, CVEs | Update, replace |
| Scalability | Single points of failure | Design for scale |

Assess each by likelihood × impact (High/Medium/Low); document indicators, mitigation steps, contingency plans.
