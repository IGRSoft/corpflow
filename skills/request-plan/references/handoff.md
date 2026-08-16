# Handoff to Worktask

A plan that doesn't end with a clear next action is just commentary. Close every plan with one
ready-to-paste `/worktask` command line so the user can execute immediately.

## Tier selection (canonical)

Use the **Worktask Tier Selection** logic from `skills/estimation-methodology/SKILL.md` — do not invent a
parallel ruleset. Summarized:

```
size = T-shirt size from the estimation sizing table

IF size == XL:   → split first (recommend ≤ L sub-tasks; no single command)
ELSE:            → /worktask "<goal>"   (PL0 dynamic sizing drops stages for small work)
```

The surface check above decides `--secure` and `--emergency`; the size rule only applies once both are ruled out.

## Command lines

Emit exactly one of these, with the restated goal as the payload:

| Tier | Line to emit | For |
|------|--------------|-----|
| `--secure` | `/worktask --secure "<goal>"` | work handling credentials, tokens, secrets, PII, payments, authn/authz, or untrusted input — any size |
| `--emergency` | `/worktask --emergency "<goal>"` | something is broken right now and still failing |
| `/worktask` | `/worktask "<goal>"` | everything else — PL0 dynamic sizing picks the stage set |
| split | *(no single command)* | XL — recommend splitting into ≤ L sub-tasks first, then re-plan |

Check the two escalation rows before the size rule; both beat size in either direction. Escalating
ordinary work burns the security pipeline, and leaving a live failure on the standard one delays it.
Emit exactly one line — a plan that recommends running some other command *instead* of a worktask
has not made the handoff.

For the split case, don't emit a command. Instead list the 2–3 sub-tasks the work should break into,
and note that each can be re-planned with this skill once separated.

## Phrasing the recommendation

One line of rationale, tied to the size/complexity you computed — e.g.:

> **Recommended:** `/worktask --secure "add Keychain-backed settings store"` — M-sized, touches
> credential storage (security-sensitive), so the full pipeline with its security review stage applies.

If the user might instead want formal requirements or a budget before committing, name the command:
`/pm-requirements` for a PRD, `/estimate --detailed` for hours and budget.
