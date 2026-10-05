# Token-attribution findings — era python-2, n=3 (89500e0)

**Status:** three complete paired live runs, one workload (TicTacToe), one commit.
**Scope:** per-stage cost attribution, the DV fix in `89500e0`, and a transcript
diagnosis of the two largest remaining deltas (AR, PL). Everything below is read from
the records and captures; nothing is projected.

## Data source

- Records: `benchmark/results/runs/live/live-20260930T{080425,090418,100549}Z-89500e0.json`
- Transcripts: `benchmark/workdirs/<run_id>/captures/{with,without}-<STAGE>.jsonl`
- Era `python-2`. WITH = corpflow 4.1.0 + apple-developer 1.31.0. WITHOUT = plugin-free
  arm under an isolated config dir.
- Reference only, not comparable: `live-20260929T204447Z-d8d8392` (`KNOWN-BAD-RECORDS.md`
  — WITH loaded the installed plugin; WITHOUT carried 36 plugins).
- Noise floor for every number here: `variance-envelope.md § Era python-2 (n=3)`.

## Run totals

| run | WITH | WITHOUT | cost premium | token premium | oracle W / WO |
|---|---:|---:|---:|---:|---|
| 1 `080425` | $10.99 | $5.52 | +99% | +36% | 42/42 / 42/42 |
| 2 `090418` | $10.72 | $5.96 | +80% | +16% | 42/42 / 42/42 |
| 3 `100549` | $12.57 | $5.17 | +143% | +58% | 42/42 / 42/42 |

## Per-stage cost (mean, [min–max], USD)

| Stage | WITH | WITHOUT | Δ mean | Δ range | tool calls W | tool calls WO |
|---|---:|---:|---:|---:|---|---|
| PL | 1.47 [1.07–1.84] | 0.37 [0.35–0.39] | **+1.11** | +0.71..+1.44 | 16 / 35 / 26 | 3 / 6 / 3 |
| AR | 2.87 [2.45–3.08] | 0.93 [0.85–1.01] | **+1.94** | +1.60..+2.15 | 22 / 30 / 34 | 5 / 4 / 6 |
| TL | 0.11 [0.09–0.12] | 0.08 [0.07–0.10] | +0.03 | +0.02..+0.04 | 4 / 4 / 3 | 2 / 3 / 2 |
| DV | 3.99 [3.11–4.62] | 2.53 [2.24–2.71] | **+1.46** | +0.40..+2.38 | 33 / 32 / 52 | 24 / 25 / 25 |
| DR | 1.24 [1.04–1.46] | 0.63 [0.60–0.65] | +0.62 | +0.38..+0.84 | 20 / 18 / 20 | 10 / 12 / 11 |
| SR | 0.98 [0.86–1.06] | 0.58 [0.55–0.65] | +0.39 | +0.21..+0.51 | 17 / 15 / 16 | 8 / 9 / 10 |
| QA | 0.17 [0.16–0.19] | 0.10 [0.10–0.11] | +0.07 | +0.05..+0.09 | 5 / 5 / 7 | 4 / 6 / 4 |
| DC | 0.24 [0.13–0.43] | 0.12 [0.12–0.13] | +0.11 | +0.01..+0.30 | 16 / 17 / 39 | 14 / 11 / 12 |
| FN | 0.18 [0.15–0.20] | 0.12 [0.10–0.13] | +0.05 | +0.02..+0.09 | 8 / 8 / 5 | 3 / 3 / 6 |
| ST | 0.17 [0.15–0.20] | 0.08 [0.07–0.09] | +0.09 | +0.07..+0.13 | 4 / 4 / 7 | 2 / 2 / 2 |
| **Total** | | | **+5.88** | | | |

- Every stage's delta is positive in all three runs.
- **AR + DV + PL = $4.51 of $5.88 (77%).** DR + SR add $1.01.
- DV has the widest delta range (+0.40..+2.38); AR the tightest relative range.

## DV: before and after `89500e0`

| | d8d8392 (known-bad) | 89500e0 run 1 / 2 / 3 |
|---|---:|---|
| WITH-DV assistant events | 177 | 69 / 59 / 96 |
| WITH-DV tool calls (record) | 104 | 33 / 32 / 52 |
| WITH-DV cost | $7.30 | $4.24 / $3.11 / $4.62 |
| WITHOUT-DV cost | $3.52 | $2.64 / $2.71 / $2.24 |

Three causes were fixed in `89500e0`:

1. **Screenshot adapter** — DV now reaches evidence capture through the
   `corpflow:dv-screenshot-capture` skill (one `Skill` call in each WITH-DV transcript)
   rather than probing capture tooling turn by turn.
2. **Helper recipes** — ready-made helper invocations replace per-run discovery.
3. **Batched scaffolding** — the d8d8392 WITH-DV transcript has 48 `Write` calls; the
   89500e0 transcripts have 1 / 1 / 2.

**Limit:** d8d8392 ran the installed plugin (`612bb0c5`), not the stamped commit, and
its WITHOUT arm is contaminated. The drop from 177 to 59–96 events is an observation
across eras, not a controlled A/B of the three fixes. DV remains the third-largest
delta (+$1.46), and run 3 (96 events, 41 Bash calls) shows the fix does not hold
every run.

## Diagnosis: AR (+$1.94)

| | WITH run 1 / 2 / 3 | WITHOUT run 1 / 2 / 3 |
|---|---|---|
| assistant events | 31 / 39 / 75 | 11 / 10 / 13 |
| parent tool calls (Bash+Read) | 7 / 6 / 13 | 3 / 3 / 4 |
| subagent tool calls | 13 / 22 / 19 | — |
| output tokens, `modelUsage` | 64,295 / 74,368 / 82,029 | 25,685 / 31,046 / 28,004 |
| output tokens, stage record `out` | 26,443 / 25,845 / 8,879 | same as `modelUsage` |
| artifacts written (chars) | `apple-architecture.md` 13.0k / 13.2k / 13.7k + `architecture-0.md` 21.1k / 20.0k / 22.4k | `architecture-0.md` 34.2k / 35.6k / 32.8k |

**What the WITH agent spends turns on that WITHOUT does not:**

1. **The `apple-developer:apple-architector` consult.** One `Agent` call per run. The
   subagent's output is the gap between `modelUsage` and the record's `out`:
   ~38k / ~49k / ~73k tokens — the largest single term in AR WITH.
2. **Plugin discovery inside the consult.** 9 / 14 / 11 of the subagent's 13 / 22 / 19
   tool calls locate its own plugin: `ls` of the workdir, `echo $CLAUDE_PLUGIN_ROOT`,
   `find / -name CORPFLOW.md`, `installed_plugins.json`, then `ls` and `cat` under
   `~/.claude/plugins/cache/apple-developer/apple-developer/1.32.0/`. The dispatch prompt
   says "Read CORPFLOW.md at the root of your plugin" without giving the root.
3. **Compile probes (run 3).** 5 parent calls type-check snippets against the macOS SDK
   (`.context/tmp-typecheck`). Runs 1–2 have 0 and 2.
4. **Ledger work.** 5 / 2 / 4 calls on `state.json`, `handoff-harness.sh` and `jq`
   patches. WITHOUT writes state with one Python heredoc.

**Artifacts:** total AR prose is about equal (WITH ~33–36k chars across two files,
WITHOUT ~33–36k in one). The premium is the consult and its discovery, not a longer
architecture document.

## Diagnosis: PL (+$1.11)

| | WITH run 1 / 2 / 3 | WITHOUT run 1 / 2 / 3 |
|---|---|---|
| assistant events | 32 / 86 / 54 | 7 / 13 / 8 |
| turns (`result.num_turns`) | 17 / 36 / 27 | 4 / 7 / 4 |
| tool calls (Bash+Read) | 14 / 33 / 24 | 2 / 5 / 2 |
| output tokens | 21,172 / 33,252 / 27,547 | 9,838 / 11,169 / 10,026 |
| cache_read | 686k / 2,258k / 1,514k | 72k / 139k / 75k |
| `planning-0.md` (chars) | 23.3k / 21.5k / 19.8k | 15.7k / 16.0k / 14.7k |

WITH tool calls by category (runs 1 / 2 / 3):

| category | calls | example |
|---|---|---|
| procedure docs | 4 / 9 / 9 | `pl0-procedure.md`, `grep tpl-pl` in stage-contracts, `estimation-methodology`, routing matrix, elicitation sweep |
| state / ledger | 5 / 5 / 9 | seed `state.json`, `jq '.version=2'`, `state-patch`, `handoff-harness` validation |
| toolchain / compile probes | 2 / 7 / 3 | `swift --version`, `simctl`, a scratch package built in `mktemp` (run 2: `swift run`, `xcodebuild -list`, generic-platform build) |
| benchmark harness | 0 / 4 / 0 | run 2 read `benchmark/README.md`, `harness/benchmarklive`, `live/prompts/dv.txt`, oracle files |
| other | 3 / 7 / 3 | branch policy, `detect-ui-channel`, git counts |

WITHOUT does one `ls`/`cat` of `.context`, writes `state.json` with a Python heredoc,
and writes `planning-0.md`. It never reads a procedure file.

**The per-turn cost multiplies:** each extra WITH turn re-reads a growing prefix, so
cache_read rises 10–16× while tool calls rise 5–12×. Run 2 is the outlier on every
axis, driven by the scratch-build prototype and the harness reads.

## Ranked levers

Ceilings are the measured stage delta; none of these is a measured saving.

| # | Lever | Evidence | Ceiling (measured) |
|---|---|---|---|
| 1 | **Pass the resolved plugin root into the AR consult prompt** (e.g. the `CORPFLOW.md` absolute path) | 9 / 14 / 11 discovery calls in the subagent | share of the ~38–73k consult output spent on discovery; bounded by AR Δ +$1.60..+2.15 |
| 2 | **Gate or cap the AR consult** — skip it when PL records a known platform pattern, or bound its return to a short decision list | consult output ~38–73k tokens vs whole WITHOUT AR at 26–31k | AR Δ +$1.60..+2.15 |
| 3 | **Forbid build/compile probes in PL and AR** (toolchain facts from one `swift --version` line; compilation belongs to DV) | PL 2 / 7 / 3 and AR 0 / 2 / 5 probe calls; run 2 PL built a scratch package | run-2 PL excess over runs 1/3: ~$0.3–0.8 |
| 4 | **Inline the PL artifact template and sizing rule in the PL prompt** instead of grepping `stage-contracts.md` / `estimation-methodology` | 4 / 9 / 9 procedure-doc calls in PL | PL Δ +$0.71..+1.44 (shared with #5) |
| 5 | **One-call ledger seed/patch** for PL and AR (a single script invocation, no `jq` follow-ups or re-validation loops) | PL 5 / 5 / 9, AR 5 / 2 / 4 ledger calls; WITHOUT does it in one | part of PL and AR Δ |
| 6 | **Keep PL out of `benchmark/`** — the stage read the harness that measures it | run 2: 4 harness reads | small in cost; a measurement-integrity issue |

Recommended order: 1 and 3 are prompt-only and tied to calls with no output value;
2 changes what the consult produces and needs a quality check against DV outcomes.

## Measurement gaps found

- **Stage `out` omits subagent output.** AR WITH record `out` is 26,443 / 25,845 /
  8,879, while `modelUsage` reports 64,295 / 74,368 / 82,029. `cost_usd` includes the
  subagent (it matches `total_cost_usd`); `tokens` does not. Token-premium figures
  undercount the WITH arm wherever a stage dispatches a subagent.
- **Consult plugin version.** The record states apple-developer 1.31.0; the AR
  consult read files under `.../apple-developer/1.32.0/` in all three runs. Which
  version the subagent's own definition loaded is not verified here.
- **Duplicate `result` event.** Run 3 `with-AR.jsonl` carries two `result` events
  (8 and 9 turns, same cost).

## Honest limits

- **n=3, one workload, one commit.** Per-stage ranges are three points; they are not
  confidence intervals.
- **Tokens do not clear their floor** (`variance-envelope.md`); this report ranks by
  cost, which does.
- **Oracle saturated.** 42/42 in all six arm-runs, so nothing here says whether the
  extra WITH spend buys quality.
- **Category counts are keyword-classified** from tool inputs; boundaries are
  approximate, totals are exact.
- **DV before/after crosses eras** and uses a known-bad record as "before".

## Related

- `variance-envelope.md` — noise floor, era python-2 (n=3)
- `token-findings-3.md` — previous era, n=1, tail stages only
- `KNOWN-BAD-RECORDS.md` — why `d8d8392` is reference only
