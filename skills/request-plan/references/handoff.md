# Handoff to Worktask

Close every plan with one ready-to-paste `/worktask` command line.

## Tier selection (canonical)

Use the Worktask Tier Selection logic in `skills/estimation-methodology/SKILL.md` — never a
parallel ruleset. Its surface check decides `--secure` and `--emergency`; the size rule applies
only once both are ruled out.

## Command lines

Emit exactly one of these, with the restated goal as the payload:

| Tier | Line to emit | For |
|------|--------------|-----|
| `--secure` | `/worktask --secure "<goal>"` | the request names credentials, tokens, secrets, PII, payments, authn/authz, or untrusted input — any size |
| `--emergency` | `/worktask --emergency "<goal>"` | something is broken right now and still failing |
| `/worktask` | `/worktask "<goal>"` | everything else — PL0 dynamic sizing picks the stage set |
| split | `/worktask "<first sub-task>"` | XL — name the ≤ L sub-tasks, then trigger the first |

### Escalation beats size

Check both escalation rows before the size rule; they beat size in either direction — escalating
ordinary work burns the security pipeline, and leaving a live failure on the standard one delays it.

XL still gets a line. List the 2–3 sub-tasks the work breaks into, note each can be re-planned with
this skill once separated, and emit the line for the first sub-task, not the whole XL goal. "Split
first, no command" leaves the user nothing to paste — the `no-handoff-trigger` failure
(`SKILL.md § 4`).

### The flag must match what the plan body argues

Prose and the command line are one recommendation, and the line is the part that executes. Before
emitting it, read back what the plan body claims:

- body argues the **request** names one of the assets in the `--secure` row above (canon's list,
  from `skills/estimation-methodology/SKILL.md § Worktask Tier Selection`) → the line carries
  `--secure`
- body argues the thing is broken right now and still failing → the line carries `--emergency`
- body argues neither → the line is plain, and the plan says so rather than leaving it implied

A plan whose body says the request puts user tokens in a new store and then emits a plain
`/worktask` has recommended two different things. Fix whichever is wrong — if the body overstated
what the request asked for, cut the claim; if it did not, carry the flag.

#### The claim to read back is an asset, not a topic

The `--secure` row asks which asset the request names, never how security-flavoured the topic
sounds. Canon rules the topic reading out (`estimation-methodology § What the two escalations are
not`), so a request to review, audit or threat-model something names no asset by itself.

#### Reporting a surface you found is not arguing for the flag

The tier is decided by the request (`estimation-methodology § A surface you discover does not raise
the tier`), so a plan may name a credential path the search turned up — it usually should — without
that becoming a reason to escalate. Compare the flag against what the body says the request needs,
not against everything the body mentions; otherwise any plan whose search walked past a secret
escalates.

## Phrasing the recommendation

One line of rationale tied to the size/complexity you computed — e.g.:

> **Recommended:** `/worktask --secure "add Keychain-backed settings store"` — M-sized, and the
> request names credential storage, so the full 11-stage pipeline applies.

If the user might want formal requirements or a budget first, name the command alongside the line:
`/product-requirements` for a PRD, `/estimate --detailed` for hours and budget.
