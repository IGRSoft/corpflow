---
name: writing-style
---

# Writing Style

Prose rules derived from ASD-STE100 (Simplified Technical English), applied at about 80%: the
core writing rules, without the approved-dictionary constraint. The goal is text that a reader
parses once, with no second pass.

## Scope

| Applies to | Does not apply to |
|---|---|
| Chat replies to the user | Source comments → `skills/shared/code-documentation.md` |
| Stage handoffs and final returns | Agent, command and skill prompt bodies → `agents/prompt-engineer.md` doctrine |
| Reports, findings, reviews | Quoted text, logs, tool output |
| README, ADR, API docs, PR bodies, release notes | Commit subjects → `skills/shared/git-conventions.md` |
| Plans and `.context/` artifacts | |

## Core rules

### Sentences and steps

1. Write one topic per sentence. A procedural sentence has 20 words or fewer; a descriptive
   sentence has 25 words or fewer.
2. Write one topic per paragraph, with 6 sentences or fewer.
3. Use the active voice. Name the actor: "The hook blocks the commit", not "The commit is blocked".
4. Write each step as an imperative, with one action per step, in execution order.
5. Put a condition first: "If the build fails, read the log."
6. Put a warning or a precondition before the step it applies to, never after it.

### Words and terms

7. Keep the articles (a, an, the) and the connecting words. Do not write telegraph style.
8. Use one word for one meaning. Use the same term for the same thing every time. Do not use
   synonyms for variety.
9. Use simple verb tenses: present, simple past and future. Do not stack more than 3 nouns
   ("worktask stage handoff budget" → "the token budget for a stage handoff").
10. Do not use idioms, slang, metaphors or filler. "In order to" → "to"; "basically",
    "actually" and "just" add nothing.
11. Write technical names (APIs, flags, paths, error text) exactly as they are. They are exempt
    from these rules.

## Relaxations

These keep the text natural where full STE is too stiff:

- No approved-dictionary limit. Use the plain word that is correct.
- Contractions are allowed in chat replies.
- A descriptive sentence can be longer when a split would separate a cause from its effect.

## Visual over prose

Choose the form from the shape of the content:

| Content | Form |
|---|---|
| Two or more options compared on the same attributes | Table |
| A sequence of actions | Numbered list |
| Flow, state machine or architecture with 3 or more interacting parts | Mermaid or ASCII diagram |
| Rationale, a trade-off, a judgement | Prose |

## Before → after

Chat reply:

- Before: "Fixed. Gate broke on null ctx, patched guard, tests green."
- After: "I fixed the gate. It failed when the context was null, so the guard now checks for null.
  The scoped tests pass."

Handoff line:

- Before: "Decided to go with DI approach basically since it seemed cleaner overall."
- After: "Use dependency injection for ThemeManager. It removes the global singleton."

README step:

- Before: "The config file should be copied and then the token, which is required, can be added."
- After: "1. Copy `config.example.json` to `config.json`. 2. Add your API token to `token`."
