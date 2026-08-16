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
- `label_id` — content hash of `(worktask_id, run_index, path, added, removed, summary)`; keys same-run idempotency, so a recurrence in a later worktask still counts
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
`skills/request-plan/evals/evals.json`). Every case is *specified* to be graded
by **binary, code-checked assertions** — no scales, no unvalidated judges.
Criteria that genuinely need interpretation are parked in each case's `deferred`
list rather than being graded badly.

**No case has yet been graded against model output.** What `./run-tests.sh`
executes is `tests/python/test_skill_evals.py` and
`tests/python/test_eval_capture.py` — unit tests of the assertion engine and the
capture tooling against injected dispatches, plus the lint that keeps every eval
set binary and code-checkable. **A green run means the sets are well-formed and
the tooling is correct; it is not a measurement of any skill's output quality.**

## Capture and grading

`scripts/` holds the loop. Capture costs money and needs a credential; grading is
free and offline.

```sh
evals/scripts/eval-capture.py --eval-set skills/request-plan/evals/evals.json --dry-run
evals/scripts/eval-capture.py --eval-set skills/request-plan/evals/evals.json --budget 1.00
evals/scripts/eval-grade.py   --eval-set skills/request-plan/evals/evals.json
```

- `eval-engine.py` — assertion engine + digests, shared by capture, grading, and
  the test suite so two scores of one response can never disagree.
- `eval-capture.py` — dispatches each case `prompt` through headless `claude -p`
  and writes `<eval-set-dir>/responses/<case_id>.json`. A failed or empty
  dispatch **raises and stores nothing**; a fabricated blank would be graded as a
  genuine skill failure.
- `eval-grade.py` — scores stored responses. Refuses (rc 2) when a record's
  `prompt_digest` no longer matches the eval set, since that response answers a
  question the set no longer asks. A moved `assertions_digest` is flagged, not
  refused — the response stands, only its score went stale.

`--mode` picks what is being measured: `command` (default) invokes the skill
explicitly and grades its output; `natural` sends the bare request and so also
grades whether the skill triggers at all.

### Isolating a session from this repo

`judge-traces.py` runs each judge in an **empty temp directory**, not in the repo.
That is the only isolation that held. Denying the built-in file tools was not
enough — an isolated probe reached the repo through a connected MCP server's own
`read_file`, and after MCP was stripped too, a run still recited an exact tracked
file census (`py=61 md=189`, both correct) with no tool call at all, because the
CLI injects working-directory context. Deny-lists chase channels; an empty `cwd`
removes the thing being read. A settings-file `permissions.deny` is weaker still:
under `bypassPermissions` it did not apply at all.

The regression test for this is a question whose answer can be checked — ask for
a file census and compare it against `git ls-files`.

### Three outcomes, not two

A response that asks a clarifying question instead of answering is reported as
`CLARIFY` and left out of the pass/fail denominator. The skill declined to
answer, so its output quality was never exercised — scoring that as a broken plan
is what made a correct refusal read as 0/2 on the first live run.

### Case lints

`tests/python/test_skill_evals.py` fails a set that would waste a capture:

| Lint | Rejects |
|---|---|
| `grounding` paths resolve | A case describing a surface this repo lacks — it can only ever be refused |
| No echoed assertion values | A value already in the case's own prompt, which rewards restatement over judgement |
| ≥2 case-specific assertions | Cases that only re-measure the shared template checks and cannot tell each other apart |

Captured responses are gitignored. A clone re-captures rather than inheriting
them, so every grade cites the `plugin_sha`, `model` and `skill_version` of the
run that actually produced it. The tradeoff is real: a grade is reproducible only
by paying for the capture again (~$1/case), so record the numbers that matter in
the commit or a findings doc rather than assuming the responses will be there.

### Splits

`evals/splits/<skill>.json` freezes tranche membership. A case **never** changes
tranche: stratifying on a dimension that later gets re-derived once reshuffled dev
and test after dev had been read, quietly moving examined cases into the held-out
set. Generation reads the manifest and stratifies only genuinely new cases.
Anything already examined stays in `dev` — something read cannot be un-read.
