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

Usage: label-align.py --labels PATH [--grades PATH] [--split dev] [--min-id N]
"""

from __future__ import annotations

import argparse
import json
import random
import sys

BOOTSTRAP_SEED = 20260826
BOOTSTRAP_ROUNDS = 2000


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
    p.add_argument("--grades", default="/tmp/allgrades.json", help="eval-grade --json output")
    p.add_argument("--split", default=None)
    p.add_argument("--min-id", type=int, default=None,
                   help="restrict to case ids >= N. The held-out tranche is ids 122+; "
                        "every lower id predates the reset and has been read, so the "
                        "split manifest calls its own `test` membership nominal")
    p.add_argument("--json", action="store_true")
    args = p.parse_args(argv)

    try:
        with open(args.labels, encoding="utf-8") as f:
            human = {}
            for line in f:
                line = line.strip()
                if not line:
                    continue
                row = json.loads(line)
                if row.get("verdict") in ("pass", "fail"):
                    human[row["case_id"]] = row
    except (OSError, ValueError) as exc:
        sys.stderr.write(f"label-align: cannot read labels: {exc}\n")
        return 64
    if not human:
        sys.stderr.write("label-align: no usable labels\n")
        return 64

    grades = {}
    try:
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
        sys.stderr.write(f"label-align: no grades file ({exc}); falling back to each "
                         f"label's own harness_status. Rates are UNWEIGHTED and there "
                         f"is no p_obs over the unlabelled cases.\n")

    def grader_verdict(cid):
        if cid in grades:
            return "pass" if grades[cid].get("status") == "pass" else "fail"
        return "pass" if human[cid].get("harness_status") == "pass" else "fail"

    ids = [c for c in human
           if (not grades or c in grades)
           and (args.split is None or human[c].get("split") == args.split)
           and (args.min_id is None or c >= args.min_id)]
    if not ids:
        sys.stderr.write("label-align: no labelled case matched the selection\n")
        return 64

    # Stratum populations come from the FULL grade set; without it every weight is 1
    # and the rates describe the sample rather than the corpus.
    weighted = bool(grades)
    sampled, population = {}, {}
    for c in ids:
        sampled[(human[c].get("split"), grader_verdict(c))] = \
            sampled.get((human[c].get("split"), grader_verdict(c)), 0) + 1
    if weighted:
        for cid, g in grades.items():
            key = (g.get("split") or (human.get(cid) or {}).get("split"),
                   "pass" if g.get("status") == "pass" else "fail")
            population[key] = population.get(key, 0) + 1

    rows = []
    for c in ids:
        gv = grader_verdict(c)
        stratum = (human[c].get("split"), gv)
        w = 1.0
        if weighted and population.get(stratum) and sampled.get(stratum):
            w = population[stratum] / sampled[stratum]
        # A clarification is not a harness pass; fold it with fail so the matrix is binary.
        rows.append({"case_id": c, "human": human[c]["verdict"], "grader": gv,
                     "weight": w, "stratum": stratum})

    p_obs = None
    if grades:
        p_obs = sum(1 for r in grades.values()
                    if r.get("status") == "pass") / max(1, len(grades))
    out = {"n_labelled": len(ids),
           "strata": {f"{k[0]}/{k[1]}": {"sampled": v, "population": population.get(k)}
                      for k, v in sorted(sampled.items(), key=lambda kv: str(kv[0]))},
           "harness": report("HARNESS vs human", rows, p_obs, weighted)}

    print(f"\nLabelled {len(ids)} of {len(grades) or len(human)} cases.")
    for k, v in sorted(sampled.items(), key=lambda kv: str(kv[0])):
        pop = population.get(k)
        print(f"  stratum {str(k):24} sampled {v:3}"
              + (f" of {pop:3}  weight {pop / v:.2f}" if pop else "  weight 1.00"))
    if args.json:
        print(json.dumps(out, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
