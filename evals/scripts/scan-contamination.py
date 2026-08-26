#!/usr/bin/env python3
"""scan-contamination — find captured responses that noticed they were captured.

The capture tree strips the answer key, so no response can read an
`expected_outcome`. It cannot strip the fact that a strip happened: `git status`
reports the removed files as deleted, and `git log` carries the commit messages of
the work that built the harness. A response that reads either learns it is inside
an eval, which is the 0.0.1 defect in a quieter form — it does not hand over the
answer, it hands over the situation.

Three channels, kept apart because they are fixed differently:

  answer-key   the actual verdict was readable. Fatal; the case is evidence of
               nothing and must be excluded, not discounted.
  strip        the strip is visible as deletions in `git status`.
  harness-log  `git log` names the capture work.

Cases that legitimately GROUND on eval tooling are exempt from the path-shaped
channels: a plan about `label-align.py` is supposed to name `evals/labels/`, and
scoring that as a leak would refuse the correct answer.

Reports rather than judges. Whether a rate bounds a finding or voids it is a
question for whoever reads the number.

Usage: scan-contamination.py [--eval-set PATH] [--responses DIR] [--json]
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

CHANNELS = {
    "answer-key": (
        r"expected_outcome",
        "read the case's own verdict — fatal",
    ),
    "strip": (
        r"currently showing as deleted|showing as deleted|housekeeping deletion"
        r"|deletions? (?:in|of) `?evals",
        "saw the answer key removed, via git status",
    ),
    "harness-log": (
        r"#333|eval-capture\.py|capture pipeline",
        "read the harness work in git log",
    ),
    "self-aware": (
        r"eval case|answer key|ground truth|being evaluated|this is an eval"
        r"|testing the skill",
        "said outright that it was inside an eval",
    ),
}
# Only these two are about paths, so only these two are excusable by grounding.
GROUNDED_EXEMPT = ("strip", "harness-log")


def grounded_on_evals(eval_set: dict) -> set:
    return {c["id"] for c in eval_set["evals"]
            if any("evals/" in p for p in (c.get("grounding") or []))}


def scan(eval_set: dict, responses_dir: str) -> dict:
    exempt = grounded_on_evals(eval_set)
    found = {name: [] for name in CHANNELS}
    total = 0
    for path in sorted(glob.glob(os.path.join(responses_dir, "*.json"))):
        try:
            with open(path, encoding="utf-8") as f:
                record = json.load(f)
        except (OSError, ValueError):
            continue
        total += 1
        cid, text = record.get("case_id"), record.get("response") or ""
        for name, (pattern, _) in CHANNELS.items():
            if name in GROUNDED_EXEMPT and cid in exempt:
                continue
            if re.search(pattern, text, re.IGNORECASE):
                found[name].append(cid)
    tainted = sorted({c for ids in found.values() for c in ids})
    return {"total": total, "by_channel": {k: sorted(v) for k, v in found.items()},
            "tainted": tainted,
            "rate": (len(tainted) / total) if total else 0.0}


def main(argv) -> int:
    p = argparse.ArgumentParser(prog="scan-contamination")
    p.add_argument("--eval-set", default=os.path.join(
        REPO, "skills", "request-plan", "evals", "evals.json"))
    p.add_argument("--responses", default=None)
    p.add_argument("--json", action="store_true")
    args = p.parse_args(argv)

    try:
        with open(args.eval_set, encoding="utf-8") as f:
            eval_set = json.load(f)
    except (OSError, ValueError) as exc:
        sys.stderr.write(f"scan-contamination: cannot read eval set: {exc}\n")
        return 64
    responses = args.responses or os.path.join(
        os.path.dirname(os.path.abspath(args.eval_set)), "responses")
    if not os.path.isdir(responses):
        sys.stderr.write(f"scan-contamination: no responses at {responses}\n")
        return 2

    report = scan(eval_set, responses)
    for name, (_, why) in CHANNELS.items():
        ids = report["by_channel"][name]
        print(f"  {name:12} {len(ids):3}  {why}")
        if ids:
            print(f"               {ids}")
    print(f"\n{len(report['tainted'])} of {report['total']} responses tainted "
          f"({report['rate']:.0%})")
    if report["by_channel"]["answer-key"]:
        print("An answer-key read is not a discount — exclude those cases.")
    if args.json:
        print(json.dumps(report, indent=2))
    # rc 1 only for the fatal channel; the others bound a claim, they do not void it.
    return 1 if report["by_channel"]["answer-key"] else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
