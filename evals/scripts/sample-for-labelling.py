#!/usr/bin/env python3
"""sample-for-labelling — pick which captured cases are worth a human verdict.

Labelling is the scarce input: the harness can grade 156 cases for free but every
verdict costs a domain expert's attention, so a run is calibrated on whatever
subset the budget allows. Which subset is not a matter of convenience.

Two rules shape it.

Enrich, then weight. Human failures are rare (22 of 114 in the 0.0.1 pass), so a
uniform sample spends most of its budget confirming passes and leaves TNR resting
on a handful of cases. Over-sampling the harness-fail stratum fixes that, but
selecting on the grader's own verdict while measuring agreement WITH that grader
biases both rates — so each stratum's sampling fraction is recorded and
`label-align.py` divides it back out. Enrichment buys precision, never a shifted
estimate.

Take the held-out tranche whole. `evals/splits/request-plan.json` calls its own
`test` membership nominal for ids below the batch-4 boundary: those cases predate
the corpus reset and have been read. Only the ids written after the manifest were
pinned before any capture saw them, and there are few enough that sampling them
would leave nothing to measure. They are taken entire and reported apart.

Usage: sample-for-labelling.py --grades PATH [--budget N] [--held-out-from ID]
"""

from __future__ import annotations

import argparse
import json
import random
import sys

DEFAULT_BUDGET = 60
DEFAULT_HELD_OUT_FROM = 122
SEED = 20260826


def allocate(dev_by_stratum: dict, budget: int) -> dict:
    """Split the dev budget evenly between the harness-pass and harness-fail strata.

    Even rather than proportional: the false-pass cell — human fail, harness pass —
    lives entirely in the harness-PASS stratum and is the rarest thing being
    measured, so starving that stratum to chase false alarms leaves TNR resting on
    one or two cases. A stratum smaller than its share contributes everything it has
    and the remainder goes to the other.
    """
    strata = sorted(dev_by_stratum)
    take = {}
    remaining, left = budget, list(strata)
    while left:
        share = remaining // len(left)
        name = min(left, key=lambda s: len(dev_by_stratum[s]))
        take[name] = min(share, len(dev_by_stratum[name]))
        remaining -= take[name]
        left.remove(name)
    return take


def main(argv) -> int:
    p = argparse.ArgumentParser(prog="sample-for-labelling")
    p.add_argument("--grades", required=True, help="eval-grade.py --json output")
    p.add_argument("--budget", type=int, default=DEFAULT_BUDGET,
                   help="total labels affordable, held-out tranche included")
    p.add_argument("--held-out-from", type=int, default=DEFAULT_HELD_OUT_FROM)
    p.add_argument("--out", default=None, help="write the id list here for --only")
    args = p.parse_args(argv)

    try:
        with open(args.grades, encoding="utf-8") as f:
            results = json.load(f)["results"]
    except (OSError, ValueError, KeyError) as exc:
        sys.stderr.write(f"sample-for-labelling: cannot read grades: {exc}\n")
        return 64

    held_out, dev_by_stratum = [], {}
    for r in results:
        cid, split = r["case_id"], r.get("split")
        verdict = "pass" if r.get("status") == "pass" else "fail"
        if split == "test" and cid >= args.held_out_from:
            held_out.append(cid)
        elif split == "dev":
            dev_by_stratum.setdefault(verdict, []).append(cid)

    if not dev_by_stratum:
        sys.stderr.write("sample-for-labelling: no dev cases in the grades\n")
        return 64

    rng = random.Random(SEED)
    take = allocate(dev_by_stratum, max(0, args.budget - len(held_out)))
    chosen, manifest = list(held_out), {}
    for stratum, ids in sorted(dev_by_stratum.items()):
        picked = sorted(rng.sample(sorted(ids), take.get(stratum, 0)))
        chosen += picked
        manifest[f"dev/{stratum}"] = {"population": len(ids), "sampled": len(picked)}
    manifest["test/held-out"] = {"population": len(held_out), "sampled": len(held_out)}

    chosen = sorted(set(chosen))
    for name, m in sorted(manifest.items()):
        frac = m["sampled"] / m["population"] if m["population"] else 0
        print(f"  {name:18} {m['sampled']:3} of {m['population']:3}  "
              f"({frac:.0%}, weight {1 / frac:.2f})" if frac else
              f"  {name:18} {m['sampled']:3} of {m['population']:3}")
    print(f"\n{len(chosen)} cases to label "
          f"({len(held_out)} held out, {len(chosen) - len(held_out)} dev)")
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            json.dump(chosen, f)
        print(f"-> {args.out}")
    else:
        print(json.dumps(chosen))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
