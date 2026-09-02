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
`test` membership nominal below the floor it records: those cases have been read,
whether they predate the corpus reset or were spent by a later labelling pass.
Only the ids at or above the floor were pinned before any capture saw them, and
there are few enough that sampling them would leave nothing to measure. They are
taken entire and reported apart, which makes `--budget` a ceiling the tranche can
exceed: that conflict is refused rather than resolved by trimming either side.

Between batches the manifest records no floor at all, because the pass that spends a
tranche deletes it. That is not a defect to route around -- a run needing held-out
cases needs a batch nobody has read, so this exits 64 and says so.

Usage: sample-for-labelling.py --grades PATH [--budget N] [--held-out-from ID]
"""

from __future__ import annotations

import argparse
import json
import os
import random
import sys

DEFAULT_BUDGET = 60
SEED = 20260826

SPLIT_MANIFEST = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "splits", "request-plan.json")


def held_out_floor(manifest_path: str) -> int:
    """First id of the tranche still unread. Raises `LookupError` rather than
    defaulting: a stale floor re-samples a spent tranche and reports the result as
    held-out, which is the one error no output here would reveal.

    An absent key is a legitimate manifest state, not damage: it is deleted by the
    edit that spends a tranche and re-pinned by the edit that appends the successor.
    It is reported apart because its remedy is the opposite one -- pin a NEW batch,
    never re-name the spent tranche the manifest just stopped vouching for.
    """
    try:
        with open(manifest_path, encoding="utf-8") as f:
            manifest = json.load(f)
        if "held_out_from" in manifest:
            return int(manifest["held_out_from"])
    except (OSError, ValueError, TypeError) as exc:
        raise LookupError(
            f"no usable held_out_from in {manifest_path} ({exc}); "
            f"pass --held-out-from with the first id of the current tranche") from exc
    raise LookupError(
        f"{manifest_path} pins no held_out_from, so nothing in it is held out right "
        f"now: the last tranche was spent by a labelling pass and no successor has "
        f"been appended. Append a batch and pin its first id there, or pass "
        f"--held-out-from to name a tranche for this run -- but not a spent one")


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
                   help="ceiling on total labels, held-out tranche included; a budget "
                        "below the tranche is refused, never silently exceeded")
    p.add_argument("--held-out-from", type=int, default=None,
                   help="first id of the current tranche; defaults to the "
                        "held_out_from recorded in the split manifest")
    p.add_argument("--out", default=None, help="write the id list here for --only")
    args = p.parse_args(argv)

    if args.held_out_from is None:
        try:
            args.held_out_from = held_out_floor(SPLIT_MANIFEST)
        except LookupError as exc:
            sys.stderr.write(f"sample-for-labelling: {exc}\n")
            return 64

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

    # Refused rather than clamped. A partial tranche is still reported at a sampling
    # fraction of 1.0, which `label-align.py` divides back out as if the whole tranche
    # had been drawn — so trimming here would understate the held-out population and
    # nothing downstream could tell. The operator picks which constraint gives.
    if args.budget < len(held_out):
        sys.stderr.write(
            f"sample-for-labelling: budget {args.budget} is below the held-out tranche "
            f"({len(held_out)} ids at or above {args.held_out_from}), which is taken "
            f"whole or not at all. Raise --budget to at least {len(held_out)}, or pass "
            f"--held-out-from to name a smaller tranche\n")
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
