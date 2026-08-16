#!/usr/bin/env python3
"""Binary assertion engine + digests for per-skill eval sets.

The single grader for capture, offline grading, and the test suite; a second copy
would let two scores of the same response disagree.

Two digests, because they invalidate different things: a changed `prompt_digest`
voids the stored response, a changed `assertions_digest` only makes its score
stale. One combined hash would force a paid re-capture on every reworded assertion.

Pure, stdlib-only, no model calls.
"""

from __future__ import annotations

import hashlib
import json
import re

ASSERTION_TYPES = frozenset({"contains_all", "contains_none", "regex_all", "regex_any"})


def check(assertion: dict, response: str) -> bool:
    kind, values = assertion["type"], assertion["values"]
    if kind == "contains_all":
        return all(v in response for v in values)
    if kind == "contains_none":
        return not any(v in response for v in values)
    if kind == "regex_all":
        return all(re.search(v, response, re.MULTILINE) for v in values)
    if kind == "regex_any":
        return any(re.search(v, response, re.MULTILINE) for v in values)
    raise ValueError(f"unknown assertion type: {kind}")


def find_case(eval_set: dict, case_id: int) -> dict:
    return next(c for c in eval_set["evals"] if c["id"] == case_id)


def assertions_for(eval_set: dict, case_id: int) -> list:
    """Shared assertions apply to every case; case assertions extend them."""
    case = find_case(eval_set, case_id)
    return eval_set.get("shared_assertions", []) + case.get("assertions", [])


def grade(eval_set: dict, case_id: int, response: str) -> dict:
    assertions = assertions_for(eval_set, case_id)
    failed = [a["id"] for a in assertions if not check(a, response)]
    return {"case_id": case_id, "total": len(assertions),
            "passed": len(assertions) - len(failed), "failed": failed}


def _digest(payload) -> str:
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()[:16]


def prompt_digest(eval_set: dict, case_id: int) -> str:
    return _digest(find_case(eval_set, case_id)["prompt"])


def assertions_digest(eval_set: dict, case_id: int) -> str:
    return _digest(assertions_for(eval_set, case_id))
