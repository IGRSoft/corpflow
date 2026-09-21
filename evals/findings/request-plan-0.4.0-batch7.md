# request-plan — batch 7, the first out-of-sample rate since batch 4

**Corrected 69%, 95% CI [61%, 82%]** (TPR 83%, TNR 100%, n=36 labelled of 45 captured).

This is the first number this corpus has produced against a tranche **written and pinned
before any capture read it** since batches 4, 5 and 6 were each spent by a labelling pass.
`held_out_from` was absent when batch 7 was written; it is pinned at 271 now.

## Provenance

| | |
|---|---|
| eval set | 304 cases, `eval_set_version` 0.4.0; batch 7 is ids 271-315 |
| captured | 45 of 45, `plugin_sha` 954783e, `skill_version` 0.4.0, model claude-sonnet-5 |
| spend | **$39.20** ($0.87/case) |
| labelled | 36 of 36 in the frame — 18 `test`/held-out whole, 11 `dev`/pass, 7 `dev`/fail |
| draw | every stratum sampled at 1.00, so there is no sampling error to correct |

Harness observed 26/45 = 58%. Corrected against the labels: **69% [61%, 82%]**.

**Do not read 69% as a decline from 0.4.0's 85%.** Different tranche, and a deliberately
harder cell mix: batch 7 is 30 `buried` / 15 `absent` with **zero** `obvious` and zero
`adjacent`, where the 259-case corpus carries 40 `obvious` and 44 `adjacent`. The cell was
chosen to yield failures and it did. A lower rate on a harder tranche is the design working,
not a regression, and the two are not comparable without re-weighting.

One caveat the tool prints and this document keeps: TPR/TNR are estimated on the 36-case
frame and applied to a `p_obs` over 45, so the correction extrapolates past what was sampled.

## The harness is over-strict, never lenient — third independent confirmation

**Zero false passes.** All 12 human failures were caught. Four of 24 human passes were
scored as failures: **283, 287, 288, 296**.

That is the same direction measured at 0.0.1 and again at 0.4.0 (18 human failures, all
caught, zero false negatives). Three separate label sets now agree, so it is a property of
the assertion design rather than an artifact of one draw: **every repair the labels justify
subtracts failures at no cost in recall.**

The four split into two causes, and they are not the same kind of problem.

### Two are a grader defect: `finds-the-real-surface` only matches literal paths

**287** names the fixture pair by brace expansion —
`tests/fixtures/hooks/dv-screenshot-gate-{developer,nondeveloper}.payload.json` — and
**288** names it by glob — `tests/fixtures/hooks/dv-screenshot-gate-*.payload.json`. Both
then quote the file *contents* (287: the pair "differ by two fields (`agent_type` and
`agent_id`), not the single field the request describes"), so these are content claims, not
gestures. `surface_tokens` emits the literal relative path, basename and hyphenated stem;
none of those substring-match a brace or glob form, so the assertion fails on responses that
demonstrably read the file.

This is fixable and worth fixing, **carefully**: TNR is 100% today and a looser matcher is
exactly how that gets lost. The narrow repair is to accept a brace/glob spelling of the
declared path, not to relax the token set.

### Two are my own case-authoring defect: the premise does not hold

**283** and **296** are cases I wrote asserting a verification gap that does not exist.

- **296** asserts the scanner lacks a negative fixture — a clean input proving it stays
  silent. The response reproduced `tests/fixtures/skills/scan-secrets/clean.env` in full
  *and* the test that consumes it (`scan-secrets.bats:33-40`, with
  `assert_success` plus `refute_output --partial "Critical"/"High"`), then showed
  `run-tests.sh` globs it into the required CI suite.
- **283** claims "only a sample says so" about the title-chain fallback. The response showed
  the behaviour ships (`publish-pl-issue.sh:816-824,979-987` emitting a non-blocking audit
  row), that a self-test drives the real code path against that fixture, and then **ran the
  suite**: `pass=44 fail=0`.

In both the grounding file disproves its own premise, so refusing to plan is correct and the
harness scoring `asked-instead-of-planning` is measuring the case, not the skill. **Expected
outcome for both should be `refute`.**

This is the batch-7 analogue of the template cascade found at 0.4.0, and it lands the same
way: the fix belongs in the generator's `REFUTED_PREMISE` table, not hand-edited into
`evals.json`, which is regenerated wholesale. Two of 30 buried cases is a 6.7% false-premise
rate — worth recording as the cost of authoring prompts from a "verification gap" template
without executing the check first.

## `routes-to-secure-tier` is a real skill finding, not a grader artifact

Four of seven `secure` cases failed the same assertion — **273, 282, 294, 297** — and the
labels confirm three of four as genuine. The pattern is identical across them: the response
reasons about the tier from **what the fix touches** rather than from **what the request
names**.

- **294**: "no credential, untrusted-input, or live-failure surface named by the request" —
  on a request whose first clause names an embedded private key.
- **273**: "this does not name a credential/PII/payment asset" — on a request whose opening
  clause is a rejected-credential failure.
- **297**: argues from the fixtures ("the fixtures use synthetic fake values already") rather
  than from a request naming a secret scanner and its severity classes.
- **282** is the weakest of the four and flagged as such: it turns on asset hosting and
  egress rather than a named secret, so it is the one a reasonable reader could defend.

The 0.3.0 label set already records the convention — route `--secure` off the request's own
credential framing, not off findings. This is the first time it has been measured at volume,
and 4-of-7 on a single assertion is the strongest single-cause signal in the batch.

## The `buried` fixture cell worked

17 of 30 `buried` cases produced harness failures (43% pass), against `absent` at 13/15 (86%).
Batch 5's `buried` yield was 25%. The cell was picked because `capability-registry.sh`
enumerates neither `tests/` nor `skills/*/references/`, so a plan must read the tree to reach
these surfaces — and the misses are concentrated exactly there: **272, 278, 284, 289, 291,
292, 294** all land on a plausible neighbouring surface and plan competently on the wrong
file. **291** is the sharpest instance: it never opens the designated fixture yet produces the
best finding in the batch (the `cc_classify_section` promotion table is documented wrong).

That failure shape — good work, wrong file — is what this cell was built to expose.

## Both repairs were applied after this calibration — 2026-09-11

**Every harness number above this heading is the pre-repair grader, and stays that way.**
The 69% [61%, 82%] describes the capture as graded then, and
`request-plan-0.4.0-batch7-verdicts.jsonl` records the per-case verdicts it was computed
from. Neither is updated.

1. **283 and 296 registered in `REFUTED_PREMISE`** (`shipped` kind), against the evidence
   above and re-verified before writing: `scan-secrets.bats:33` consumes `clean.env` with
   `refute_output`, and `publish-pl-issue.sh:816-824` tracks the title source down to the
   worktask-id rank. The corpus is now 201 plan / 60 clarify / 43 refute.
2. **`surface_tokens` gained a path-qualified prefix token** so a sibling-set file named by
   glob or brace expansion matches its own assertion. Path-qualified deliberately: the bare
   stem is what leaks, and `hooks/dv-screenshot-gate.sh` must not satisfy a fixture assertion.
3. **`routes-to-secure-tier` untouched.** It measures real skill behaviour, three of four
   confirmed by hand.

Re-grading moves exactly the four labelled false failures — 283, 287, 288, 296 — and nothing
else. Against the same 36 labels the repaired grader reaches **TPR 100% / TNR 100%**, and the
observed rate is **30/45 = 67%**.

**That 100% is in-sample and is not a headline.** It is measured on the labels that motivated
the repairs, so it is a consistency check — the same shape as the post-repair figure at 0.4.0.
The out-of-sample number for batch 7 remains the pre-repair **69% [61%, 82%]**. A repaired
grader earns a new rate only against labels it has not seen.

One repair carries a real cost worth naming: the prefix token makes two members of a sibling
set mutually satisfiable, so naming `dv-screenshot-gate-nondeveloper` now satisfies the
assertion for `-developer`. That is correct for 287/288, which had read both, and wrong in
principle. It survived the guard — TNR stayed 100% across all 36 labels — but it is the
loosest thing in the assertion set and the first place to look if a false pass ever appears.


## The secure-tier fix is not measurable at this n — 2026-09-11

`estimation-methodology` 0.4.0 (`a54c455`) added the missing de-escalation guard, and batch 7
was re-captured against it: 35 of 45 cases, `plugin_sha` a54c455, **$32.37**, stopped at the
$200 ceiling with the last 10 `absent`/clarify cases unbought. Both sets graded by the same
repaired grader, so the grader repair cannot be mistaken for a skill change.

| | before (954783e) | after (a54c455) |
|---|---|---|
| `routes-to-secure-tier` failures | 4 of 7 | **3 of 7** |
| secure cell pass | 2/7 | 3/7 |
| overall | 20/35 | 22/35 |

**One case moved, and that is inside the noise.** 294 — the case whose reasoning motivated the
fix — now routes `--secure`. 273, 282 and 297 still do not. Meanwhile **12 of 35 cases changed
status, six in each direction**, a 34% flip rate against the 17.1% measured at 0.4.0 between two
*identical* captures. A 7-case cell with a ~34% background flip rate would move by one or two
cases on a re-run with no change at all, so this measurement cannot tell a working fix from a
coin toss.

That the flip rate doubled is itself consistent: 0.4.0 measured `buried` as the noisiest cell at
22%, and batch 7 is two-thirds `buried` by construction.

**What this does and does not establish.** It does not establish the fix works. It does not
establish it fails — three of four target cases were unchanged, which is equally consistent with
a fix that needs more than a document edit and with a fix that landed but was swamped. The
result is genuinely null, and the design is why: a 7-case cell cannot resolve a single-case
effect.

**What it would take.** Either many more `secure` cases — the cell needs to be sized against the
flip rate, not against convenience — or repeated captures of the same cell to average the noise
out. Both cost money this budget no longer has. **Do not quote 3/7 as an improvement over 4/7.**

Recorded rather than dropped, because the negative result is the useful part: it prices what a
future prompt-fix measurement has to buy before it can claim anything.
