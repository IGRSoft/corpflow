# Skill-grant and plugin-path verification — live paired probes

**Status:** no check passes cleanly. One replicated as a null result, one does not replicate
across runs, one is confounded by a harness defect, and the oracle — which has been running
all along — does not discriminate. Reported against noise per the `token-findings-2.md`
standard.

| Check | Verdict |
|---|---|
| 1. DV calls `Skill`, no `capture.sh` | **MIXED** — `capture.sh` gone; evidence in both runs; Skill call in only 1 of 2 |
| 2. Plugin-path hunting stops | **CONFOUNDED** — `CLAUDE_PLUGIN_ROOT` unset under the harness |
| 3. Cost ratio vs 1.14x | **1.25x on the first complete paired run**, upper bound (see below) |
| Oracle `failures[]` → taxonomy | **NULL RESULT** — 30/30 both arms; arms proven equivalent over 15 further probes |

**Records:**

- `live-20260814T102001Z-cce3984.json` — **complete**, 10/10 both arms, `--budget 100`,
  WITH $22.38 / WITHOUT $17.87. The first non-partial live paired run in repo history.
- `live-20260814T083428Z-cce3984.json` — partial, WITH 10/10, WITHOUT 4/10, `--budget 70`.
- `live-20260807T114444Z-a0cdb43.json` — baseline, partial, WITH 4/10, WITHOUT 10/10.

## Correction to an earlier claim in this document

An earlier revision asserted that no live record had ever carried an oracle block. **That
was wrong.** It came from checking `has("oracle")` at the record root; the oracle is stored
per-arm at `paths.<arm>.oracle`. Every record carries one:

| Record | WITH | WITHOUT |
|---|---|---|
| `a0cdb43` (baseline) | 20/20 | 20/20 (pre-tier 20-case set) |
| `083428Z` | 30/30, implied 6/6 | 30/30, implied 6/6 |
| `102001Z` | 30/30, implied 6/6 | 30/30, implied 6/6 |

The original plan's premise — that oracle `failures[]` is empty for both arms — was correct.
The "no oracle ever ran" claim that briefly replaced it was an artifact of a bad jq path.

## Oracle: a real null result, now well-evidenced

**Six arms across three runs. Zero failures. Ever.** Both runs at the tiered 30-case set
sweep `specified` 24/24 *and* `implied` 6/6 — including the tier built specifically to be
the discriminating signal.

Per the Phase 3 spec, `evals/failure-taxonomy.md` is **deliberately not written**. There is
no failure material to open-code, and inventing categories from a clean sweep would be
worse than having none.

The finding is about the instrument, not the agents: **the case set does not discriminate
on this workload.** A tic-tac-toe CLI built from a scripted contract is apparently within
comfortable reach of both arms, so the oracle cannot separate them.

### Why more cases cannot fix this

Both arms' apps were rebuilt from the completed run and probed with 15 candidate edge cases
beyond the graded set (empty tokens, tab/newline padding, integer overflow, leading zeros,
`+` signs, hex, unicode digits, 50-move lists, precedence pairs).

**Not one case separated the arms.** On all 15 the two implementations returned identical
exit codes and identical stdout. Where they diverged from `ttt-template` they diverged
*together*, in the same direction, on all 5 such cases.

This reframes the null result: it is not that the cases are too easy, it is that **the two
arms produce functionally equivalent implementations on this surface.** No amount of
additional CLI case coverage will discriminate them, because there is nothing to discriminate.

### A defect in the golden source

The 5 shared divergences are all contract ambiguities where `ttt-template` — the source of
every golden — made an undocumented choice:

- `main.swift:31` (`if trimmed.isEmpty { continue }`) silently drops empty tokens, so
  `0,`, `0,,4` and `,` all succeed. Both arms read "comma-separated integer list" strictly
  and exit 2.
- `main.swift:30` trims `.whitespaces`, which excludes newlines, so a newline-padded token
  fails to parse. Both arms treated newline as whitespace and accepted it.

Where the contract was silent, the goldens encoded an implementation accident as the correct
answer. Both independent implementations disagreed with it — which is evidence about the
template, not about them.

### What was changed

`_cli-contract.txt` now states the previously-unwritten rules (parse-before-play precedence,
whitespace = spaces and tabs only, empty tokens contribute no move), propagated verbatim into
`dv.txt` and `without.txt` as the lint requires. `era.prompt_contract` is bumped to
**`scripted-cli-v3`**; records before and after are not directly comparable.

Five `implied` cases were added with goldens captured from the template, never hand-written,
taking the set to 35 (24 specified / 11 implied). Re-grading the completed run's two arms
against it:

| | cases | specified | implied |
|---|---|---|---|
| `ttt-template` | 35/35 | 24/24 | 11/11 |
| WITH | **32/35** | 24/24 | **8/11** |
| WITHOUT | **32/35** | 24/24 | **8/11** |

**The ceiling effect is gone** — the oracle can now register a regression, which at 30/30 it
could not. Both arms fail the same three cases (`empty-token-between-commas`,
`trailing-comma-accepted`, `newline-is-not-token-whitespace`), so `failures[]` is populated
for the first time.

It still does not discriminate *between* arms, and per the 15-probe result it is unlikely
that any CLI-surface case will. Phase 3 now has three real failure rows to open-code, but a
taxonomy built from three rows that both arms share would describe the contract's former
ambiguity, not agent behaviour. `evals/failure-taxonomy.md` therefore remains unwritten;
the honest prerequisite is a workload where the arms actually differ.

## Check 1 — DV calls `Skill`, stops writing `capture.sh`: **does not replicate**

| Run | DV `Skill` calls | DV tool mix | `capture.sh` written |
|---|---|---|---|
| `083428Z` | 1 — `corpflow:dv-screenshot-capture` | 44 Write, 34 Bash, 11 Read, 6 Edit, 1 Skill | no |
| `102001Z` | **0** | 40 Bash, 38 Write, 21 Edit, 8 Read | no |

Same sha, same prompt contract, same platform. The only `Skill` call anywhere in the second
run's WITH arm was `ST → corpflow:self-improvement`.

**The difference is mechanism, not outcome.** Both runs produced real visual evidence:

| Run | Skill tool call | Evidence produced |
|---|---|---|
| `083428Z` | yes | `dv-01-main-menu.png`, `dv-02-game-mid-match.png`, `dv-04-leaderboard.png`, … |
| `102001Z` | no | 4 × 960×1360 PNG + `screenshots.md` manifest |

Run B reached the skill's *procedure* without invoking the Skill *tool*, and its manifest is
complete — per-shot captions tied to REQ/AC ids, adapter (`apple_offscreen_render`), an
explicit note that `screencapture` returned all-black frames under TCC denial and was
verified before falling back, and an honest known-limitation entry for the `Form` controls
`ImageRenderer` cannot draw.

So the correct reading of Check 1 is **weaker than a defect and weaker than a pass**: the
`capture.sh` failure mode is gone (never written in either run), evidence appears in both
runs, and the Skill-tool invocation itself is not deterministic. `metadata.requires_screenshots`
was `true` in both runs and the evidence requirement was met both times.

An earlier revision of this document claimed the DV completion gate "is not enforced on this
path." **That was wrong** — it was written before checking `.context/images/`, which contains
the evidence. Retracted.

One real caveat survives: the offscreen `ImageRenderer` path is host-rendered, and the skill
itself (§68) holds that a host-rendered snapshot verifies structure, not runtime
presentation. DV disclosed this rather than papering over it, and the cause was
environmental (TCC), not a workflow failure.

## Check 2 — plugin-path filesystem hunting stops: **confounded**

23 `find`-based probes across the WITH arm this run (27 in the previous one), in shapes like:

```
find / -maxdepth 10 -iname "plugin.json" -path "*corpflow*"
find / -maxdepth 8  -iname "state-patch.sh"
find / -maxdepth 8  -iname "CORPFLOW.md"
```

### Root cause: `CLAUDE_PLUGIN_ROOT` is unset under the benchmark harness

PL's own probe printed it:

```
PLUGIN_ROOT=
FOUND: /Volumes/internal/conductor/workspaces/corpflow/jerusalem
```

Neither `run-benchmark.sh` nor `dispatch.py` exports `CLAUDE_PLUGIN_ROOT`, and
`Subprocess.run` passes no `env`, so every dispatched stage inherits it unset. PL survives
only because its fallback list happens to include the literal repo path; stages whose
fallback chains miss escalate to `find /`.

**This is very likely a harness artifact, not a production defect.** Under normal plugin
loading the variable is set and this fallback never triggers. The run does **not** show the
v4.0.10 plugin-path fix failing in production — it shows the benchmark not reproducing the
condition that fix targets.

Two things remain worth fixing regardless:

1. **The harness should export `CLAUDE_PLUGIN_ROOT`** — otherwise Check 2 is untestable
   here, and the induced `find /` scans inflate the measured cost of every affected stage,
   contaminating Check 3.
2. **Unbounded `find /` is a bad fallback whatever triggers it.** An agent that cannot
   resolve the plugin root should fail loudly, not scan to `-maxdepth 10`.

`CORPFLOW.md` is a red herring: by contract (`plugin-contract.md:10`) it is exposed by
*integrating* plugins at their own root. corpflow is the orchestrator and correctly has
none. Agents probing for it are guessing at landmarks.

## Check 3 — cost ratio: 1.25x, and the quality delta is zero

The first complete like-for-like 10-stage paired run:

| Metric | WITH | WITHOUT | Delta |
|---|---:|---:|---:|
| cost_usd | $22.38 | $17.87 | **+25.2%** |
| wall_clock_s | 2,974 | 2,382 | +24.9% |
| loc_produced | 1,920 | 2,263 | −15.2% |
| test_count | 52 | 84 | −38.1% |
| tokens_total | 182,040 | 182,576 | −0.3% |
| **oracle** | **30/30** | **30/30** | **0** |

Per-stage, WITH is dearer everywhere except the back half (DR, SR, FN), and DV dominates:
$12.45 vs $7.54.

**On this workload the pipeline costs ~25% more, takes ~25% longer, produces fewer lines
and fewer tests, and scores identically on the held-out oracle.** That is the honest read.

Three caveats, none of which rescue it:

- **n=1** for the complete paired comparison.
- **DV variance is large** — $7.54 / $9.04 / $11.52 / $12.45 / $18.16 across five observed
  arm-runs. A 2.4x spread on the stage carrying ~50% of the cost.
- **The 1.25x is an upper bound.** The WITH arm's 23 `find /` scans are induced by the unset
  `CLAUDE_PLUGIN_ROOT` and would not occur in production, so real overhead is lower by an
  unmeasured amount.

The earlier 1.14x baseline was computed over 4 comparable stages of a partial run and is not
directly comparable to this 10v10 figure.

Note also that `test_count` favours WITHOUT while the oracle scores both perfectly — more
tests did not translate into measurably better output. That is a point about `test_count` as
a quality proxy, not a point in either arm's favour.

## Budget sizing

`--budget 100` (≈$50/arm) cleared both arms; realized $40.25 total. The mechanism that
truncated earlier runs is the reserve rule (`budget.py:112`):
`reserve() = max(next_stage_estimate, max_stage_usd)`, holding back the heaviest observed
stage before every later stage. At `--budget 70` after an $18.16 DV:

```
21.49 spent + 18.16 reserved = 39.65 > 35.00/arm  → DR refused
```

Given DV's $7.54–$18.16 range, **$50/arm is the right floor**; $35 is not reliably enough
and the originally planned $25/arm would have truncated both arms.

## Harness gaps found along the way

Two earlier dispatches died on transient `API Error: 529 Overloaded` — at DV (after
PL/AR/TL, $3.64) and at AR (after PL, $0.96). Neither wrote a record.

1. **An API blip is more destructive than exhausting the budget.** A budget breach calls
   `_persist_partial` and flushes a record; `DispatchFailure` discards everything. Attempt 1
   threw away three completed stages that a budget breach at the same point would have kept.
2. **Failure discards stdout.** `SubprocessDispatcher.run` (`dispatch.py:185-189`) reports
   only stderr, which was empty both times. The 529 was recoverable only from Claude Code's
   own session transcripts, not from the harness.
3. **Oracle grading failures are swallowed** (`dispatch.py:576-578`) — `warn` only. Not hit
   here, but the same silent-failure shape.

## What would close this out

Applied in this change:

1. ✅ `run-benchmark.sh` exports `CLAUDE_PLUGIN_ROOT`, so Check 2 becomes testable and the
   induced `find /` scans stop inflating Check 3.
2. ✅ `DispatchFailure` mid-WITHOUT-arm now persists completed stages (`_persist_without`),
   closing the gap where an API blip destroyed more than a budget breach.
3. ✅ Dispatch failures surface stdout, where the CLI reports API errors under
   `--output-format json`.
4. ✅ Contract ambiguities closed and 5 cases added; the oracle ceiling is broken.
5. ✅ `run-benchmark.sh` regenerates `result.html` after every run, and the report now
   carries the oracle columns — previously the only quality signal was absent from it.

Still open:

6. **Make plugin-root resolution fail loudly instead of scanning.** `find / -maxdepth 10`
   should not be any agent's fallback, whatever sets the variable.
7. **Change the workload.** The 15-probe result says the arms are equivalent on a scripted
   CLI; discriminating them needs a surface where they can differ — AI opponent strategy,
   leaderboard ordering, settings persistence, view-model transitions. This, not more runs,
   is the Phase 3 blocker.
8. Re-run the paired benchmark under the fixed harness before any cost claim is quoted:
   every figure in this document predates fixes 1–5.

Nothing here supports a positive claim about the Skill or plugin-path fixes. Check 1 needs
more runs to say anything at n>1; Check 2 needs the harness fixed before it means anything;
Check 3's only clean signal is that the oracle sees no difference between the arms.
