# Handoff to Worktask

A plan that doesn't end with a clear next action is commentary. Close every plan with one
ready-to-paste `/worktask` command line.

## Tier selection (canonical)

Use the **Worktask Tier Selection** logic from `skills/estimation-methodology/SKILL.md` — never a
parallel ruleset. Summarized:

```
size = T-shirt size from the estimation sizing table

IF size == XL:   → name the 2–3 sub-tasks, then emit the line for the FIRST of them
ELSE:            → /worktask "<goal>"   (PL0 dynamic sizing drops stages for small work)
```

The surface check above decides `--secure` and `--emergency`; the size rule applies only once both
are ruled out.

## Command lines

Emit exactly one of these, with the restated goal as the payload:

| Tier | Line to emit | For |
|------|--------------|-----|
| `--secure` | `/worktask --secure "<goal>"` | work handling credentials, tokens, secrets, PII, payments, authn/authz, or untrusted input — any size |
| `--emergency` | `/worktask --emergency "<goal>"` | something is broken right now and still failing |
| `/worktask` | `/worktask "<goal>"` | everything else — PL0 dynamic sizing picks the stage set |
| split | `/worktask "<first sub-task>"` | XL — name the ≤ L sub-tasks, then trigger the first |

### Escalation beats size

Check both escalation rows before the size rule; they beat size in either direction — escalating
ordinary work burns the security pipeline, and leaving a live failure on the standard one delays it.
Emit exactly one line: a plan recommending some other command *instead* of a worktask has not made
the handoff.

XL is not an exception to that. List the 2–3 sub-tasks the work breaks into, note each can be
re-planned with this skill once separated, and still emit one line — for the first sub-task, not the
whole XL goal. "Split first, no command" leaves the user with nothing to paste, which is the
`no-handoff-trigger` failure wearing a size label (`SKILL.md § 4`; `commands/request-plan.md` step 3).

### The flag must match what the plan body argues

**Prose and the command line are one recommendation, and the line is the part that executes.** Before
emitting it, read back what the plan body claims:

- body argues the **request** asked for security review, threat modelling, or credential/PII
  handling → the line carries `--secure`
- body argues the thing is broken right now and still failing → the line carries `--emergency`
- body argues neither → the line is plain, and the plan says so rather than leaving it implied

A plan that argues for a security review "before merge, not just standard DR" and then emits a plain
`/worktask` has recommended two different things. Fix whichever is wrong — if the body overstated
what the request asked for, cut the claim; if it did not, carry the flag. Do not ship the pair.

#### Reporting a surface you found is not arguing for the flag

The tier is decided by the request (`estimation-methodology § A surface you discover does not raise
the tier`), so a plan may name a credential path the search turned up — it usually should — without
that naming becoming a reason to escalate.

The check above compares the flag against what the body says the **request** needs, never against
everything the body mentions. Read the other way it escalates any plan whose search walked past a
secret, which in a plugin is most of them.

## Phrasing the recommendation

One line of rationale tied to the size/complexity you computed — e.g.:

> **Recommended:** `/worktask --secure "add Keychain-backed settings store"` — M-sized, touches
> credential storage (security-sensitive), so the full pipeline with its security review stage applies.

If the user might want formal requirements or a budget first, name the command: `/product-requirements`
for a PRD, `/estimate --detailed` for hours and budget.
