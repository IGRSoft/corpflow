# Handoff to Worktask

A plan that doesn't end with a clear next action is just commentary. Close every plan with one
ready-to-paste worktask trigger line so the user can execute immediately.

## Tier selection (canonical)

Use the **Worktask Tier Selection** logic from `skills/estimation/SKILL.md` — do not invent a
parallel ruleset. Summarized:

```
size       = T-shirt size from the estimation sizing table
complexity = sum of the 5 complexity factors (0–25)
security   = true if Risk Level ≥ 4 OR the work touches auth / PII / payments

IF size == XL:                              → split first (too big for one worktask)
ELSE IF size == XS AND complexity ≤ 5 AND NOT security:   → micro:
ELSE IF size == XS AND NOT security:        → quick:   (XS but complexity > 5)
ELSE IF size == S AND NOT security:         → quick:
ELSE IF size ∈ {M, L} OR security:          → worktask:
```

Security-sensitive work always routes to `worktask:` regardless of size — the full pipeline runs the
security review stage that lighter tiers skip.

## Trigger lines

Emit exactly one of these, with the restated goal as the payload:

| Tier | Line to emit | For |
|------|--------------|-----|
| `micro:` | `micro: <goal>` | single-file fix, typo, trivial change |
| `quick:` | `quick: <goal>` | small feature or bug fix (PL → DV → DR → QA) |
| `worktask:` | `worktask: <goal>` | multi-file feature, or anything security-sensitive |
| split | *(no single trigger)* | XL — recommend splitting into ≤ L sub-tasks first, then re-plan |

For the split case, don't emit a trigger. Instead list the 2–3 sub-tasks the work should break into,
and note that each can be re-planned with this skill once separated.

## Phrasing the recommendation

One line of rationale, tied to the size/complexity you computed — e.g.:

> **Recommended:** `worktask: add Keychain-backed settings store` — M-sized, touches credential
> storage (security-sensitive), so the full pipeline with its security review stage applies.

If the user might instead want formal requirements or a budget before committing, name the command:
`/pm-requirements` for a PRD, `/estimate --detailed` for hours and budget.
