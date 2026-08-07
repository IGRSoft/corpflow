# evals/

Evaluation data for the plugin's own output quality — as opposed to `benchmark/`,
which measures cost and process.

## `failure-labels.jsonl`

Append-only, committed dataset of user edits made **after** an agent delivered.
Written by `skills/self-improvement` Step 5b on every ST completion (and by
`/improve-yourself`). A user correcting delivered work is a domain-expert failure
label — the signal most eval systems pay annotators for.

One row per kept, classified change:

```json
{"ts":"2026-08-07T05:00:00Z","worktask_id":"wt-42","run_index":0,"stage":"ST",
 "path":"agents/developer.md","target":"agents/developer.md",
 "category":"completeness","confidence":"high","lines_added":4,"lines_removed":1,
 "summary":"added Swift 6 strict-concurrency constraint","label_id":"a1b2c3d4e5f60718"}
```

- `category` — one of the six in `skills/self-improvement/SKILL.md § Step 3`
- `label_id` — content hash of `(path, added, removed, summary)`; keys idempotency
- **No diff bodies are ever stored** — counts and a redacted one-line summary only
- Opt out with `SELF_IMPROVE_LABELS=0`

Aggregate with `skills/self-improvement/scripts/label-stats.sh`.

## `failure-taxonomy.md` (not yet written)

The open-coded failure taxonomy, built by reading real output — not by
brainstorming category names. Blocked until there is material to read:

1. **Oracle failures** — one live benchmark run with the scripted-CLI contract in
   place (`benchmark/README.md § Held-out oracle`), which yields per-case
   `failures[]` naming what the generated app got wrong.
2. **Label rows** — roughly 100 rows in `failure-labels.jsonl`, i.e. Step 5b
   running across a number of real worktasks.

Until both exist, writing a taxonomy would mean inventing categories rather than
observing them, which is the failure this directory exists to avoid. Build it
with the `evals-skills:error-analysis` skill once the inputs are there, then
reconcile it against the six existing self-improvement categories rather than
forking a second vocabulary.

**Do not build LLM judges before that taxonomy exists.** If it surfaces failure
modes code cannot check, add judges then — with TPR/TNR measured on a held-out
split (`evals-skills:validate-evaluator`), never on the few-shot examples.

## Skill eval sets

Per-skill eval sets live next to their skill (e.g.
`skills/request-plan/evals/evals.json`). Every case is graded by **binary,
code-checked assertions** — no scales, no unvalidated judges. The assertion
engine, grading, and the lint that keeps eval sets code-checkable live in
`tests/python/test_skill_evals.py` and run offline as part of `./run-tests.sh`.
Criteria that genuinely need interpretation are parked in each case's `deferred`
list rather than being graded badly.
