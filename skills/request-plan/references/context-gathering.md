# Context Gathering

Aim for grounding, not exhaustiveness — in the sense SKILL.md gives it: *lean governs how much you
read, never how hard you look*. You are scoping one request, not auditing the codebase; but
under-searching changes which file the plan is about, which costs more than over-reading.

## Sources, in priority order

Read top-down, and read before writing any scope.

### Sources 1–3 — state, memory, git

1. **In-flight worktask state** — `.context/state.json` and the highest-N `.context/planning-*.md`:
   whether this request overlaps active work, and what was already decided. Skip if no `.context/`.
2. **Project memory** — root `MEMORY.md` plus the cross-conversation memory index if present:
   constraints, conventions, and decisions not visible in code.
3. **Recent git activity** — `git status` (work in progress) and `git log --oneline -15` (direction
   of travel, naming conventions, what shipped lately).

### Sources 4–5 — code and existing capabilities

4. **The code the request touches** — use the `Explore` agent for "where does X live / how is Y done
   here"; it reads excerpts and returns the conclusion (files, patterns, reusable utilities) instead
   of pulling whole files into context. Read files directly only when you know the path and need
   specifics.
5. **Relevant skills/commands** — if the request resembles existing functionality, note the command
   or skill already covering part of it so the plan reuses rather than rebuilds.

## When to stop

Single-sourced to `SKILL.md § When you may stop searching`; this file states no termination
condition of its own. Ambiguity is § 1's question: see `SKILL.md § Ask or plan`.
