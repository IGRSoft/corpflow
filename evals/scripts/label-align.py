#!/usr/bin/env python3
"""label-align — score the assertion harness against human labels.

The harness is itself unmeasured. Human labels are the only ground truth
available, so this reports its TPR and TNR against them, plus the Rogan-Gladen
correction for its observed pass rate.

TPR/TNR rather than accuracy: with a skewed pass rate a grader that always says
pass scores well and catches nothing, and these two rates are what the correction
divides by.

The LLM judge used to be scored here as a second column and no longer is. It
measured TNR 0% — it caught 0 of the 26 failures the humans found — so its column
reported nothing except that it agreed with whatever the harness already said.
Reinstating it means re-validating it first, on a split it did not see.

Labels are JSONL from the review page's Export button:
  {"case_id": 1, "verdict": "pass"|"fail", "note": "..."}

Rates are STRATUM-WEIGHTED. A labelling budget smaller than the corpus gets spent
on an enriched sample — over-sampling harness-fails, because that is where both
error types concentrate — and selecting on the grader's own verdict while measuring
agreement with that grader would bias both rates toward whatever the sample
over-represented. Each labelled case therefore carries weight
`stratum_population / stratum_sampled`, recovering the population rates. Weighting
needs the full grade set to know the populations; without `--grades` the rates fall
back to unweighted and say so.

THE STRATA ARE THE DRAW'S, NOT (split, verdict). `sample-for-labelling.py` draws
from a frame of exactly two kinds of stratum: `dev/<verdict>` over the dev split,
and `test/held-out` — the newest tranche, taken WHOLE. Train cases and test cases
below the floor are not in the frame at all. Re-deriving strata here as
`(split, grader_verdict)` instead put every labelled held-out case in a
`('test', ...)` stratum whose population was the WHOLE test split, so 18 cases
written to be harder than the corpus were weighted ~4.6x each to stand in for 82.
Weighting assumes a random draw within the stratum; the held-out tranche is a
deliberately hard tail. Pass `--sample` to take the populations from the draw that
was actually cut, and `--held-out-from` so a case can be assigned to its stratum.

A SELECTION FILTER APPLIES TO THE POPULATION TOO. `--min-id` and `--split` used to
narrow `ids` while `population` and `p_obs` were still built from every grade, so
"held-out TPR/TNR only" returned corpus weights and the corpus pass rate corrected
by subset-derived rates. Both now honour the same predicate on the `--grades` path.
Under `--sample` the populations are the draw's and cannot be narrowed by an id
floor, so `--min-id` is refused there: it cuts inside a stratum, which the drift
check would then misreport as a moved grade set. Select with `--stratum` instead.

Usage: label-align.py --labels PATH [--grades PATH] [--sample PATH]
                      [--held-out-from N] [--stratum test/held-out]
                      [--split dev] [--min-id N] [--p-obs RATE]
"""

from __future__ import annotations

import argparse
import json
import random
import sys

BOOTSTRAP_SEED = 20260826
BOOTSTRAP_ROUNDS = 2000


def stratum_of(cid, split, verdict, held_out_from):
    """Mirror of `sample-for-labelling.py`'s frame. Anything it would not have
    drawn comes back `unframed/...`: kept, never upweighted, and reported, because
    a labelled case outside the recorded frame means the draw and the labels
    disagree about what was sampled."""
    if held_out_from is not None and split == "test" and cid >= held_out_from:
        return "test/held-out"
    if split == "dev":
        return f"dev/{verdict}"
    return f"unframed/{split}/{verdict}"


def weighted_rates(rows):
    """rows: dicts with human/grader in {'pass','fail'} and a numeric weight."""
    def total(h, g=None):
        return sum(r["weight"] for r in rows
                   if r["human"] == h and (g is None or r["grader"] == g))
    hp, hf = total("pass"), total("fail")
    tp, fn = total("pass", "pass"), total("pass", "fail")
    tn, fp = total("fail", "fail"), total("fail", "pass")
    tpr = tp / hp if hp else None
    tnr = tn / hf if hf else None
    return tpr, tnr, {"tp": tp, "fn": fn, "tn": tn, "fp": fp}


def bootstrap_ci(rows, p_obs, rounds=BOOTSTRAP_ROUNDS, seed=BOOTSTRAP_SEED):
    """Percentile CI for the corrected rate, resampling WITHIN each stratum.

    Stratified because the sample is stratified: resampling the pooled rows would
    let a draw change the pass/fail mix the design fixed, widening the interval for
    a reason the study does not have. Seeded so a re-run reproduces the number in
    the findings doc. Stdlib `random` — the repo carries no numpy by design.
    """
    strata = {}
    for r in rows:
        strata.setdefault(r["stratum"], []).append(r)
    if not strata:
        return None, None
    # No point estimate, no interval. Resampling a coin-flip grader still yields
    # draws that happen to miss the degenerate denominator, and their percentiles
    # come back as a confident-looking [0%, 100%] — an interval around a number
    # this function already declined to produce.
    if corrected(p_obs, *weighted_rates(rows)[:2]) is None:
        return None, None
    rng = random.Random(seed)
    estimates = []
    for _ in range(rounds):
        draw = []
        for group in strata.values():
            draw += [group[rng.randrange(len(group))] for _ in group]
        tpr, tnr, _ = weighted_rates(draw)
        theta = corrected(p_obs, tpr, tnr)
        if theta is not None:
            estimates.append(theta)
    if len(estimates) < rounds // 10:
        # Too many draws landed on a degenerate matrix for a percentile to mean
        # anything; a number here would be an artefact of the ones that survived.
        return None, None
    estimates.sort()
    lo = estimates[int(0.025 * (len(estimates) - 1))]
    hi = estimates[int(0.975 * (len(estimates) - 1))]
    return lo, hi


def corrected(p_obs, tpr, tnr):
    """Rogan-Gladen. None when the grader is no better than a coin, where the
    correction divides by ~0 and any estimate it returns is noise."""
    if tpr is None or tnr is None:
        return None
    denom = tpr + tnr - 1
    if abs(denom) < 1e-6:
        return None
    return max(0.0, min(1.0, (p_obs + tnr - 1) / denom))


def report(name, rows, p_obs=None, weighted=True):
    tpr, tnr, m = weighted_rates(rows)
    label = "weighted" if weighted else "unweighted"
    print(f"\n{name}  (n={len(rows)}, {label})")
    print(f"  human pass/grader pass {m['tp']:6.1f}   human pass/grader fail {m['fn']:6.1f}")
    print(f"  human fail/grader pass {m['fp']:6.1f}   human fail/grader fail {m['tn']:6.1f}")
    print(f"  TPR {'n/a' if tpr is None else f'{tpr:.0%}'}"
          f"   TNR {'n/a' if tnr is None else f'{tnr:.0%}'}")
    if tpr is not None and tnr is not None and tpr + tnr - 1 < 0.2:
        print("  ** TPR+TNR-1 is near zero: this grader barely beats a coin flip,")
        print("     so neither its verdicts nor any correction from them mean much.")
    out = {"tpr": tpr, "tnr": tnr, "n": len(rows), "weighted": weighted, **m}
    if p_obs is not None:
        theta = corrected(p_obs, tpr, tnr)
        lo, hi = bootstrap_ci(rows, p_obs)
        span = "" if lo is None else f"  95% CI [{lo:.0%}, {hi:.0%}]"
        print(f"  observed pass rate {p_obs:.0%} -> corrected "
              f"{'n/a' if theta is None else f'{theta:.0%}'}{span}")
        out.update({"p_obs": p_obs, "corrected": theta, "ci_low": lo, "ci_high": hi})
    if len(rows) < 20:
        print("  ** under 20 labels: directional only, a single case moves these rates.")
    return out


def main(argv) -> int:
    p = argparse.ArgumentParser(prog="label-align")
    p.add_argument("--labels", required=True, help="JSONL exported from the review page")
    p.add_argument("--grades", default=None,
                   help="eval-grade --json output. Omitted, the rates fall back to "
                        "each label's own harness_status and the weights to 1")
    p.add_argument("--sample", default=None,
                   help="the draw's <skill>-<version>-sample.json. Its `strata` are the "
                        "populations the sample was actually drawn from; without it they "
                        "are re-derived from --grades, which can only reconstruct the "
                        "frame, never the draw")
    p.add_argument("--held-out-from", type=int, default=None,
                   help="first id of the tranche taken whole in this draw. Read from "
                        "--sample's held_out_from when present. Absent, no case is "
                        "assigned to test/held-out and test-split labels fall outside "
                        "the frame")
    p.add_argument("--allow-stratum-drift", action="store_true",
                   help="proceed when the labels' per-stratum counts do not match the "
                        "draw's. They disagree only if the grade set moved under the "
                        "labels, so the weights describe a frame that was never sampled")
    p.add_argument("--stratum", default=None,
                   help="report one stratum of the draw, e.g. test/held-out. Exact where "
                        "an id floor is not: batch 5 seeded BOTH the held-out tranche and "
                        "dev cases, so --min-id over its range sweeps in dev labels the "
                        "draw counted elsewhere")
    p.add_argument("--split", default=None)
    p.add_argument("--min-id", type=int, default=None,
                   help="restrict to case ids >= N. Narrows the POPULATION and p_obs by "
                        "the same predicate, so the rates describe the subset rather "
                        "than the corpus. Refused under --sample, whose populations are "
                        "whole strata; use --stratum there. The current tranche floor is the held_out_from "
                        "recorded in evals/splits/request-plan.json; below it the "
                        "manifest calls its own `test` membership nominal")
    p.add_argument("--p-obs", type=float, default=None,
                   help="observed harness pass rate to correct, when the grade set is "
                        "not at hand. Captured responses are gitignored and cost a "
                        "sweep to regenerate, so without this the published corrected "
                        "rates cannot be re-derived from what git actually holds")
    p.add_argument("--json", action="store_true")
    args = p.parse_args(argv)

    try:
        with open(args.labels, encoding="utf-8") as f:
            human, deferred = {}, {}
            for line in f:
                line = line.strip()
                if not line:
                    continue
                row = json.loads(line)
                if row.get("verdict") in ("pass", "fail"):
                    human[row["case_id"]] = row
                elif row.get("verdict") == "defer":
                    # Excluded from every rate — an undecided case must not vote — but
                    # it was still DRAWN, so the drift check has to see it or a single
                    # defer looks like the draw and the labels disagreeing.
                    deferred[row["case_id"]] = row
    except (OSError, ValueError) as exc:
        sys.stderr.write(f"label-align: cannot read labels: {exc}\n")
        return 64
    if not human:
        sys.stderr.write("label-align: no usable labels\n")
        return 64

    draw = None
    if args.sample:
        if args.min_id is not None:
            # The draw's populations are per stratum and whole; an id floor cuts inside
            # them, so the drift check below would refuse with the wrong diagnosis and
            # --allow-stratum-drift would weight a partial stratum by its full population.
            sys.stderr.write("label-align: --min-id cannot narrow a draw's populations; "
                             "select with --stratum (e.g. test/held-out) under --sample\n")
            return 64
        try:
            with open(args.sample, encoding="utf-8") as f:
                draw = json.load(f)
        except (OSError, ValueError) as exc:
            sys.stderr.write(f"label-align: cannot read sample manifest: {exc}\n")
            return 64
        if args.held_out_from is None and "held_out_from" in draw:
            args.held_out_from = int(draw["held_out_from"])

    grades = {}
    try:
        if args.grades is None:
            raise FileNotFoundError("no --grades given")
        with open(args.grades, encoding="utf-8") as f:
            grades = {r["case_id"]: r for r in json.load(f)["results"]}
    except (OSError, ValueError) as exc:
        # The label rows already carry the harness verdict the review page saw, so a
        # missing grades file costs the WEIGHTS and p_obs, not the comparison. It used
        # to cost everything: --grades defaults to a /tmp path nothing produces, which
        # left the only calibration tool in the repo unrunnable.
        if not all("harness_status" in r for r in human.values()):
            sys.stderr.write(f"label-align: cannot read grades ({exc}) and the labels "
                             f"carry no harness_status; run eval-grade.py --json first\n")
            return 64
        sys.stderr.write(
            f"label-align: no grades file ({exc}); falling back to each label's own "
            f"harness_status."
            + ("" if draw else " Without --sample the weights fall back to 1.")
            + ("" if args.p_obs is not None else
               " Without --p-obs there is no observed rate over the unlabelled cases "
               "to correct.")
            + "\n")

    def grader_verdict(cid):
        if cid in grades:
            return "pass" if grades[cid].get("status") == "pass" else "fail"
        return "pass" if human[cid].get("harness_status") == "pass" else "fail"

    def selected(cid, split):
        """The one predicate. Applied to the labels, the populations and p_obs alike:
        a subset report whose denominator is still the corpus is not a subset report."""
        return ((args.split is None or split == args.split)
                and (args.min_id is None or cid >= args.min_id))

    ids = [c for c in human
           if (not grades or c in grades)
           and selected(c, human[c].get("split"))
           and (args.stratum is None
                or stratum_of(c, human[c].get("split"), grader_verdict(c),
                              args.held_out_from) == args.stratum)]
    if not ids:
        sys.stderr.write("label-align: no labelled case matched the selection\n")
        return 64

    weighted = bool(grades) or bool(draw)
    sampled, population = {}, {}
    strata_of = {}
    for c in ids:
        s = stratum_of(c, human[c].get("split"), grader_verdict(c), args.held_out_from)
        strata_of[c] = s
        sampled[s] = sampled.get(s, 0) + 1

    # `drawn` counts what the draw handed the labeller; `sampled` what survived to
    # vote. They differ by the defers, and the weight divides by the smaller one:
    # the survivors stand in for the whole stratum only if the defers are missing at
    # random, which is the assumption this line makes and the reason to keep the gap
    # visible in the output rather than folding it away.
    drawn = dict(sampled)
    for c, row in deferred.items():
        split = row.get("split")
        if not selected(c, split):
            continue
        gv = "pass" if row.get("harness_status") == "pass" else "fail"
        if grades and c in grades:
            gv = "pass" if grades[c].get("status") == "pass" else "fail"
        s = stratum_of(c, split, gv, args.held_out_from)
        if args.stratum is not None and s != args.stratum:
            continue
        drawn[s] = drawn.get(s, 0) + 1

    if draw:
        # The draw is authoritative: it records the frame that was sampled, which a
        # later grade set can no longer reconstruct once any case has flipped.
        for name, m in (draw.get("strata") or {}).items():
            population[name] = m.get("population")
        drift = {n: (drawn[n], (draw.get("strata") or {}).get(n, {}).get("sampled"))
                 for n in drawn
                 if (draw.get("strata") or {}).get(n, {}).get("sampled") != drawn[n]}
        if drift:
            lines = "".join(
                f"    {n:22} labels {a:3}  draw {b if b is not None else 'absent'}\n"
                for n, (a, b) in sorted(drift.items()))
            sys.stderr.write(
                "label-align: the labels do not sit in the strata the draw recorded:\n"
                + lines
                + "  The draw's populations therefore weight a frame that was never\n"
                  "  sampled. This happens when the grade set moved after the draw was\n"
                  "  cut, so each label's harness_status no longer names the stratum it\n"
                  "  was drawn from. Re-cut the draw against the grades these labels\n"
                  "  were taken under, or pass --allow-stratum-drift to proceed and\n"
                  "  treat every rate below as uncalibrated.\n")
            if not args.allow_stratum_drift:
                return 65
    elif grades:
        # No draw to read, so reconstruct the frame sample-for-labelling.py uses.
        # Restricted by `selected` for the same reason the labels are.
        for cid, g in grades.items():
            split = g.get("split") or (human.get(cid) or {}).get("split")
            if not selected(cid, split):
                continue
            s = stratum_of(cid, split, "pass" if g.get("status") == "pass" else "fail",
                           args.held_out_from)
            if args.stratum is not None and s != args.stratum:
                continue
            population[s] = population.get(s, 0) + 1

    unframed = sorted(n for n in sampled if n.startswith("unframed/"))
    if unframed:
        sys.stderr.write(
            "label-align: labelled cases outside the draw's frame, carried at weight "
            "1.00: " + ", ".join(f"{n} x{sampled[n]}" for n in unframed) + "\n"
            "  sample-for-labelling.py draws only dev/<verdict> and test/held-out. A "
            "case here is either a hand-added label or a missing --held-out-from.\n")

    rows = []
    for c in ids:
        gv, stratum = grader_verdict(c), strata_of[c]
        w = 1.0
        if weighted and population.get(stratum) and sampled.get(stratum):
            w = population[stratum] / sampled[stratum]
        # A clarification is not a harness pass; fold it with fail so the matrix is binary.
        rows.append({"case_id": c, "human": human[c]["verdict"], "grader": gv,
                     "weight": w, "stratum": stratum})

    p_obs, sel = args.p_obs, []
    if grades:
        sel = [r for cid, r in grades.items()
               if selected(cid, r.get("split") or (human.get(cid) or {}).get("split"))
               and (args.stratum is None
                    or stratum_of(cid,
                                  r.get("split") or (human.get(cid) or {}).get("split"),
                                  "pass" if r.get("status") == "pass" else "fail",
                                  args.held_out_from) == args.stratum)]
        if sel and args.p_obs is None:
            p_obs = sum(1 for r in sel if r.get("status") == "pass") / len(sel)
    frame = sum(population.get(n) or sampled[n] for n in sampled)
    out = {"n_labelled": len(ids), "frame": frame,
           "held_out_from": args.held_out_from,
           "strata": {k: {"sampled": v, "population": population.get(k)}
                      for k, v in sorted(sampled.items())},
           "harness": report("HARNESS vs human", rows, p_obs, weighted)}

    print(f"\nLabelled {len(ids)} of {frame} cases in the frame"
          + (f"; p_obs over {len(sel)} graded." if sel else
             ("; p_obs supplied." if p_obs is not None else ".")))
    for k, v in sorted(sampled.items()):
        pop, dr = population.get(k), drawn.get(k, v)
        gap = f"  ({dr - v} deferred)" if dr != v else ""
        print(f"  stratum {k:24} sampled {v:3}"
              + (f" of {pop:3}  weight {pop / v:.2f}" if pop else "  weight 1.00")
              + gap)
    if p_obs is not None and sel and frame < len(sel):
        print(f"  ** TPR/TNR are estimated on the {frame}-case frame and applied to a "
              f"p_obs over {len(sel)}:\n"
              f"     the correction extrapolates beyond what was sampled.")
    if args.json:
        print(json.dumps(out, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
