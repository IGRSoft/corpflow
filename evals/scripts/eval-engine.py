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
import os
import re

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def load_eval_set(path: str) -> dict:
    """Reads and parses only. Each caller keeps its own exit code and prog-prefixed
    message, because one shared verdict makes eval-grade's usage error and
    build-review-page's crash indistinguishable to whoever is reading stderr."""
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def responses_dir(eval_set_path: str, override: str | None = None) -> str:
    """Where a capture wrote its answers: beside the eval set that produced them.

    Existence is the caller's question — the three consumers disagree on whether an
    absent directory is a decline, a hard error, or an empty page, and that
    disagreement is deliberate.
    """
    if override:
        return override
    return os.path.join(os.path.dirname(os.path.abspath(eval_set_path)), "responses")


ASSERTION_TYPES = frozenset({"contains_all", "contains_none", "regex_all", "regex_any",
                             "regex_none", "paths_resolve"})

_PATH_RE = re.compile(r"[\w.-]+(?:/[\w.-]+)+\.(?:py|sh|md|json|bats|swift|toml)")


def cited_paths(response: str) -> list:
    return sorted(set(_PATH_RE.findall(response)))


def check(assertion: dict, response: str, resolver=None) -> bool:
    """`resolver` decides whether a cited path exists; required only by paths_resolve,
    which is the one type that cannot be settled from the text alone."""
    kind, values = assertion["type"], assertion["values"]
    if kind == "contains_all":
        return all(v in response for v in values)
    if kind == "contains_none":
        return not any(v in response for v in values)
    if kind == "regex_all":
        return all(re.search(v, response, re.MULTILINE) for v in values)
    if kind == "regex_any":
        return any(re.search(v, response, re.MULTILINE) for v in values)
    if kind == "regex_none":
        # contains_none over a bare literal cannot express "no trigger LINE": banning the
        # string "/worktask" failed the two refutations that named it only to decline it
        # ("no `/worktask` command to hand off"), which is the correct answer.
        return not any(re.search(v, response, re.MULTILINE) for v in values)
    if kind == "paths_resolve":
        # Tests grounding without naming the target: an author's guess at WHICH file
        # the plan should reach failed three plans that reached a better one.
        if resolver is None:
            raise ValueError("paths_resolve needs a resolver")
        need = int(values[0]) if values else 1
        return sum(1 for p in cited_paths(response) if resolver(p)) >= need
    raise ValueError(f"unknown assertion type: {kind}")


def find_case(eval_set: dict, case_id: int) -> dict:
    return next(c for c in eval_set["evals"] if c["id"] == case_id)


def assertions_for(eval_set: dict, case_id: int) -> list:
    """Shared assertions apply to every case; case assertions extend them.

    Except on a `refute` case, where the shared set IS the thing that misfires: the
    plan template cannot be satisfied by a correct "this already shipped" answer, so
    a refute case carries only its own assertions.
    """
    case = find_case(eval_set, case_id)
    if case.get("expected_outcome") == "refute":
        return list(case.get("assertions", []))
    return eval_set.get("shared_assertions", []) + case.get("assertions", [])


PLAN_SECTIONS = ("Context", "Goal", "Scope", "Phases", "Effort", "Risks")

# Enough sections to prove a plan was attempted, whatever heading syntax was used.
# Matching on `## Context` instead misread a full plan that used `**Context**` as a
# refusal, which silently drops good plans out of the denominator.
PLAN_SECTION_QUORUM = 3


def classify_outcome(response: str) -> str:
    """`clarify` when the skill asked instead of answering: too few plan sections.

    One-directional, and it must stay that way: this may reclassify a `plan` as a
    `clarify`, never the reverse. A question mark used to break the tie below the
    quorum, which let punctuation alone decide a verdict. Requiring MORE than a
    question mark instead is the reverse move and was measured: it read four genuine
    questions as plans, each because it named the handoff trigger while asking about it.
    """
    present = sum(1 for section in PLAN_SECTIONS if section in response)
    return "plan" if present >= PLAN_SECTION_QUORUM else "clarify"


def expected_outcome(eval_set: dict, case_id: int) -> str:
    return find_case(eval_set, case_id).get("expected_outcome", "plan")


def grade(eval_set: dict, case_id: int, response: str, resolver=None) -> dict:
    """A case expecting a clarification is scored on that alone — its assertions
    describe a plan that should never have been written."""
    outcome = classify_outcome(response)
    expected = expected_outcome(eval_set, case_id)
    if expected == "clarify":
        matched = outcome == "clarify"
        return {"case_id": case_id, "total": 1, "passed": int(matched),
                "failed": [] if matched else ["should-have-asked-not-planned"],
                "outcome": outcome, "expected_outcome": expected}
    if expected == "refute":
        # The prompt's premise is false — the work already shipped, or the file it
        # describes no longer looks like that. The right answer disputes it with
        # evidence, so the plan template misfires wholesale: case 2 failed six
        # assertions while being correct.
        #
        # Registered per case by a human who checked the premise, NEVER inferred from
        # the response. Detecting "this looks like a refutation" would let any response
        # opt out of the template by sounding like one, which is how CLARIFY once
        # dropped 9 of 32 known failures out of the denominator. A refute case is
        # scored, stays in the denominator, and fails when it plans anyway.
        assertions = assertions_for(eval_set, case_id)
        failed = [a["id"] for a in assertions if not check(a, response, resolver)]
        return {"case_id": case_id, "total": len(assertions),
                "passed": len(assertions) - len(failed), "failed": failed,
                "outcome": outcome, "expected_outcome": expected}
    if outcome == "clarify":
        # One decision went wrong, not six. Scoring a question against the plan
        # assertions reported 31 defects across 6 traces and buried the 8 real ones.
        return {"case_id": case_id, "total": 1, "passed": 0,
                "failed": ["asked-instead-of-planning"],
                "outcome": outcome, "expected_outcome": expected}
    assertions = assertions_for(eval_set, case_id)
    failed = [a["id"] for a in assertions if not check(a, response, resolver)]
    return {"case_id": case_id, "total": len(assertions),
            "passed": len(assertions) - len(failed), "failed": failed,
            "outcome": outcome, "expected_outcome": expected}


def _digest(payload) -> str:
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()[:16]


def prompt_digest(eval_set: dict, case_id: int) -> str:
    return _digest(find_case(eval_set, case_id)["prompt"])


def assertions_digest(eval_set: dict, case_id: int) -> str:
    return _digest(assertions_for(eval_set, case_id))
