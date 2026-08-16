"""Skill-eval assertion engine + eval-set lint.

Offline and free: `grade()` scores a response the caller supplies; the lint pins
the eval sets as binary and code-checkable. Graded scores of real model output
come from `evals/scripts/eval-grade.py` over captured responses — a pass here
proves the engine and the sets, never a skill's output quality.
"""

import json
import os
import re
import unittest

from _scriptimport import EVAL_ENGINE, load_module

_engine = load_module(EVAL_ENGINE, "eval_engine")
check = _engine.check
grade = _engine.grade

_REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
_EVAL_SETS = [os.path.join(_REPO, "skills", "request-plan", "evals", "evals.json")]

_TYPES = set(_engine.ASSERTION_TYPES)

# Satisfies case 1's own assertions so these fixtures exercise the shared ones in isolation.
_CASE1_TOKEN = "test-execution-gate rerun after a tree change\n"


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
        result = grade(self.eval_set, 1, self._plan() + _CASE1_TOKEN)
        self.assertEqual(result["failed"], [], result)

    def test_missing_out_of_scope_fails_that_assertion(self):
        plan = self._plan(sections="## Context\nc\n## Goal\ng\n## Scope\n**In:** a\n"
                                   "## Phases\n| P0 — Required |\n| P1 — Nice-to-have |\n"
                                   "| P2 — v1.1 |\n")
        result = grade(self.eval_set, 1, plan + _CASE1_TOKEN)
        self.assertIn("scope-names-in-and-out", result["failed"])

    def test_effort_assertion_rejects_a_stray_digit(self):
        """Prose mentioning a number is not a size + complexity score."""
        plan = self._plan(effort="## Effort (rough)\nroughly 3 days of work\n")
        self.assertIn("effort-sized-with-complexity", grade(self.eval_set, 1, plan + _CASE1_TOKEN)["failed"])

    def test_effort_assertion_accepts_the_template_table(self):
        result = grade(self.eval_set, 1, self._plan() + _CASE1_TOKEN)
        self.assertNotIn("effort-sized-with-complexity", result["failed"])

    def test_effort_assertion_accepts_an_approximated_score(self):
        """`~8` answers the question; rejecting it failed a correct plan for hedging."""
        for score in ("~8", "≈8", "8"):
            plan = self._plan(effort=f"## Effort (rough)\n| S | {score} | drivers |\n")
            self.assertNotIn("effort-sized-with-complexity",
                             grade(self.eval_set, 1, plan + _CASE1_TOKEN)["failed"], score)

    def test_effort_assertion_still_rejects_an_out_of_range_score(self):
        plan = self._plan(effort="## Effort (rough)\n| S | ~99 | drivers |\n")
        self.assertIn("effort-sized-with-complexity",
                      grade(self.eval_set, 1, plan + _CASE1_TOKEN)["failed"])

    def test_separate_test_phase_fails(self):
        result = grade(self.eval_set, 1, self._plan() + _CASE1_TOKEN + "P1 — Testing\n")
        self.assertIn("no-separate-test-phase", result["failed"])

    def test_security_case_requires_the_secure_tier(self):
        plain = self._plan() + "credential exposure in headless runs\n"
        self.assertIn("routes-to-secure-tier", grade(self.eval_set, 3, plain)["failed"])

        secure = (self._plan(handoff='/worktask --secure "harden the deny-list"\n')
                  + "credential exposure in headless runs\n")
        self.assertNotIn("routes-to-secure-tier", grade(self.eval_set, 3, secure)["failed"])
        self.assertNotIn("flags-security-sensitive", grade(self.eval_set, 3, secure)["failed"])


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

    def test_every_case_is_grounded_in_paths_that_exist(self):
        """A case describing a surface this repo lacks can only ever be refused —
        the first live run burned $1.47 on two such cases before this existed."""
        for path in _EVAL_SETS:
            for case in _load(path)["evals"]:
                grounding = case.get("grounding")
                self.assertTrue(grounding, f"{path} case {case['id']} declares no grounding")
                for rel in grounding:
                    self.assertTrue(os.path.exists(os.path.join(_REPO, rel)),
                                    f"{path} case {case['id']} grounds on missing {rel}")

    def test_no_assertion_can_be_satisfied_by_echoing_the_prompt(self):
        """A value already in the case's own prompt rewards restatement, not judgement."""
        for path in _EVAL_SETS:
            for case in _load(path)["evals"]:
                prompt = case["prompt"].lower()
                for assertion in case.get("assertions", []):
                    for value in assertion["values"]:
                        literal = re.sub(r"\\[sbwd]\*?|\[.*?\]|[\\()?+*|^$]", " ", value)
                        for token in (t for t in literal.lower().split() if len(t) > 5):
                            self.assertNotIn(token, prompt,
                                             f"{path} case {case['id']} {assertion['id']}: "
                                             f"'{token}' is echoed from the prompt")

    def test_every_case_carries_enough_case_specific_assertions(self):
        """Shared assertions re-measure template conformance; only case-specific ones
        tell two cases apart."""
        for path in _EVAL_SETS:
            for case in _load(path)["evals"]:
                self.assertGreaterEqual(
                    len(case.get("assertions", [])), 2,
                    f"{path} case {case['id']} needs >=2 case-specific assertions")


if __name__ == "__main__":
    unittest.main()
