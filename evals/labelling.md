# Human labelling — the trace review page and the loop around it

`build-review-page.py` emits a self-contained HTML labelling UI over a capture's stored
responses. It exists to answer the one question the harness cannot: *was this answer
actually right?*

A harness verdict is a regex score. A human label is ground truth. Aligning the two is what
produces TPR, TNR and the Rogan–Gladen correction. Without labels a pass rate is
**uncalibrated** and means only what it literally counts — never quote one as a quality
figure.

Throughout, `<skill>` is the eval set's skill (today: `request-plan`) and `<version>` its
`eval_set_version`.

## Where things live

| what | path |
|---|---|
| eval set | `skills/<skill>/evals/evals.json` |
| captured responses | `skills/<skill>/evals/responses-<version>/` |
| review page | `evals/review/<skill>-<version>.html` |
| the draw that chose the sample | `evals/labels/<skill>-<version>-sample.json` |
| exported labels | `evals/labels/<skill>-<version>-human.jsonl` |
| what the capture measured | `evals/findings/<skill>-<version>.md` |

## Why the page is not in git

`.gitignore:28` ignores the whole of `evals/review/`, as it does the `responses-*/`
directories the page embeds. This document sits at `evals/labelling.md` rather than beside
the page for that reason — anything under `evals/review/` is untracked and does not survive
a clone.

Traces are inlined rather than fetched because the page opens over `file://`, where fetching
a sibling JSON is blocked. Expect a few hundred KB.

- **The page is disposable.** Rebuild it any time; nothing is lost.
- **Your labels are not in it.** They live in browser `localStorage` and must be exported
  deliberately. Closing the tab is safe; clearing site data is not.

`evals/review/` is also on `ANSWER_KEY_PATHS`, so `eval-capture.py` strips it from the
capture tree. A model under evaluation can never read it.

## The loop

Open the file in any browser — no server, no network, no build step.

Each trace shows the request, the rendered response, and in the sidebar: the case's
dimensions, its grounding files, what the harness said, and the `deferred` criteria that are
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
`unlabeled only`, `dev split`, `test split` or `expected clarify`; the fastest path is to
leave it on `unlabeled only` and hold `1`/`2`.

The note field is free text and saves as you type. House style is **observations, not
explanations** — what the response did, quotably, so a later reader can re-derive the verdict
without reopening the trace. Any `evals/labels/*-human.jsonl` shows the register: each note
names the concrete thing that decided it.

### `defer` is a real verdict, and it is dropped downstream

`label-align.py` reads only rows whose verdict is `pass` or `fail`. A `defer` row is
**silently excluded** from every rate it computes. That is correct — an undecided case should
not vote — but deferring is not free: it shrinks the denominator. Defer when the *case* is
ambiguous, not when the call is merely hard.

## Judge against the contract, not against taste

The binding rubric is the `grading` field of that eval set's `evals.json`. Read it before
labelling; it is appended to, capture by capture, and later entries supersede earlier ones.

### What to check in it

- **Which structural fields are load-bearing.** Some are a machine interface, not
  formatting: a substantively correct answer still fails when it drops one. The `grading`
  field names them and says which downstream script parses them.
- **What ground truth follows from.** Typically the *request*, never what investigation later
  reveals — otherwise the same prompt is gradeable two ways depending on what a search found.
- **Which spec version applies.** A rubric decision applies from its stated version forward.
  Labels taken under an older contract are **not** re-flipped against a newer one; those
  responses were correct answers to the rule in force.
- **What is deliberately ungraded.** The sidebar's `deferred` list is criteria that need a
  judge. Do not fail a response for one of them.

## Check the findings doc for capture-specific traps

Before labelling, read `evals/findings/<skill>-<version>.md`. A capture usually turns up at
least one place where **the harness is wrong and the response is right**, and those cases
are the highest-value part of a labelling pass: they decide whether an assertion gets
rewritten, and that decision must come from labels rather than from reading the regex.

When the findings doc names such a mode, **label on the response, not on the harness
column.**

> **Worked example, `request-plan` 0.3.0.** Seven refute cases fail `disputes-the-premise`
> on a grader defect: the assertion enumerates verbs, but the "already <verb>" construction
> it is trying to catch takes an open class. One response cites its evidence by file and
> line, runs the script's self-test, and stops — a textbook refutation, scored `FAIL`. Two
> others in the same set may be genuine failures. Only labels separate them.

## Export, then align

1. Click **Export**. A pre-selected textarea appears at the top of the page with one JSON
   object per labelled case — already in the exact shape `label-align.py` reads.
2. Copy it into `evals/labels/<skill>-<version>-human.jsonl`.
3. Align, twice:

```sh
# held-out TPR/TNR only
python3 evals/scripts/label-align.py \
  --labels evals/labels/<skill>-<version>-human.jsonl \
  --grades <grades.json> --min-id <first-held-out-id>

# weighted full-set rates and the Rogan-Gladen correction
python3 evals/scripts/label-align.py \
  --labels evals/labels/<skill>-<version>-human.jsonl \
  --grades <grades.json>
```

`<grades.json>` is `eval-grade.py --json` output over the same responses directory —
regenerate it freely, it is offline and deterministic.

### `--min-id` is load-bearing, and its default goes stale

Held-out means *never read*. Once a tranche has been labelled it is spent, and the floor
moves to the first id of its successor. `--min-id` and `sample-for-labelling.py
--held-out-from` both carry a hardcoded default that was correct for one past cycle
(`DEFAULT_HELD_OUT_FROM = 122`) and silently re-samples spent cases afterwards. **Pass the
value explicitly** and take it from the current `-sample.json`, not from the default or the
help text.

## Which cases, and why those

`evals/labels/<skill>-<version>-sample.json` records the draw — seed, strata, populations
and the chosen ids. `sample-for-labelling.py --out` writes only a bare id list, so this
richer file is written by hand; without it, *which* sample produced a rate is
unreconstructable.

The sample is **deliberately enriched toward harness failures**, because that is where error
types concentrate. Two consequences:

- **The raw labelled count is not a corpus rate** and must never be quoted as one. Only the
  stratum-weighted correction from `label-align.py` compares to anything.
- **Take the held-out tranche whole.** Sampling within it wastes the one-shot measurement.

## Rebuilding the page

```sh
python3 evals/scripts/eval-grade.py \
  --eval-set skills/<skill>/evals/evals.json \
  --responses skills/<skill>/evals/responses-<version> --json > /tmp/grades.json

python3 evals/scripts/build-review-page.py \
  --eval-set skills/<skill>/evals/evals.json \
  --responses skills/<skill>/evals/responses-<version> \
  --grades /tmp/grades.json \
  --only <ids.json> \
  --out evals/review/<skill>-<version>.html
```

`--only` takes a JSON array of case ids — the `case_ids` field of the `-sample.json`. Drop it
to page through every captured trace instead of the sample.

Rebuilding **does not touch your labels**: they are keyed in `localStorage`, not in the file.

## The tooling is currently single-skill

`build-review-page.py` hardcodes `request-plan` in four places — the page title, the `<h1>`,
the `--eval-set` and `--out` defaults, and, most consequentially, the storage key:

```js
const KEY = 'request-plan-labels-__EVAL_SET_VERSION__';
```

The key is scoped by **eval-set version but not by skill**. Only one eval set exists today
(`skills/request-plan/`), so nothing collides. The moment a second one is added, two skills
sharing an `eval_set_version` would share one label store — and browsers keep a single
`localStorage` partition across all `file://` pages, so the collision is silent. Fix the key
before adding a second eval set, not after.

### Why the key is versioned at all

A version-blind key once restored notes from an older capture into a newer session: eight
came back naming assertions that capture never fired. Verdicts regenerated correctly and only
the free text was stale, which is the hard kind to notice. If a note ever does not match the
trace in front of you, that is this failure mode returning.
