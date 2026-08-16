"""Capture + offline-grading tests. Every dispatch is injected — no live model call.

The contract under test is that capture NEVER manufactures a response: a failed
dispatch must raise, because a silently-empty capture would be graded as a
genuine skill failure and pollute the numbers this directory exists to produce.
"""

import json
import os
import subprocess
import unittest

from _scriptimport import EVAL_CAPTURE, EVAL_ENGINE, EVAL_GRADE, load_module

engine = load_module(EVAL_ENGINE, "eval_engine")
capture = load_module(EVAL_CAPTURE, "eval_capture")
grader = load_module(EVAL_GRADE, "eval_grade")

_REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
_EVAL_SET = os.path.join(_REPO, "skills", "request-plan", "evals", "evals.json")


def _completed(rc=0, stdout="", stderr=""):
    return subprocess.CompletedProcess(["claude"], rc, stdout, stderr)


def _cli_json(text, cost=0.01):
    return json.dumps({"result": text, "usage": {"input_tokens": 10, "output_tokens": 20},
                       "total_cost_usd": cost})


class _Fixture(unittest.TestCase):
    """Supplies its own case: the real set is generated and its ids churn."""

    def setUp(self):
        with open(_EVAL_SET, encoding="utf-8") as f:
            real = json.load(f)
        self.eval_set = {
            "skill_name": "request-plan",
            "shared_assertions": real["shared_assertions"],
            "evals": [{"id": 1, "prompt": "plan a fix for the flaky gate",
                       "assertions": [], "expected_outcome": "plan"}],
        }
        self.case = engine.find_case(self.eval_set, 1)


class PromptAssembly(_Fixture):
    def test_command_mode_invokes_the_skill_explicitly(self):
        sent = capture.build_prompt(self.case, "command", "request-plan")
        self.assertTrue(sent.startswith("/corpflow:request-plan "))
        self.assertIn(self.case["prompt"], sent)

    def test_natural_mode_sends_the_bare_request(self):
        self.assertEqual(capture.build_prompt(self.case, "natural", "request-plan"),
                         self.case["prompt"])

    def test_argv_pins_model_and_json_output(self):
        argv = capture.build_argv("claude-sonnet-5", None)
        self.assertEqual(argv[:2], ["claude", "-p"])
        self.assertIn("--output-format", argv)
        self.assertEqual(argv[argv.index("--output-format") + 1], "json")
        self.assertEqual(argv[argv.index("--model") + 1], "claude-sonnet-5")
        self.assertNotIn("--settings", argv)

    def test_settings_path_is_appended_when_given(self):
        argv = capture.build_argv("claude-sonnet-5", "/tmp/s.json")
        self.assertEqual(argv[argv.index("--settings") + 1], "/tmp/s.json")


class ResponseExtraction(unittest.TestCase):
    def test_extracts_text_and_usage(self):
        text, usage = capture.extract_response(_cli_json("# Plan: x"))
        self.assertEqual(text, "# Plan: x")
        self.assertEqual(usage["output_tokens"], 20)
        self.assertEqual(usage["cost_usd"], 0.01)

    def test_malformed_json_yields_no_text(self):
        self.assertEqual(capture.extract_response("not json")[0], None)

    def test_empty_result_yields_no_text(self):
        self.assertEqual(capture.extract_response(json.dumps({"result": "   "}))[0], None)

    def test_error_object_yields_no_text(self):
        payload = json.dumps({"result": "partial", "is_error": True})
        self.assertEqual(capture.extract_response(payload)[0], None)


class CaptureNeverFabricates(_Fixture):
    def test_successful_dispatch_returns_the_response(self):
        sent, response, usage = capture.capture_case(
            self.eval_set, self.case, mode="command", model="m", settings_path=None,
            timeout=1, cwd=None, dispatcher=lambda a, p: _completed(0, _cli_json("# Plan")))
        self.assertEqual(response, "# Plan")
        self.assertTrue(sent.startswith("/corpflow:request-plan"))
        self.assertEqual(usage["cost_usd"], 0.01)

    def test_nonzero_exit_raises_rather_than_storing_nothing(self):
        with self.assertRaises(RuntimeError) as ctx:
            capture.capture_case(
                self.eval_set, self.case, mode="command", model="m", settings_path=None,
                timeout=1, cwd=None, dispatcher=lambda a, p: _completed(1, "", "boom"))
        self.assertIn("exited 1", str(ctx.exception))

    def test_missing_response_text_raises(self):
        with self.assertRaises(RuntimeError) as ctx:
            capture.capture_case(
                self.eval_set, self.case, mode="command", model="m", settings_path=None,
                timeout=1, cwd=None, dispatcher=lambda a, p: _completed(0, "{}"))
        self.assertIn("no response text", str(ctx.exception))

    def test_timeout_is_a_failure_not_an_empty_answer(self):
        def timing_out(argv, prompt):
            return capture.run(["sleep", "5"], timeout=0.01)
        with self.assertRaises(RuntimeError):
            capture.capture_case(
                self.eval_set, self.case, mode="command", model="m", settings_path=None,
                timeout=1, cwd=None, dispatcher=timing_out)


class Provenance(unittest.TestCase):
    def test_reads_the_skill_version_from_frontmatter(self):
        self.assertEqual(capture.skill_version(_REPO, "request-plan"), "0.1.0")

    def test_absent_skill_is_unknown_not_an_exception(self):
        self.assertIsNone(capture.skill_version(_REPO, "no-such-skill"))


class Credentials(unittest.TestCase):
    def test_env_key_short_circuits_the_cli_probe(self):
        def explode():
            raise AssertionError("CLI probe must not run when the env key is set")
        self.assertTrue(capture.has_credential({"ANTHROPIC_API_KEY": "k"}, explode))

    def test_cli_login_is_accepted(self):
        self.assertTrue(capture.has_credential({}, lambda: json.dumps({"loggedIn": True})))

    def test_logged_out_is_refused(self):
        self.assertFalse(capture.has_credential({}, lambda: json.dumps({"loggedIn": False})))

    def test_unparseable_probe_is_refused(self):
        self.assertFalse(capture.has_credential({}, lambda: "garbage"))

    def test_blank_env_key_falls_through_to_the_probe(self):
        self.assertFalse(capture.has_credential({"ANTHROPIC_API_KEY": "  "}, lambda: "{}"))


class Digests(_Fixture):
    def test_prompt_digest_is_stable_across_key_order(self):
        reordered = {"evals": [dict(reversed(list(self.case.items())))]}
        self.assertEqual(engine.prompt_digest(self.eval_set, 1),
                         engine.prompt_digest(reordered, 1))

    def test_editing_the_prompt_moves_only_the_prompt_digest(self):
        before_p = engine.prompt_digest(self.eval_set, 1)
        before_a = engine.assertions_digest(self.eval_set, 1)
        engine.find_case(self.eval_set, 1)["prompt"] += " and be quick"
        self.assertNotEqual(before_p, engine.prompt_digest(self.eval_set, 1))
        self.assertEqual(before_a, engine.assertions_digest(self.eval_set, 1))

    def test_editing_an_assertion_moves_only_the_assertions_digest(self):
        before_p = engine.prompt_digest(self.eval_set, 1)
        before_a = engine.assertions_digest(self.eval_set, 1)
        self.eval_set["shared_assertions"][0]["values"].append("## Handoff")
        self.assertEqual(before_p, engine.prompt_digest(self.eval_set, 1))
        self.assertNotEqual(before_a, engine.assertions_digest(self.eval_set, 1))


class OfflineGrading(_Fixture):
    def _record(self, response, **overrides):
        rec = {"case_id": 1, "response": response,
               "prompt_digest": engine.prompt_digest(self.eval_set, 1),
               "assertions_digest": engine.assertions_digest(self.eval_set, 1),
               "model": "claude-sonnet-5", "captured_at": "2026-08-16T00:00:00Z"}
        rec.update(overrides)
        return rec

    def _conforming_plan(self):
        """Carries case 1's own token too, so this fixture satisfies every assertion it is graded by."""
        return ("# Plan\n## Context\nhooks/test-execution-gate.sh\n## Goal\ng\n"
                "## Scope\n**In:** a\n**Out:** b\n"
                "## Phases\n| P0 — Required | x |\n| P1 — Nice-to-have | x |\n"
                "| P2 — v1.1 | x |\n## Effort (rough)\n| M | 12 |\n"
                "## Risks\n- allow a rerun once the tree hash changes\n"
                "/worktask \"fix the test-execution-gate dedupe branch\"\n")

    def test_a_conforming_response_passes(self):
        result = grader.grade_record(self.eval_set, self._record(self._conforming_plan()))
        self.assertEqual(result["status"], "pass", result)

    def test_a_deficient_response_fails_with_named_assertions(self):
        result = grader.grade_record(self.eval_set, self._record("just some prose about wake"))
        self.assertEqual(result["status"], "fail")
        self.assertIn("template-sections-present", result["failed"])

    def test_a_response_to_a_superseded_prompt_is_refused_not_scored(self):
        record = self._record(self._conforming_plan(), prompt_digest="0000000000000000")
        result = grader.grade_record(self.eval_set, record)
        self.assertEqual(result["status"], "stale")
        self.assertNotIn("failed", result)

    def test_a_clarifying_question_is_not_scored_as_a_broken_plan(self):
        asked = ("The current working directory has no macOS app to ground a plan against. "
                 "Do you mean a different project directory?")
        result = grader.grade_record(self.eval_set, self._record(asked))
        self.assertEqual(result["status"], "clarify")

    def test_a_plan_that_merely_lacks_sections_still_fails(self):
        """Absent sections plus no question is a bad plan, not a clarification."""
        result = grader.grade_record(self.eval_set, self._record("here is roughly what I would do."))
        self.assertEqual(result["status"], "fail")

    def test_bold_section_labels_still_count_as_a_plan(self):
        """A real dev capture used `**Context**` throughout; reading that as a
        refusal drops a complete plan out of the denominator entirely."""
        bold = ("## Plan: x\n**Context**\nc\n**Goal**\ng\n**Scope**\ns\n"
                "**Phases**\np\n**Effort (rough)**\ne\n**Risks**\nr\nWhy this order?\n")
        self.assertEqual(engine.classify_outcome(bold), "plan")

    def test_two_incidental_section_words_are_not_a_plan(self):
        asked = "What's the goal here, and what scope did you have in mind?"
        self.assertEqual(engine.classify_outcome(asked), "clarify")

    def test_a_plan_asking_a_rhetorical_question_is_still_a_plan(self):
        plan = self._conforming_plan() + "\nWhy this order? Risk first.\n"
        self.assertEqual(grader.grade_record(self.eval_set, self._record(plan))["outcome"], "plan")

    def test_moved_assertions_are_flagged_but_still_graded(self):
        record = self._record(self._conforming_plan(), assertions_digest="0000000000000000")
        result = grader.grade_record(self.eval_set, record)
        self.assertEqual(result["status"], "pass")
        self.assertTrue(result["assertions_moved"])


class GradeCli(unittest.TestCase):
    def test_missing_responses_dir_declines_rather_than_reporting_zero(self):
        rc = grader.main(["--eval-set", _EVAL_SET, "--responses", "/nonexistent/xyz"])
        self.assertEqual(rc, 2)


class CaptureCli(unittest.TestCase):
    def test_dry_run_spends_nothing_and_prints_the_plan(self):
        rc = capture.main(["--eval-set", _EVAL_SET, "--dry-run"])
        self.assertEqual(rc, 0)

    def test_unknown_case_id_is_a_usage_error(self):
        rc = capture.main(["--eval-set", _EVAL_SET, "--case", "99", "--dry-run"])
        self.assertEqual(rc, 64)

    def test_unreadable_eval_set_is_a_usage_error(self):
        self.assertEqual(capture.main(["--eval-set", "/nonexistent/evals.json"]), 64)


if __name__ == "__main__":
    unittest.main()
