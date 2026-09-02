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

Aggregate with `skills/self-improvement/scripts/label-stats.sh`. It reports
per-target and per-category counts, flags targets and categories at or above
`--min-count=<n>` (default 3), and prints progress toward the 100-row taxonomy
gate below. It reports only — acting on a repeat still goes through the human
approval gate on a Step 5 proposal.

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
free and offline. Human labelling — the step that turns a harness rate into a
calibrated one — has its own guide in [`labelling.md`](labelling.md).

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
  genuine skill failure. Dispatches run against an **isolated tree**, never the
  repo — see § The capture surface.
- `eval-grade.py` — scores stored responses. Refuses (rc 2) when a record's
  `prompt_digest` no longer matches the eval set, since that response answers a
  question the set no longer asks. A moved `assertions_digest` is flagged, not
  refused — the response stands, only its score went stale. It also refuses to
  average across two `skill_version`s unless `--allow-mixed` is passed.
- `build-review-page.py` → `label-align.py` — the human labelling loop. The review
  page exports JSONL to `labels/<skill>-<eval-set-version>-human.jsonl`;
  `label-align.py` scores the assertion harness against those labels and reports
  TPR/TNR plus the Rogan-Gladen correction. **Until a capture has been labelled the
  harness is uncalibrated, and no pass rate it prints is trustworthy.**

`--mode` picks what is being measured: `command` (default) invokes the skill
explicitly and grades its output; `natural` sends the bare request and so also
grades whether the skill triggers at all.

### The LLM judge is retired

`judge-traces.py` still exists and still runs, but nothing reads its verdicts.
Scored against human labels it returned **TNR 0%** — 0 of 26 known failures caught —
so `label-align.py` dropped its column. A grader that never says fail adds no
information to the harness it sits beside. Validating it again means measuring it on
labels it has not seen, per the taxonomy gate above; until then its output is not a
label. The script is kept for the isolation technique, which is the part that worked.

### The capture surface

Dispatches run in a detached worktree at HEAD with the answer key removed, pinned
with `--plugin-dir` and with the ambient marketplace copy disabled. Two separate
defects made that necessary, and neither was visible in a stored record.

**The plugin under test was not the tree under test.** Without `--plugin-dir` the
CLI resolves `/corpflow:<skill>` from the installed release while `skill_version()`
reads this repo, so a run could exercise one version and stamp another on every
record. Measured rather than argued — same prompt, same model, empty cwd:

| flags | `/corpflow:roadmap` | `/corpflow:cost-report` |
|---|---|---|
| none (what 0.0.1 used) | no | **yes** |
| `--plugin-dir` + ambient disabled | **yes** | no |

`roadmap` ships only in this tree; `cost-report` only in the installed 4.0.25. The
un-isolated capture really was answered by the published release.

**The answer key was inside the searched tree.** `evals.json` carries
`expected_outcome`, and 7 of 114 responses in the 0.0.1 capture reached the corpus.
The strip is the answer key, not the directory: cases ground on
`evals/scripts/*.py`, so removing all of `evals/` would make them unanswerable and
score the strip as a skill failure. A worktree rather than a copy, because it
excludes gitignored material by construction — `.context/` held a per-trace map of
every known failure, and the prompt-leak lint sweeps `git ls-files --others`, so it
could never have seen it.

#### Ask for the enumeration, not a yes/no

Two refusals guard the spend: a dirty tree, and a probe dispatch whose enumeration
of available commands must match the tree's exactly.

Asked whether one deleted command was available, the model answered `yes`; asked to
list its commands moments later it produced exactly the tree's 28, without that one.
A set can be checked against the tree; a judgement cannot. The version question is
worse than useless — the model answers it by reading `SKILL.md` out of the working
directory, so it reports the tree's version whether or not the pin bound.

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

### Asking is an answer, and it can be the wrong one

A response that asks a clarifying question instead of planning is graded against
the case's `expected_outcome`: a pass where the case wanted a question, a failure
where it wanted a plan. Both are inside the denominator.

An earlier version left every unexpected question **out** of the denominator, on
the reasoning that the skill declined to answer so its plan quality was never
exercised. That was wrong once cases carried `expected_outcome`, and it cost a
whole defect class: 9 of 32 human-labelled failures were plans the skill should
have written and didn't, and the grader reported all 9 as unscored. The headline
was computed over 87 cases and read as healthier than the skill was. Failures
that leave the denominator are worse than failures that stay in it — a metric
cannot report what it has excused.

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

### Baseline 0.0.1

The corpus was reset to a **0.0.1 baseline** on 2026-08-23. Everything the reset
deleted — labels, judgements, findings, captured responses — described a case set
that had since been repaired and a skill at three different versions, so no number
from it can be compared against a number taken after it. `SKILL.md` `version:` and
`evals.json` `eval_set_version` both read `0.0.1` **at the baseline**, and the rule is
that they move together — not that they stay at `0.0.1`. Both are `0.2.0` today: 0.1.0
shipped in PR #325 and 0.2.0 on 2026-08-26. `0.0.1` names the last **captured** state,
which is what a number is compared against; the pair names the current **spec**. When
they disagree, the spec versions are wrong, not this paragraph.

**Three spec versions are unmeasured and a capture cannot separate them.** 0.1.0
shipped with no capture; the 4.0.26 command-surface reorganization then changed the
tree `eval-capture.py` reads (seven commands removed, five renamed, eight groundings
repointed); 0.2.0 stacks on both. Any future number is a delta against that whole
stack.

**0.0.1 is retired as a comparison point.** It was captured without `--plugin-dir`,
so the installed release answered and its records cannot say which skill version
actually ran — the `0.0.1` they carry describes a file in the repo, not the plugin
that produced the response. Its *labels* remain sound and are still the reference
for what a human verdict looks like; its *rates* measure an unknown version. The
next capture is a fresh baseline, and no delta against 81% should be quoted.

What the reset does **not** do is make the cases unread. Every case in 0.0.1
predates it, so the `test` tranche in `splits/request-plan.json` is nominal rather
than held out for those ids. Ids 122+ were written after the manifest and pinned to a
tranche before any capture read them — those are the first genuinely held-out cases
this corpus has had.

The two subsections below are the rules that produced the reset; they still govern.

### Rubric changes and labels that predate them

A labelling rubric is part of the measurement instrument, so changing one raises the
question of what happens to labels made before it existed. Two kinds, and they are handled
oppositely.

A rubric decision that **resolves an inconsistency the labels themselves already recorded**
— two same-shaped responses labelled oppositely, or a note saying "the rubric needs a rule
for X" — is a clarification of what correct always meant. Apply it to **every** capture and
every case it touches, in one change, with: a dated bracket note in each flipped label
naming the rule; recomputed headline numbers in every findings doc that cited the old
labels; and the harness re-calibrated (TPR/TNR) against the new labels. Applying a
clarification only to the newest capture is what corrupts the corpus — it asserts both
shapes are correct at once and makes grader agreement meaningless.

A rubric decision that **changes what behaviour is desirable** is a spec change, belongs in
a `SKILL.md` version bump, and applies only from that version's capture forward. Old
responses were correct answers to the old contract; relabelling them fails the skill for
obeying its own prompt.

The test for which kind you have: **did any contemporaneous label already treat the new
rule's shape as correct?** If yes it is a clarification. Both rubrics decided on 2026-08-23
passed that test, and both are recorded in `evals.json`'s `grading` field, which survived
the reset because a labelling contract is not a result.

One thing a clarification cannot repair: a case whose *premise* changed between captures.
Where the work asked for has since shipped, the two columns measure different ground truth
and cannot be compared at all — which is why 0.0.1 converts those cases to `refute` and
retires the ones whose premise was never true, rather than footnoting them. See
`gen-request-plan-cases.py`'s `REFUTED_PREMISE` and `RETIRED` tables. Both go stale the
same way: a premise that becomes true again has to come back off the list.

### Splits

`evals/splits/<skill>.json` freezes tranche membership. A case **never** changes
tranche: stratifying on a dimension that later gets re-derived once reshuffled dev
and test after dev had been read, quietly moving examined cases into the held-out
set. Generation reads the manifest and stratifies only genuinely new cases.
Anything already examined stays in `dev` — something read cannot be un-read.

The 0.0.1 reset re-stratified the whole set once, deliberately, behind
`gen-request-plan-cases.py --restratify`. Without that flag a missing or unreadable
manifest is now a hard error rather than a silent full reshuffle, which is how the
rule above was breached the first time. Re-stratifying does not un-read anything: see
the manifest's own `note`.
