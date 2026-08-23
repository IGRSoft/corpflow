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
    """Exercises the SHARED assertions. Cases are generated and churn, so the
    fixture supplies its own case rather than pinning to an id in the real set."""

    def setUp(self):
        self.eval_set = {
            "skill_name": "request-plan",
            "shared_assertions": _load(_EVAL_SETS[0])["shared_assertions"],
            "evals": [
                {"id": 1, "prompt": "fixture", "assertions": [], "expected_outcome": "plan"},
                {"id": 3, "prompt": "fixture", "expected_outcome": "plan",
                 "assertions": [{"id": "routes-to-secure-tier", "why": "fixture",
                                 "type": "regex_all", "values": [r"/worktask\s+--secure"]}]},
            ],
        }

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

    def test_effort_assertion_accepts_the_five_factor_breakdown(self):
        """estimation-methodology asks for the factor split; a dev capture supplied
        it inside the cell and was failed for the extra detail."""
        cell = "| S–M | 11 (Technical 3, Integration 1, Risk 3, Uncertainty 2, Scope 2) | n |\n"
        plan = self._plan(effort="## Effort (rough)\n" + cell)
        self.assertNotIn("effort-sized-with-complexity",
                         grade(self.eval_set, 1, plan + _CASE1_TOKEN)["failed"])

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
                if a["type"] == "paths_resolve":
                    self.assertTrue(a["values"] and isinstance(a["values"][0], int),
                                    f"{a['id']} must carry an integer path count")

    def test_assertion_ids_are_unique_within_a_case(self):
        for path in _EVAL_SETS:
            eval_set = _load(path)
            shared = [a["id"] for a in eval_set.get("shared_assertions", [])]
            for case in eval_set["evals"]:
                # A refute case is scored on its own assertions alone, so it may reuse a
                # shared id (the worktask line is still owed when disputing a premise).
                inherited = [] if case.get("expected_outcome") == "refute" else shared
                ids = inherited + [a["id"] for a in case.get("assertions", [])]
                self.assertEqual(len(ids), len(set(ids)), f"{path} case {case['id']}")

    def test_every_case_is_grounded_in_paths_that_exist(self):
        """A case describing a surface this repo lacks can only ever be refused —
        the first live run burned $1.47 on two such cases. Cases that EXPECT a
        refusal are the deliberate exception and may declare no grounding."""
        for path in _EVAL_SETS:
            for case in _load(path)["evals"]:
                grounding = case.get("grounding", [])
                if case.get("expected_outcome") != "clarify":
                    self.assertTrue(grounding,
                                    f"{path} case {case['id']} declares no grounding")
                for rel in grounding:
                    self.assertTrue(os.path.exists(os.path.join(_REPO, rel)),
                                    f"{path} case {case['id']} grounds on missing {rel}")

    def test_no_case_prompt_leaks_into_the_searched_tree(self):
        """A prompt printed anywhere the model can read turns its case into a lookup.

        v0.5.0 lost two capability cases this way: SKILL.md carried case 73's prompt beside
        its answer as a worked example, and a findings doc quoted case 75's. Both scored as
        the mechanism working. v0.4.0 case 94 found its own prompt in the generator.
        The eval set and the generator are exempt — a case has to live somewhere.

        Untracked files count. `eval-capture.py` runs the model against the WORKING TREE,
        so a findings doc that is written but not yet committed is just as readable as one
        that is — and that is exactly how a capability-registry proposal kept a table of
        case ids beside their answers through a whole capture without tripping this.

        What this cannot catch: paraphrase. Substring matching over the prompt's own words
        is blind to a leak that restates the case in different words beside its answer.
        That is inherent to the technique, not a gap to close by widening the window — an
        n-gram lint that fires on paraphrase fires on ordinary prose too. Treat a green run
        as "no verbatim copy", never as "this case is uncontaminated".
        """
        import subprocess
        exempt = {"skills/request-plan/evals/evals.json",
                  "evals/scripts/gen-request-plan-cases.py"}
        # --others --exclude-standard adds untracked-but-not-ignored files; --cached keeps
        # the tracked ones. -z because a leak is likeliest in a path with a space in it.
        listed = subprocess.run(
            ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
            cwd=_REPO, capture_output=True, text=True).stdout.split("\0")
        blobs = {}
        for rel in listed:
            if not rel or rel in exempt or "/responses/" in rel or "/labels/" in rel:
                continue
            if not rel.endswith((".md", ".py", ".sh", ".json", ".jsonl",
                                 ".txt", ".yml", ".yaml", ".bats")):
                continue
            try:
                with open(os.path.join(_REPO, rel), encoding="utf-8", errors="ignore") as f:
                    blobs[rel] = f.read().lower()
            except OSError:
                continue
        leaks = []
        for path in _EVAL_SETS:
            for case in _load(path)["evals"]:
                words = re.findall(r"[a-z']+", case["prompt"].lower())
                # Every 6-word window, so a quote that drops the leading "i want to" still trips.
                for i in range(0, max(1, len(words) - 5)):
                    frag = " ".join(words[i:i + 6])
                    if len(frag) < 25:
                        continue
                    # Every hit, not the first: stopping at one reported a single file to
                    # scrub and left the same prompt sitting in three others.
                    for rel, blob in blobs.items():
                        if frag in blob:
                            leaks.append(f"case {case['id']} -> {rel}: '{frag}'")
        self.assertEqual(leaks, [], "eval prompts readable by the model under test:\n  "
                         + "\n  ".join(leaks))

    def test_expected_outcome_is_a_known_value(self):
        for path in _EVAL_SETS:
            for case in _load(path)["evals"]:
                self.assertIn(case.get("expected_outcome", "plan"),
                              ("plan", "clarify", "refute"), f"{path} case {case['id']}")

    def test_no_assertion_can_be_satisfied_by_echoing_the_prompt(self):
        """A value already in the case's own prompt rewards restatement, not judgement."""
        for path in _EVAL_SETS:
            for case in _load(path)["evals"]:
                prompt = case["prompt"].lower()
                for assertion in case.get("assertions", []):
                    for value in assertion["values"]:
                        if not isinstance(value, str):
                            continue
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
                if case.get("expected_outcome") == "clarify":
                    continue  # scored on the outcome alone; assertions describe an unwanted plan
                self.assertGreaterEqual(
                    len(case.get("assertions", [])), 2,
                    f"{path} case {case['id']} needs >=2 case-specific assertions")


if __name__ == "__main__":
    unittest.main()
