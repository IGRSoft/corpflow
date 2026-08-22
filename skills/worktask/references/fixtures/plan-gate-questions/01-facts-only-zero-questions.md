# Fixture 01 — Every open question is a fact; zero reach the gate

Exercises `§ Facts are PL0's job; decisions are the user's`. Every candidate question PL0 raises
while drafting is answerable from the repository, so PL0 resolves all of them and the plan gate
receives an empty list.

Primary AC: **AC-8** (a planning run whose only open question is answerable by inspecting the
repository produces zero plan-gate questions).

## Input

Task description:

```
Wire the four lint scripts into a CI job.
```

Repository state the run can inspect: four scripts under `skills/worktask/scripts/`, no
`.github/workflows/` directory, a committed `run-tests.sh`.

## Candidate questions PL0 raises while drafting

| # | Candidate | Class | Resolver |
|---|---|---|---|
| c1 | "How many lint scripts are there?" | fact | `ls skills/worktask/scripts/*-lint.sh` |
| c2 | "Does a workflow already exist?" | fact | `ls .github/workflows/ 2>/dev/null` |
| c3 | "Do any of the four fail today?" | fact | run each script, record exit codes |
| c4 | "Which of them exit non-zero on a bare invocation?" | fact | run each bare, record exit codes |

No candidate turns on what the user *wants*, so none is a decision.

## Expected gate output

- `handoff.open_questions[]` — **0 entries**.
- `## summary` numbered elicitation list — **absent** (nothing to elicit).
- PL0 completes without a gate round-trip for questions. The plan-approval checkpoint itself is
  unaffected: it still fires, it just carries no question list.

## Expected plan content

Each resolved fact appears in the plan as a stated value with the command that produced it — for
example "four lint scripts (`ls skills/worktask/scripts/*-lint.sh`)", "no workflows directory
exists (verified)", "`section-lint.sh` exits 1 today, two sections over cap".

An unresolved candidate silently dropped is a failure of this fixture just as much as one surfaced
to the gate: "I did not look" and "the user must choose" are different states.

## Cost-is-not-an-exemption variant

If c3 required running a slow repo-wide sweep, the expected behaviour is unchanged — PL0 dispatches
a subagent to run it and waits. Expected gate output stays **0 entries**.

## Assertions (QA)

- [ ] Exactly 0 entries in `handoff.open_questions[]`.
- [ ] No numbered elicitation list in `## summary`.
- [ ] All four candidates appear in the plan as resolved facts, each naming its resolver.
- [ ] No candidate is dropped without a recorded answer.
