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
import importlib.util
import json
import os
import sys

_ENGINE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "eval-engine.py")
_spec = importlib.util.spec_from_file_location("eval_engine", _ENGINE_PATH)
engine = importlib.util.module_from_spec(_spec)
sys.modules["eval_engine"] = engine
_spec.loader.exec_module(engine)


def grade_record(eval_set: dict, record: dict) -> dict:
    """Score one stored record, refusing when it answers a superseded prompt."""
    cid = record["case_id"]
    current_prompt = engine.prompt_digest(eval_set, cid)
    if record.get("prompt_digest") != current_prompt:
        return {"case_id": cid, "status": "stale",
                "reason": (f"prompt changed since capture "
                           f"(stored {record.get('prompt_digest')}, now {current_prompt})")}
    result = engine.grade(eval_set, cid, record["response"])
    if result["outcome"] == "clarify":
        result["status"] = "clarify"
    else:
        result["status"] = "pass" if not result["failed"] else "fail"
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
    p.add_argument("--json", action="store_true")
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

    ids = [c["id"] for c in eval_set["evals"]]
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
        if result["status"] == "stale":
            stale.append(cid)
        results.append(result)

    # Clarifications sit outside pass/fail: the skill declined to answer, so its
    # plan quality was never exercised and folding it either way would lie.
    clarified = [r for r in results if r["status"] == "clarify"]
    graded = [r for r in results if r["status"] not in ("stale", "clarify")]
    failed = [r for r in graded if r["status"] == "fail"]
    summary = {
        "skill": eval_set["skill_name"],
        "graded": len(graded), "passed": len(graded) - len(failed), "failed": len(failed),
        "clarified": [r["case_id"] for r in clarified],
        "missing_captures": missing, "stale_captures": stale, "results": results,
    }

    if args.json:
        print(json.dumps(summary, indent=2, ensure_ascii=False))
    else:
        for r in results:
            if r["status"] == "stale":
                print(f"  case {r['case_id']}: STALE — {r['reason']}")
                continue
            if r["status"] == "clarify":
                print(f"  case {r['case_id']}: CLARIFY — asked instead of planning; not scored")
                continue
            mark = "PASS" if r["status"] == "pass" else "FAIL"
            detail = f" (failed: {', '.join(r['failed'])})" if r["failed"] else ""
            moved = "  [assertions changed since capture]" if r["assertions_moved"] else ""
            print(f"  case {r['case_id']}: {mark} {r['passed']}/{r['total']}{detail}{moved}")
        if missing:
            print(f"  missing captures: {missing}")
        if summary["clarified"]:
            print(f"  clarified (unscored): {summary['clarified']}")
        print(f"{eval_set['skill_name']}: {summary['passed']}/{summary['graded']} passed")

    if stale:
        return 2
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
