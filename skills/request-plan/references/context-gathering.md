# Context Gathering

The plan is only as good as the context behind it. Aim for **grounding, not exhaustiveness** — but
only in the sense SKILL.md gives it: *lean governs how much you read, never how hard you look*.
Over-reading burns budget and rarely changes the recommendation; under-searching changes which file
the plan is about, which is the more expensive of the two.

## Sources, in priority order

Read top-down. Where to stop is not decided here — see `SKILL.md § When you may stop searching`.

### Sources 1–3 — state, memory, git

1. **In-flight worktask state** — `.context/state.json` and the highest-N `.context/planning-*.md`:
   whether this request overlaps active work, and what was already decided. Skip if no `.context/`.
2. **Project memory** — root `MEMORY.md` plus the cross-conversation memory index if present:
   constraints, conventions, and decisions not visible in code.
3. **Recent git activity** — `git status` (work in progress) and `git log --oneline -15` (direction
   of travel, naming conventions, what shipped lately).

### Sources 4–5 — code and existing capabilities

4. **The code the request touches** — use the `Explore` agent for "where does X live / how is Y done
   here". Ask for the conclusion (files, patterns, reusable utilities), not a file dump. Read files
   directly only when you know the path and need specifics.
5. **Relevant skills/commands** — if the request resembles existing functionality, note the command
   or skill already covering part of it so the plan reuses rather than rebuilds.

## When to stop

**Single-sourced to `SKILL.md § When you may stop searching`.** This file states no termination
condition of its own, and no other file should either.

It used to state one, and that copy contradicted SKILL.md for a whole version: it let a search
end on the searcher's own sense that more reading would not help, which is the judgement a search
that never reached the owning file is least able to make. Two surfaces answering the stop question
differently is how a plan ends up confident and about the wrong module.

Ambiguity is § 1's question, not this file's: see `SKILL.md § Ask or plan`.

## Anti-patterns

- **Grep sweeps in place of Explore** — open-ended discovery is what `Explore` is for; it reads
  excerpts and returns the conclusion instead of pulling whole files into context.
- **Reading for completeness** — you are scoping one request, not auditing the codebase.
- **Planning before reading** — writing scope before looking at `.context/` or git is guessing.
