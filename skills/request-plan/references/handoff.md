# Handoff to Worktask

A plan that doesn't end with a clear next action is just commentary. Close every plan with one
ready-to-paste worktask trigger line so the user can execute immediately.

## Tier selection (canonical)

Use the **Worktask Tier Selection** logic from `skills/estimation/SKILL.md` — do not invent a
parallel ruleset. Summarized:

```
size = T-shirt size from the estimation sizing table

IF size == XL:   → split first (recommend ≤ L sub-tasks; no single trigger)
ELSE:            → worktask:   (single trigger; PL0 dynamic sizing drops stages for small work)
```

Security-sensitive work should use `worktask: --secure` to run the 11-stage pipeline with the security review stage.

## Trigger lines

Emit exactly one of these, with the restated goal as the payload:

| Tier | Line to emit | For |
|------|--------------|-----|
| `worktask:` | `worktask: <goal>` | any task — PL0 dynamic sizing picks the stage set |
| split | *(no single trigger)* | XL — recommend splitting into ≤ L sub-tasks first, then re-plan |

For the split case, don't emit a trigger. Instead list the 2–3 sub-tasks the work should break into,
and note that each can be re-planned with this skill once separated.

## Phrasing the recommendation

One line of rationale, tied to the size/complexity you computed — e.g.:

> **Recommended:** `worktask: add Keychain-backed settings store` — M-sized, touches credential
> storage (security-sensitive), so the full pipeline with its security review stage applies.

If the user might instead want formal requirements or a budget before committing, name the command:
`/pm-requirements` for a PRD, `/estimate --detailed` for hours and budget.
