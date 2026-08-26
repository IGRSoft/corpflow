#!/usr/bin/env python3
"""eval-grade — score captured responses offline with the shared assertion engine.

Free and deterministic; every input is already on disk.

A `prompt_digest` mismatch is a hard refusal: the stored response answers a
question the eval set no longer asks, and scoring it would report a number about
text nobody sent. An `assertions_digest` mismatch is only flagged — the response
stands, the grading contract moved under it.

Usage:
  eval-grade.py --eval-set <path> [--responses D] [--case ID]... [--json]

Exit codes: 0 all graded cases passed / 1 at least one case failed
/ 2 a stored response is stale or unreadable / 64 bad usage.
"""

from __future__ import annotations

import argparse
import collections
import importlib.util
import json
import os
import sys

_ENGINE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "eval-engine.py")
_spec = importlib.util.spec_from_file_location("eval_engine", _ENGINE_PATH)
engine = importlib.util.module_from_spec(_spec)
sys.modules["eval_engine"] = engine
_spec.loader.exec_module(engine)


REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def repo_resolver(rel: str) -> bool:
    """A cited path counts only if it exists here — an invented path is the failure
    paths_resolve is looking for."""
    return os.path.exists(os.path.join(REPO, rel))


def grade_record(eval_set: dict, record: dict) -> dict:
    """Score one stored record, refusing when it answers a superseded prompt."""
    cid = record["case_id"]
    current_prompt = engine.prompt_digest(eval_set, cid)
    if record.get("prompt_digest") != current_prompt:
        return {"case_id": cid, "status": "stale",
                "reason": (f"prompt changed since capture "
                           f"(stored {record.get('prompt_digest')}, now {current_prompt})")}
    result = engine.grade(eval_set, cid, record["response"], repo_resolver)
    # Every case declares which outcome it expects, so a question is scorable either
    # way: excusing an unexpected one hid 9 of 32 human-labelled failures from the
    # denominator — the exact defect (asked instead of planning) the ask-or-plan rule
    # was written to fix, made unmeasurable by the grader.
    result["status"] = "pass" if not result["failed"] else "fail"
    result["asked_instead"] = (result["expected_outcome"] != "clarify"
                               and result["outcome"] == "clarify")
    result["assertions_moved"] = (
        record.get("assertions_digest") != engine.assertions_digest(eval_set, cid))
    result["model"] = record.get("model")
    result["captured_at"] = record.get("captured_at")
    return result


def main(argv_in: list) -> int:
    p = argparse.ArgumentParser(prog="eval-grade", add_help=True)
    p.add_argument("--eval-set", required=True)
    p.add_argument("--responses", default=None)
    p.add_argument("--case", action="append", type=int, default=None)
    p.add_argument("--split", choices=("train", "dev", "test"), default=None,
                   help="grade only this tranche; test stays unread until judge validation")
    p.add_argument("--json", action="store_true")
    p.add_argument("--allow-mixed", action="store_true",
                   help="grade across skill versions anyway; the score describes no single skill")
    try:
        args = p.parse_args(argv_in)
    except SystemExit:
        return 64

    try:
        with open(args.eval_set, encoding="utf-8") as f:
            eval_set = json.load(f)
    except (OSError, ValueError) as exc:
        sys.stderr.write(f"eval-grade: cannot read eval set: {exc}\n")
        return 64

    responses_dir = args.responses or os.path.join(
        os.path.dirname(os.path.abspath(args.eval_set)), "responses")
    if not os.path.isdir(responses_dir):
        sys.stderr.write(
            f"eval-grade: no responses at {responses_dir}; run eval-capture.py first\n")
        return 2

    ids = [c["id"] for c in eval_set["evals"]
           if args.split is None or c.get("split") == args.split]
    selected = ids if not args.case else [i for i in ids if i in args.case]

    results, missing, stale = [], [], []
    for cid in selected:
        path = os.path.join(responses_dir, f"{cid}.json")
        if not os.path.exists(path):
            missing.append(cid)
            continue
        try:
            with open(path, encoding="utf-8") as f:
                record = json.load(f)
        except (OSError, ValueError) as exc:
            sys.stderr.write(f"eval-grade: case {cid} unreadable: {exc}\n")
            stale.append(cid)
            continue
        result = grade_record(eval_set, record)
        result["skill_version"] = record.get("skill_version")
        result["dimensions"] = engine.find_case(eval_set, cid).get("dimensions", {})
        # Carried so the grades file is self-describing. `label-align.py` needs it to
        # size each stratum's population, and `sample-for-labelling.py` to keep the
        # held-out tranche out of the pool it draws from — neither should have to
        # re-open the eval set and risk reading a different one than was graded.
        result["split"] = engine.find_case(eval_set, cid).get("split")
        if result["status"] == "stale":
            stale.append(cid)
        results.append(result)

    # Reported separately for visibility, but inside the denominator: asking when the
    # case wanted a plan is a wrong answer, not an abstention.
    # One headline over two skill versions is a chimera: 75 v0.4.0 records averaged with
    # 46 v0.5.0 records reported "89/121 passed", a number describing no skill that exists.
    # Refused rather than warned — a warning above a plausible number gets read past.
    versions = sorted({r.get("skill_version") for r in results if r.get("skill_version")})
    if len(versions) > 1 and not args.allow_mixed:
        counts = collections.Counter(r.get("skill_version") for r in results)
        sys.stderr.write(
            "eval-grade: responses span skill versions "
            + ", ".join(f"{v}x{counts[v]}" for v in versions)
            + "; one score over them describes no skill.\n"
              "  Re-capture the older ones, grade with --case/--split, or pass "
              "--allow-mixed if a spanning number is genuinely what you want.\n")
        return 2

    clarified = [r for r in results if r.get("asked_instead")]
    graded = [r for r in results if r["status"] != "stale"]
    failed = [r for r in graded if r["status"] == "fail"]
    by_dimension: dict = {}
    for result in graded:
        for axis, value in result.get("dimensions", {}).items():
            passed, total = by_dimension.setdefault(axis, {}).get(value, (0, 0))
            by_dimension[axis][value] = (passed + (result["status"] == "pass"), total + 1)

    summary = {
        "skill": eval_set["skill_name"],
        "graded": len(graded), "passed": len(graded) - len(failed), "failed": len(failed),
        "clarified": [r["case_id"] for r in clarified],
        "by_dimension": by_dimension,
        "missing_captures": missing, "stale_captures": stale, "results": results,
    }

    if args.json:
        print(json.dumps(summary, indent=2, ensure_ascii=False))
    else:
        for r in results:
            if r["status"] == "stale":
                print(f"  case {r['case_id']}: STALE — {r['reason']}")
                continue
            if r.get("asked_instead"):
                print(f"  case {r['case_id']}: FAIL — asked instead of planning")
                continue
            mark = "PASS" if r["status"] == "pass" else "FAIL"
            detail = f" (failed: {', '.join(r['failed'])})" if r["failed"] else ""
            moved = "  [assertions changed since capture]" if r["assertions_moved"] else ""
            print(f"  case {r['case_id']}: {mark} {r['passed']}/{r['total']}{detail}{moved}")
        if missing:
            print(f"  missing captures: {missing}")
        if summary["clarified"]:
            print(f"  asked instead of planning (scored as failures): {summary['clarified']}")
        for axis, rates in summary["by_dimension"].items():
            print(f"\n  by {axis}:")
            for value, (passed, total) in sorted(rates.items()):
                bar = "" if not total else f"  {100 * passed // total}%"
                print(f"    {value:<10} {passed}/{total}{bar}")
        print(f"\n{eval_set['skill_name']}: {summary['passed']}/{summary['graded']} passed")

    if stale:
        return 2
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
