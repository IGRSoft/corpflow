# The trace review page — what it is and how to label with it

`evals/review/request-plan-0.3.0.html` is a self-contained labelling UI for the 0.3.0
capture. It holds **60 of the 201 captured responses** and exists to answer the one question
the harness cannot: *was this answer actually right?*

The harness verdict is a regex score. A human label is ground truth. Comparing the two is
what produces TPR, TNR and the Rogan–Gladen correction — without labels, a pass rate is
uncalibrated and means only what it literally counts.

## Why the page is not in git

It is **gitignored** (`.gitignore:28`, the whole `evals/review/` directory), along with the
`responses-*/` directories it embeds. This document lives at `evals/labelling.md` rather
than beside the page for exactly that reason — anything inside `evals/review/` is untracked
and does not survive a clone. Traces are
inlined rather than fetched because the page opens over `file://`, where fetching a sibling
JSON is blocked. That makes it a ~270 KB self-contained artifact.

Two consequences:

- **It is disposable.** Rebuild it any time (see § Rebuilding); nothing is lost.
- **Your labels are not in it.** They live in browser `localStorage` and must be exported
  deliberately. Closing the tab is safe; clearing site data is not.

`evals/review/` is also on `ANSWER_KEY_PATHS`, so `eval-capture.py` strips it from the
capture tree. A model being evaluated can never read it.

## Open it

```bash
open evals/review/request-plan-0.3.0.html
```

Any browser works. No server, no network, no build step.

## The labelling loop

Each trace shows the request, the rendered response, and — in the right sidebar — the case's
dimensions, its grounding files, what the harness said, and the deferred criteria that are
deliberately *not* graded.

| key | action |
|---|---|
| `→` / `←` | next / previous trace |
| `1` | **Pass** — mark and advance |
| `2` | **Fail** — mark and advance |
| `d` | **Defer** — mark and advance |
| `u` | Undo the last verdict |

### Working through it quickly

Marking auto-advances, so a run of clear passes is `1 1 1 1`. The header dropdown filters to
`unlabeled only`, `dev split`, `test split`, or `expected clarify` — the fastest path through
60 traces is to leave it on `unlabeled only` and hold `1`/`2`.

The note field is free text and saves as you type. The house style is **observations, not
explanations**: what the response did, quotable, so a later reader can re-derive the verdict
without reopening the trace. See `evals/labels/request-plan-0.2.0-human.jsonl` for the
register — each note names the concrete thing that decided it.

### `defer` is a real verdict, and it is dropped downstream

`label-align.py` reads only rows whose verdict is `pass` or `fail`. A `defer` row is
**silently excluded** from every rate it computes. That is correct — an undecided case
should not vote — but it means deferring is not free: it shrinks the denominator. Defer when
the case itself is ambiguous, not when the call is merely hard.

## Judge against the contract, not against taste

The rubric lives in `evals.json`'s `grading` field and is binding.

### The parts that decide the most labels

- **Structure is substance.** A substantively correct plan still **fails** if it drops the
  P0/P1/P2 phase model or the T-shirt-size + 0–25 complexity pair. Those are a machine
  interface — `milestone-helpers.sh` and `build-orchestrator.sh` parse the tier literally.
  Heading syntax is *not* covered: bold pseudo-headings are fine.
- **Routing follows the request, never the findings.** If the prompt names no credential,
  auth or secret surface, `--secure` is wrong even when the code turns out to touch one.
- **Already-ships, as narrowed at 0.1.0.** Stopping at "this already ships" is correct only
  when all three hold: the request asked to build/add/fix, the thing exists as asked, and
  nothing remains. A request to *find* or *use* an existing surface is a plan. A shipped
  headline with a live remainder is a refutation of the stale part **plus** a plan for the
  rest — that is the best answer, not a failure.

## Known trap in this capture

**Seven refute cases fail `disputes-the-premise` on a grader defect, not a model error** —
ids 17, 22, 59, 125, 210, 211, 212. The assertion enumerates verbs (`ship|land|split|exist|
done|…`) but "already" takes an open class, and this capture produced `converts`,
`anticipated`, `records`, `handles`, `runs`, `uses`, `named`, `scoped`, `stops`, `asserts`.

Label these **on the response, not on the harness column.** Case 212 states the calculator
converts hours to money, cites the function by file and line, runs the self-test, and stops
— a textbook refutation scored `FAIL`. Cases 22 and 59 may be genuine failures. Resolving
these seven is the highest-value part of this labelling pass: it decides whether the
assertion gets rewritten, and that decision must come from labels rather than from reading
the regex. See `evals/findings/request-plan-0.3.0.md § disputes-the-premise`.

## Export, then align

1. Click **Export**. A textarea appears at the top of the page, pre-selected, holding one
   JSON object per labelled case — already in the exact shape `label-align.py` reads.
2. Copy it into `evals/labels/request-plan-0.3.0-human.jsonl`.
3. Run the alignment:

```bash
# held-out TPR/TNR — the measurement batch 4 could not produce
python3 evals/scripts/label-align.py \
  --labels evals/labels/request-plan-0.3.0-human.jsonl \
  --grades <grades.json> --min-id 168

# weighted full-set rates and the Rogan-Gladen correction
python3 evals/scripts/label-align.py \
  --labels evals/labels/request-plan-0.3.0-human.jsonl \
  --grades <grades.json>
```

`--min-id 168` is load-bearing: ids 122–167 were read during 0.2.0 labelling and are no
longer held out. `<grades.json>` is `eval-grade.py --json` output over
`skills/request-plan/evals/responses-0.3.0` — regenerate it any time, it is free and
deterministic.

## Which 60, and why those

`evals/labels/request-plan-0.3.0-sample.json` records the draw (seed `20260826`):

| stratum | population | sampled | weight |
|---|--:|--:|--:|
| `dev/fail` | 17 | 17 | 1.00 |
| `dev/pass` | 69 | 25 | 2.76 |
| `test/held-out` | 18 | 18 | 1.00 |

The sample is **deliberately enriched toward harness failures** — that is where error types
concentrate. Consequently **the raw labelled count is not a corpus rate and must never be
quoted as one.** Only the stratum-weighted correction from `label-align.py` is comparable to
anything. The 0.2.0 findings doc says the same thing about its own 50-of-60.

## Rebuilding

```bash
python3 evals/scripts/eval-grade.py \
  --eval-set skills/request-plan/evals/evals.json \
  --responses skills/request-plan/evals/responses-0.3.0 --json > /tmp/grade-0.3.0.json

python3 evals/scripts/build-review-page.py \
  --eval-set skills/request-plan/evals/evals.json \
  --responses skills/request-plan/evals/responses-0.3.0 \
  --grades /tmp/grade-0.3.0.json \
  --only <(python3 -c "import json;print(json.dumps(json.load(open('evals/labels/request-plan-0.3.0-sample.json'))['case_ids']))") \
  --out evals/review/request-plan-0.3.0.html
```

Rebuilding **does not touch your labels** — they are keyed in `localStorage` on the eval-set
version (`request-plan-labels-0.3.0`), not on the file. Drop `--only` to page through all
201 traces instead of the 60-case sample.

### The version-scoped key matters

Browsers share one `localStorage` partition across all `file://` pages. An earlier
version-blind key let notes from a previous capture restore into a newer session: eight
notes came back naming assertions that capture never fired. Verdicts regenerated correctly
and only the free text was stale — the hard kind to notice. If you ever see a note that does
not match the trace in front of you, that is the failure mode returning.
