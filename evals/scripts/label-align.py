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

Usage: label-align.py --labels PATH [--grades PATH] [--split dev]
"""

from __future__ import annotations

import argparse
import json
import sys


def rates(pairs):
    """pairs: (human, grader) in {'pass','fail'}. Returns TPR, TNR and the matrix."""
    tp = sum(1 for h, g in pairs if h == "pass" and g == "pass")
    fn = sum(1 for h, g in pairs if h == "pass" and g == "fail")
    tn = sum(1 for h, g in pairs if h == "fail" and g == "fail")
    fp = sum(1 for h, g in pairs if h == "fail" and g == "pass")
    tpr = tp / (tp + fn) if (tp + fn) else None
    tnr = tn / (tn + fp) if (tn + fp) else None
    return tpr, tnr, {"tp": tp, "fn": fn, "tn": tn, "fp": fp}


def corrected(p_obs, tpr, tnr):
    """Rogan-Gladen. None when the grader is no better than a coin, where the
    correction divides by ~0 and any estimate it returns is noise."""
    if tpr is None or tnr is None:
        return None
    denom = tpr + tnr - 1
    if abs(denom) < 1e-6:
        return None
    return max(0.0, min(1.0, (p_obs + tnr - 1) / denom))


def report(name, pairs, p_obs=None):
    tpr, tnr, m = rates(pairs)
    print(f"\n{name}  (n={len(pairs)})")
    print(f"  human pass/grader pass {m['tp']:3}   human pass/grader fail {m['fn']:3}")
    print(f"  human fail/grader pass {m['fp']:3}   human fail/grader fail {m['tn']:3}")
    print(f"  TPR {'n/a' if tpr is None else f'{tpr:.0%}'}"
          f"   TNR {'n/a' if tnr is None else f'{tnr:.0%}'}")
    if tpr is not None and tnr is not None and tpr + tnr - 1 < 0.2:
        print("  ** TPR+TNR-1 is near zero: this grader barely beats a coin flip,")
        print("     so neither its verdicts nor any correction from them mean much.")
    if p_obs is not None:
        theta = corrected(p_obs, tpr, tnr)
        print(f"  observed pass rate {p_obs:.0%} -> corrected "
              f"{'n/a' if theta is None else f'{theta:.0%}'}")
    return {"tpr": tpr, "tnr": tnr, **m}


def main(argv) -> int:
    p = argparse.ArgumentParser(prog="label-align")
    p.add_argument("--labels", required=True, help="JSONL exported from the review page")
    p.add_argument("--grades", default="/tmp/allgrades.json", help="eval-grade --json output")
    p.add_argument("--split", default=None)
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

    try:
        with open(args.grades, encoding="utf-8") as f:
            grades = {r["case_id"]: r for r in json.load(f)["results"]}
    except (OSError, ValueError) as exc:
        sys.stderr.write(f"label-align: cannot read grades ({exc}); "
                         f"run eval-grade.py --json first\n")
        return 64

    ids = [c for c in human
           if c in grades and (args.split is None or human[c].get("split") == args.split)]
    if not ids:
        sys.stderr.write("label-align: no labelled case has a grade\n")
        return 64

    # A clarification is not a harness pass; fold it with fail so the matrix is binary.
    hpairs = [(human[c]["verdict"], "pass" if grades[c].get("status") == "pass" else "fail")
              for c in ids]
    p_obs = sum(1 for r in grades.values() if r.get("status") == "pass") / max(1, len(grades))
    out = {"n_labelled": len(ids), "harness": report("HARNESS vs human", hpairs, p_obs)}

    print(f"\nLabelled {len(ids)} of {len(grades)} graded cases.")
    if len(ids) < 20:
        print("Below ~20 labels these rates swing hard on a single case — treat as directional.")
    if args.json:
        print(json.dumps(out, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
