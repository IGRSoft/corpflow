# Context Gathering

The plan is only as good as the context behind it. Aim for **grounding, not exhaustiveness**: read
enough that the plan reflects this repo's reality, then stop. Over-reading burns budget and rarely
changes the recommendation.

## Sources, in priority order

Read top-down; stop early once the picture supports scoping, phasing, and sizing.

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

Stop when the next read wouldn't change **scope, phases, or effort** — concretely, when you can name
the files/areas that change and roughly how much, know whether an existing utility or command
already does part of the work, and can place the work on the T-shirt + complexity scale with a
defensible range.

If the request is still ambiguous on outcome after a reasonable pass, that is a signal to ask a
clarifying question — not to keep reading.

## Anti-patterns

- **Grep sweeps in place of Explore** — open-ended discovery is what `Explore` is for; it reads
  excerpts and returns the conclusion instead of pulling whole files into context.
- **Reading for completeness** — you are scoping one request, not auditing the codebase.
- **Planning before reading** — writing scope before looking at `.context/` or git is guessing.
