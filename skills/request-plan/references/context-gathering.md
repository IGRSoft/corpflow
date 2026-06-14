# Context Gathering

The plan is only as good as the context behind it. The goal here is **grounding, not exhaustiveness**:
read enough that the plan reflects this repo's reality, then stop. Over-reading burns budget and
rarely changes the recommendation.

## Sources, in priority order

Read top-down and stop early once the picture is clear enough to scope, phase, and size the work.

1. **In-flight worktask state** — `.context/state.json` and the latest `.context/planning-*.md`
   (highest N). Tells you whether this request overlaps active work, and what was already decided.
   Skip if `.context/` doesn't exist.
2. **Project memory** — `MEMORY.md` at the repo root, and the cross-conversation memory index if
   present. Surfaces constraints, conventions, and recent decisions not visible in code.
3. **Recent git activity** — `git status` (uncommitted work in progress) and `git log --oneline -15`
   (direction of travel, naming conventions, what shipped lately).
4. **The code the request touches** — use the `Explore` agent for "where does X live / how is Y done
   here" questions. Ask for the conclusion (files, patterns, existing utilities to reuse), not a file
   dump. Only read individual files directly when you already know the path and need specifics.
5. **Relevant skills/commands** — if the request resembles existing functionality, note the command
   or skill that already covers part of it so the plan can reuse rather than rebuild.

## When to stop

Stop gathering when the next read wouldn't change **scope, phases, or effort**. Concretely:

- You can name the files/areas that change and roughly how much.
- You know whether an existing utility or command already does part of the work.
- You can place the work on the T-shirt + complexity scale with a defensible range.

If after a reasonable pass the request is still ambiguous on outcome, that's a signal to ask the
user a clarifying question — not to keep reading.

## Anti-patterns

- **Grep sweeps in place of Explore** — open-ended discovery is what the `Explore` agent is for; it
  reads excerpts and returns the conclusion, which is cheaper than pulling whole files into context.
- **Reading for completeness** — you are not auditing the codebase, you are scoping one request.
- **Planning before reading** — if you find yourself writing scope before looking at `.context/` or
  git, you're guessing. Look first.
