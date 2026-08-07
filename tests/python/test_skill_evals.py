"""Skill-eval assertion engine + eval-set lint.

Offline and free: grades captured responses and pins the eval sets themselves as
binary and code-checkable. Capturing a response is a separate, opt-in live step —
nothing here dispatches a model.
"""

import json
import os
import re
import unittest

_REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
_EVAL_SETS = [os.path.join(_REPO, "skills", "request-plan", "evals", "evals.json")]

_TYPES = {"contains_all", "contains_none", "regex_all", "regex_any"}


def check(assertion: dict, response: str) -> bool:
    """Decide one assertion against a response. Every type is objectively decidable."""
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


def grade(eval_set: dict, case_id: int, response: str) -> dict:
    """Score one response against a case's shared + case-specific assertions."""
    case = next(c for c in eval_set["evals"] if c["id"] == case_id)
    assertions = eval_set.get("shared_assertions", []) + case.get("assertions", [])
    failed = [a["id"] for a in assertions if not check(a, response)]
    return {"case_id": case_id, "total": len(assertions),
            "passed": len(assertions) - len(failed), "failed": failed}


def _load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


class AssertionEngine(unittest.TestCase):
    def test_contains_all(self):
        self.assertTrue(check({"type": "contains_all", "values": ["a", "b"]}, "a b"))
        self.assertFalse(check({"type": "contains_all", "values": ["a", "z"]}, "a b"))

    def test_contains_none(self):
        self.assertTrue(check({"type": "contains_none", "values": ["z"]}, "a b"))
        self.assertFalse(check({"type": "contains_none", "values": ["a"]}, "a b"))

    def test_regex_all_is_multiline(self):
        self.assertTrue(check({"type": "regex_all", "values": ["^b$"]}, "a\nb\nc"))
        self.assertFalse(check({"type": "regex_all", "values": ["^z$"]}, "a\nb"))

    def test_regex_any(self):
        self.assertTrue(check({"type": "regex_any", "values": ["z", "b"]}, "a b"))
        self.assertFalse(check({"type": "regex_any", "values": ["y", "z"]}, "a b"))

    def test_unknown_type_raises(self):
        with self.assertRaises(ValueError):
            check({"type": "vibes", "values": []}, "anything")


class Grading(unittest.TestCase):
    def setUp(self):
        self.eval_set = _load(_EVAL_SETS[0])

    def _plan(self, **overrides):
        parts = {
            "sections": ("# Plan: x\n## Context\nc\n## Goal\ng\n## Scope\n"
                         "**In:** a\n**Out:** b\n## Phases\n"
                         "| P0 — Required | x | y |\n| P1 — Nice-to-have | x | y |\n"
                         "| P2 — v1.1 | x | y |\n"),
            "effort": "## Effort (rough)\n| M | 12 | drivers |\n",
            "risks": "## Risks & Dependencies\n- r\n",
            "handoff": '/worktask "do the thing"\n',
        }
        parts.update(overrides)
        return "".join(parts.values())

    def test_a_conforming_plan_passes_every_shared_assertion(self):
        result = grade(self.eval_set, 1, self._plan() + "wake from sleep\n")
        self.assertEqual(result["failed"], [], result)

    def test_missing_out_of_scope_fails_that_assertion(self):
        plan = self._plan(sections="## Context\nc\n## Goal\ng\n## Scope\n**In:** a\n"
                                   "## Phases\n| P0 — Required |\n| P1 — Nice-to-have |\n"
                                   "| P2 — v1.1 |\n")
        result = grade(self.eval_set, 1, plan + "wake\n")
        self.assertIn("scope-names-in-and-out", result["failed"])

    def test_effort_assertion_rejects_a_stray_digit(self):
        """Prose mentioning a number is not a size + complexity score."""
        plan = self._plan(effort="## Effort (rough)\nroughly 3 days of work\n")
        self.assertIn("effort-sized-with-complexity", grade(self.eval_set, 1, plan + "wake\n")["failed"])

    def test_effort_assertion_accepts_the_template_table(self):
        result = grade(self.eval_set, 1, self._plan() + "wake\n")
        self.assertNotIn("effort-sized-with-complexity", result["failed"])

    def test_separate_test_phase_fails(self):
        result = grade(self.eval_set, 1, self._plan() + "wake\nP1 — Testing\n")
        self.assertIn("no-separate-test-phase", result["failed"])

    def test_security_case_requires_the_secure_tier(self):
        plain = self._plan() + "Keychain credential migration\n"
        self.assertIn("routes-to-secure-tier", grade(self.eval_set, 3, plain)["failed"])

        secure = self._plan(handoff='/worktask --secure "migrate settings"\n') + "Keychain\n"
        self.assertNotIn("routes-to-secure-tier", grade(self.eval_set, 3, secure)["failed"])


class EvalSetLint(unittest.TestCase):
    """Keeps eval sets binary and code-checkable — the failure mode that made the
    previous version of this file unusable was prose expectations with no grader."""

    def test_every_case_has_at_least_one_assertion(self):
        for path in _EVAL_SETS:
            eval_set = _load(path)
            shared = eval_set.get("shared_assertions", [])
            for case in eval_set["evals"]:
                self.assertTrue(shared or case.get("assertions"),
                                f"{path} case {case['id']} has no assertions")

    def test_no_case_carries_a_prose_expectation(self):
        for path in _EVAL_SETS:
            for case in _load(path)["evals"]:
                self.assertNotIn("expected_output", case,
                                 f"{path} case {case['id']} still uses an ungradeable prose expectation")

    def test_assertion_types_are_known_and_regexes_compile(self):
        for path in _EVAL_SETS:
            eval_set = _load(path)
            for a in eval_set.get("shared_assertions", []) + [
                    a for c in eval_set["evals"] for a in c.get("assertions", [])]:
                self.assertIn(a["type"], _TYPES, a["id"])
                self.assertTrue(a.get("why"), f"{a['id']} must say what failure it targets")
                if a["type"].startswith("regex"):
                    for pattern in a["values"]:
                        re.compile(pattern)

    def test_assertion_ids_are_unique_within_a_case(self):
        for path in _EVAL_SETS:
            eval_set = _load(path)
            shared = [a["id"] for a in eval_set.get("shared_assertions", [])]
            for case in eval_set["evals"]:
                ids = shared + [a["id"] for a in case.get("assertions", [])]
                self.assertEqual(len(ids), len(set(ids)), f"{path} case {case['id']}")


if __name__ == "__main__":
    unittest.main()
