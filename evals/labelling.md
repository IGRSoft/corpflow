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
excluded from every rate it computes. That is correct — an undecided case should not vote —
but deferring is not free: it shrinks the denominator, and the survivors are weighted up to
cover the case that dropped out, which holds only if defers are missing at random.

It is no longer *silent*. The row is still counted as **drawn**, so the draw and the labels
still reconcile, and the stratum line prints the gap (`sampled 17 of 18 ... (1 deferred)`).
Before that, one defer in a tranche taken whole looked identical to the draw and the labels
disagreeing about what was sampled. Defer when the *case* is ambiguous, not when the call is
merely hard.

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
# held-out TPR/TNR only — select the STRATUM, not an id range
python3 evals/scripts/label-align.py \
  --labels evals/labels/<skill>-<version>-human.jsonl \
  --sample evals/labels/<skill>-<version>-sample.json \
  --grades <grades.json> --stratum test/held-out

# weighted full-set rates and the Rogan-Gladen correction
python3 evals/scripts/label-align.py \
  --labels evals/labels/<skill>-<version>-human.jsonl \
  --sample evals/labels/<skill>-<version>-sample.json \
  --grades <grades.json>
```

**`--sample` is not optional in practice.** Without it the populations are
reconstructed from the current grade set, which can only recover the *frame* and
never the *draw*: any case that flipped since the draw was cut now sits in a
different stratum than the one it was sampled from. With it, the tool checks its own
per-stratum counts against the draw and exits 65 on a mismatch rather than dividing
out a sampling fraction nobody took. `evals/README.md § The weights belong to the
draw` has the full account of what this replaced.

Pass `--p-obs <rate>` when the responses are gone. They are gitignored, so a clone
cannot regenerate `<grades.json>` without paying for the capture again — the rate
recorded in the findings doc is the only thing left, and this flag is how a
published corrected number stays re-derivable from what git holds.

`<grades.json>` is `eval-grade.py --json` output over the same responses directory —
regenerate it freely, it is offline and deterministic.

### `--stratum` selects the tranche; `--min-id` does not

An id floor and the held-out tranche are different sets. A batch seeds `dev`, `test`
and `train` cases across one id range, so `--min-id 168` over batch 5 also selects
the 12 labelled **dev** cases the draw counted in `dev/pass` and `dev/fail`.
`--split test --min-id 168` happens to be exact for that batch; `--stratum
test/held-out` is exact by construction and needs no floor at the call site, because
the draw records its own.

The floor itself is still load-bearing for the *sampler*, and it still moves:

### `--min-id` is load-bearing for the sampler, and the floor moves

Held-out means *never read*. Once a tranche has been labelled it is spent, and the floor
moves to the first id of its successor. One place records it: `held_out_from` in
`evals/splits/request-plan.json`. `sample-for-labelling.py --held-out-from` defaults to
that value and refuses to run when the key is missing rather than falling back to a
literal; `label-align.py --min-id` has no default, so **pass it explicitly**.

**The key is pinned to 213 right now, the first id of batch 6.** The 0.3.0 pass spent batch
5 (ids 168-212) whole, so no id below 213 is held out any longer; batch 6 (ids 213-270) was
appended and pinned in the same edit, before any capture read it. Read the floor from the
manifest, never from the newest `-sample.json`, whose `--min-id` names the tranche the last
pass just spent -- 168, not 213.

Pin `held_out_from` in the edit that appends a batch and delete it in the pass that spends
one. A floor left pointing at a spent tranche re-samples read cases and labels the result
held-out, which nothing downstream can detect.

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
- **Quote TNR with the number of human negatives beside it.** TNR is the rate the
  enrichment exists to protect and it is always the thinner of the two: 0.3.0 reads
  100% on **13** labelled failures, and its held-out row reads 100% on **one**.
  `label-align.py` prints its own warning under 20 labels and the matrix it prints
  above that line carries the counts — a TNR copied out without them reads as the
  strongest claim in the document when it is the weakest.

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

## The tooling reads the eval set's own name

`build-review-page.py` derives the page title, the `<h1>` and the storage key from the eval
set's `skill_name`:

```js
const KEY = '__SKILL_NAME__-labels-__EVAL_SET_VERSION__';
```

The key used to be scoped by **eval-set version but not by skill**, which was safe only
while one eval set existed. Two skills sharing an `eval_set_version` would have shared one
label store, and because browsers keep a single `localStorage` partition across all `file://`
pages the collision would have been silent — the same class of failure as the version-blind
key below, with no symptom to notice. Both dimensions are now in the key.

Only `--eval-set` and `--out` still default to `request-plan` paths. Those are defaults, not
scoping: a second eval set overrides them and gets its own store.

### Why the key is versioned at all

A version-blind key once restored notes from an older capture into a newer session: eight
came back naming assertions that capture never fired. Verdicts regenerated correctly and only
the free text was stale, which is the hard kind to notice. If a note ever does not match the
trace in front of you, that is this failure mode returning.
