"""Capture + offline-grading tests. Every dispatch is injected — no live model call.

The contract under test is that capture NEVER manufactures a response: a failed
dispatch must raise, because a silently-empty capture would be graded as a
genuine skill failure and pollute the numbers this directory exists to produce.
"""

import contextlib
import glob
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

from _scriptimport import (EVAL_CAPTURE, EVAL_ENGINE, EVAL_GRADE, LABEL_ALIGN,
                           SAMPLE_LABELS, SCAN_CONTAM, load_module)

engine = load_module(EVAL_ENGINE, "eval_engine")
capture = load_module(EVAL_CAPTURE, "eval_capture")
grader = load_module(EVAL_GRADE, "eval_grade")
label_align = load_module(LABEL_ALIGN, "label_align")
sampler = load_module(SAMPLE_LABELS, "sample_for_labelling")
scanner = load_module(SCAN_CONTAM, "scan_contamination")

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

    def test_argv_pins_model_and_stream_json_output(self):
        """stream-json, not json: the plain envelope drops every assistant message but
        the last, which is how a written plan reached disk as its own follow-up."""
        argv = capture.build_argv("claude-sonnet-5", None)
        self.assertEqual(argv[:2], ["claude", "-p"])
        self.assertIn("--output-format", argv)
        self.assertEqual(argv[argv.index("--output-format") + 1], "stream-json")
        self.assertIn("--verbose", argv)  # stream-json under -p requires it
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


def _stream(*texts, cost=0.01, subtype="success", is_error=False, terminal=True):
    """NDJSON in the shape `--output-format stream-json --verbose` emits."""
    rows = [{"type": "system", "subtype": "init"}]
    for t in texts:
        rows.append({"type": "assistant",
                     "message": {"content": [{"type": "text", "text": t}]}})
    if terminal:
        rows.append({"type": "result", "subtype": subtype, "is_error": is_error,
                     "result": texts[-1] if texts else "",
                     "usage": {"input_tokens": 10, "output_tokens": 20},
                     "total_cost_usd": cost})
    return "\n".join(json.dumps(r) for r in rows) + "\n"


class StreamExtraction(unittest.TestCase):
    """The case-187 defect: an answer followed by a second message was discarded.

    `--output-format json` puts only the final assistant message in `result`, so a turn
    that wrote a plan and then asked whether to save it stored the question alone. It
    graded as a failure to plan, and only a human label caught it.
    """

    def test_every_assistant_block_is_kept_not_just_the_last(self):
        text, usage = capture.extract_response(_stream("# Plan: x", "Shall I save it?"))
        self.assertEqual(text, "# Plan: x\n\nShall I save it?")
        self.assertEqual(usage["output_tokens"], 20)
        self.assertEqual(usage["cost_usd"], 0.01)

    def test_single_message_is_unchanged(self):
        self.assertEqual(capture.extract_response(_stream("# Plan: x"))[0], "# Plan: x")

    def test_tool_blocks_and_user_rows_are_ignored(self):
        rows = [{"type": "assistant",
                 "message": {"content": [{"type": "text", "text": "A"},
                                         {"type": "tool_use", "name": "Bash", "input": {}}]}},
                {"type": "user", "message": {"content": [{"type": "tool_result"}]}},
                {"type": "assistant", "message": {"content": [{"type": "text", "text": "B"}]}},
                {"type": "result", "subtype": "success", "usage": {}, "total_cost_usd": 0.02}]
        text, _ = capture.extract_response("\n".join(json.dumps(r) for r in rows))
        self.assertEqual(text, "A\n\nB")

    def test_blank_blocks_do_not_become_separators(self):
        self.assertEqual(capture.extract_response(_stream("A", "   ", "B"))[0], "A\n\nB")

    def test_error_terminal_yields_no_text(self):
        self.assertIsNone(capture.extract_response(_stream("partial", is_error=True))[0])

    def test_nonsuccess_subtype_yields_no_text(self):
        self.assertIsNone(
            capture.extract_response(_stream("partial", subtype="error_max_turns"))[0])

    def test_missing_terminal_event_yields_no_text(self):
        """A truncated stream is an incomplete dispatch, not a short answer."""
        self.assertIsNone(capture.extract_response(_stream("# Plan", terminal=False))[0])

    def test_no_assistant_text_yields_no_text(self):
        self.assertIsNone(capture.extract_response(_stream())[0])

    def test_unparseable_line_does_not_lose_the_answer(self):
        self.assertEqual(capture.extract_response("garbage\n" + _stream("# Plan"))[0], "# Plan")

    def test_legacy_single_envelope_still_parses(self):
        """Stored dispatches predate the switch; they must still read back."""
        self.assertEqual(capture.extract_response(_cli_json("# Plan"))[0], "# Plan")


class CaptureNeverFabricates(_Fixture):
    """Single-shot by design: `retries=0` throughout, because what these assert is
    that ONE bad dispatch is never turned into a stored answer. Retry behaviour is
    a separate contract, in TransientFailuresAreRetried."""

    def test_successful_dispatch_returns_the_response(self):
        sent, response, usage = capture.capture_case(
            self.eval_set, self.case, mode="command", model="m", settings_path=None,
            timeout=1, cwd=None, retries=0,
            dispatcher=lambda a, p: _completed(0, _cli_json("# Plan")))
        self.assertEqual(response, "# Plan")
        self.assertTrue(sent.startswith("/corpflow:request-plan"))
        self.assertEqual(usage["cost_usd"], 0.01)

    def test_nonzero_exit_raises_rather_than_storing_nothing(self):
        with self.assertRaises(RuntimeError) as ctx:
            capture.capture_case(
                self.eval_set, self.case, mode="command", model="m", settings_path=None,
                timeout=1, cwd=None, retries=0,
                dispatcher=lambda a, p: _completed(1, "", "boom"))
        self.assertIn("exited 1", str(ctx.exception))

    def test_missing_response_text_raises(self):
        with self.assertRaises(RuntimeError) as ctx:
            capture.capture_case(
                self.eval_set, self.case, mode="command", model="m", settings_path=None,
                timeout=1, cwd=None, retries=0,
                dispatcher=lambda a, p: _completed(0, "{}"))
        self.assertIn("no response text", str(ctx.exception))

    def test_timeout_is_a_failure_not_an_empty_answer(self):
        def timing_out(argv, prompt):
            return capture.run(["sleep", "5"], timeout=0.01)
        with self.assertRaises(RuntimeError):
            capture.capture_case(
                self.eval_set, self.case, mode="command", model="m", settings_path=None,
                timeout=1, cwd=None, retries=0, dispatcher=timing_out)


class Provenance(unittest.TestCase):
    def test_reads_the_skill_version_from_frontmatter(self):
        """Shape, not value: pinning the literal breaks on every legitimate bump."""
        import re
        self.assertRegex(capture.skill_version(_REPO, "request-plan") or "", r"^\d+\.\d+\.\d+$")

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

    _ASKED = ("The current working directory has no macOS app to ground a plan against. "
              "Do you mean a different project directory?")

    def test_asking_when_the_case_wanted_a_plan_is_a_failure(self):
        """Excusing this hid 9 of 32 human-labelled failures from the denominator —
        the skill answered the wrong question, which is a wrong answer, not an
        abstention. `expected_outcome` is what separates the two, and every case
        declares it."""
        result = grader.grade_record(self.eval_set, self._record(self._ASKED))
        self.assertEqual(result["status"], "fail")
        self.assertTrue(result["asked_instead"])
        self.assertIn("asked-instead-of-planning", result["failed"])

    def test_asking_when_the_case_wanted_a_question_passes(self):
        engine.find_case(self.eval_set, 1)["expected_outcome"] = "clarify"
        result = grader.grade_record(self.eval_set, self._record(self._ASKED))
        self.assertEqual(result["status"], "pass")
        self.assertFalse(result["asked_instead"])

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

    def _dry_run_argv(self, *extra):
        """The argv the dry run advertises, for the single case in a throwaway set."""
        with tempfile.TemporaryDirectory() as tmp:
            es = os.path.join(tmp, "evals.json")
            with open(es, "w", encoding="utf-8") as f:
                json.dump({"skill_name": "request-plan", "shared_assertions": [],
                           "evals": [{"id": 1, "prompt": "plan a fix", "assertions": [],
                                      "expected_outcome": "plan"}]}, f)
            settings = os.path.join(tmp, "settings.json")
            with open(settings, "w", encoding="utf-8") as f:
                json.dump({"permissions": {"defaultMode": "bypassPermissions"}}, f)
            held, sys.stdout = sys.stdout, io.StringIO()
            try:
                rc = capture.main(["--eval-set", es, "--dry-run",
                                   "--settings", settings, *extra])
                out = sys.stdout.getvalue()
            finally:
                sys.stdout = held
            self.assertEqual(rc, 0)
            plan = json.loads(out[out.rindex("{\n  \"case_id\""):])
            return plan["argv"], settings

    def test_an_uisolated_dry_run_prints_the_settings_it_would_dispatch_with(self):
        # The printed argv is the only description of a run nobody watches happen. An
        # argv missing --settings describes a dispatch against the ambient plugin,
        # which is a different measurement than the one that would actually be taken.
        argv, settings = self._dry_run_argv("--no-isolate")
        self.assertIn("--settings", argv)
        self.assertEqual(argv[argv.index("--settings") + 1], settings)

    def test_an_isolated_dry_run_advertises_the_generated_settings_instead(self):
        argv, given = self._dry_run_argv()
        self.assertIn("--settings", argv)
        self.assertNotEqual(argv[argv.index("--settings") + 1], given)

    def test_a_settings_path_that_does_not_exist_is_refused_before_any_work(self):
        self.assertEqual(
            capture.main(["--eval-set", _EVAL_SET, "--dry-run", "--no-isolate",
                          "--settings", "/nonexistent/settings.json"]), 2)

    def test_unknown_case_id_is_a_usage_error(self):
        # Out of range on purpose. A plausible-looking id silently stops testing
        # anything the day the eval set grows past it.
        rc = capture.main(["--eval-set", _EVAL_SET, "--case", "999999", "--dry-run"])
        self.assertEqual(rc, 64)

    def test_unreadable_eval_set_is_a_usage_error(self):
        self.assertEqual(capture.main(["--eval-set", "/nonexistent/evals.json"]), 64)



class PathsResolve(unittest.TestCase):
    """Grounding without naming a target: the author's guess at WHICH file failed
    three plans that reached a better one."""

    def _a(self, n=2):
        return {"id": "finds-the-real-surface", "why": "fixture",
                "type": "paths_resolve", "values": [n]}

    def test_counts_only_paths_the_resolver_accepts(self):
        text = "touch hooks/state-merge.sh and skills/worktask/SKILL.md"
        self.assertTrue(engine.check(self._a(2), text, lambda p: True))
        self.assertFalse(engine.check(self._a(2), text, lambda p: False))

    def test_an_invented_path_does_not_count(self):
        real = {"hooks/state-merge.sh"}
        text = "edit hooks/state-merge.sh and src/totally/made-up.py"
        self.assertTrue(engine.check(self._a(1), text, lambda p: p in real))
        self.assertFalse(engine.check(self._a(2), text, lambda p: p in real))

    def test_a_bare_filename_is_not_a_cited_path(self):
        self.assertEqual(engine.cited_paths("state-merge.sh is broken"), [])
        self.assertIn("hooks/state-merge.sh", engine.cited_paths("see hooks/state-merge.sh"))

    def test_missing_resolver_raises_rather_than_passing(self):
        with self.assertRaises(ValueError):
            engine.check(self._a(), "hooks/state-merge.sh", None)


class TransientFailuresAreRetried(unittest.TestCase):
    """A sustained sweep provokes transient refusals. A run at concurrency 4 lost 38
    consecutive cases to `exited 1` with an empty stderr, and the first of them
    succeeded on a bare retry minutes later — so without retry the capture is a coin
    toss against the rate limiter that costs the whole tail."""

    def setUp(self):
        self.eval_set = {
            "skill_name": "request-plan", "shared_assertions": [],
            "evals": [{"id": 1, "prompt": "p", "assertions": [],
                       "expected_outcome": "plan"}],
        }
        self.case = engine.find_case(self.eval_set, 1)
        self.slept = []

    def _capture(self, outcomes, retries=2):
        seq = list(outcomes)

        def dispatch(argv, prompt):
            return seq.pop(0)
        return capture.capture_case(
            self.eval_set, self.case, mode="command", model="m", settings_path=None,
            timeout=1, cwd=None, dispatcher=dispatch, retries=retries,
            sleeper=self.slept.append)

    def test_a_transient_failure_is_retried_and_the_answer_kept(self):
        _, response, _ = self._capture(
            [_completed(1, "", ""), _completed(0, _cli_json("real answer"))])
        self.assertEqual(response, "real answer")

    def test_retries_back_off_rather_than_hammering_the_limiter(self):
        self._capture([_completed(1), _completed(1), _completed(0, _cli_json("ok"))])
        self.assertEqual(len(self.slept), 2)
        self.assertLess(self.slept[0], self.slept[1])

    def test_exhausting_the_retries_still_raises_and_stores_nothing(self):
        # Retrying must not weaken the never-fabricate contract: a blank capture
        # would be graded as a genuine skill failure.
        with self.assertRaises(RuntimeError) as cm:
            self._capture([_completed(1, "", "boom")] * 3)
        self.assertIn("3 attempts", str(cm.exception))

    def test_an_empty_response_is_transient_too_not_an_answer(self):
        _, response, _ = self._capture(
            [_completed(0, _cli_json("")), _completed(0, _cli_json("second try"))])
        self.assertEqual(response, "second try")

    def test_retries_zero_restores_the_single_shot_behaviour(self):
        with self.assertRaises(RuntimeError):
            self._capture([_completed(1)], retries=0)
        self.assertEqual(self.slept, [])


class CaptureIsolation(unittest.TestCase):
    """The capture surface, which two separate defects made load-bearing.

    Neither defect is visible in a stored record. The plugin one is worse: without
    `--plugin-dir` the CLI answers from the ambient marketplace install while
    `skill_version()` reads this repo, so a whole sweep can measure one version and
    stamp another on all of it — a green-looking capture of the wrong thing.
    """

    def setUp(self):
        self.parent = tempfile.mkdtemp(prefix="capture-isolation-")
        self.tree = None
        self.addCleanup(shutil.rmtree, self.parent, True)

    def _tree(self):
        self.tree = capture.make_capture_tree(_REPO, os.path.join(self.parent, "tree"))
        self.addCleanup(capture.remove_capture_tree, _REPO, self.tree)
        return self.tree

    def test_the_answer_key_is_removed_from_the_capture_tree(self):
        tree = self._tree()
        capture.strip_answer_keys(tree)
        for rel in ("skills/request-plan/evals/evals.json", "evals/labels",
                    "evals/findings", "evals/splits",
                    "evals/scripts/gen-request-plan-cases.py"):
            self.assertFalse(os.path.exists(os.path.join(tree, rel)), rel)

    def test_gitignored_material_never_reaches_the_capture_tree(self):
        # `.context/` held a per-trace map of every known failure. It is gitignored,
        # so the prompt-leak lint's `git ls-files --others` sweep cannot see it — the
        # worktree excludes it by construction rather than by another deny-list.
        self.assertFalse(os.path.exists(os.path.join(self._tree(), ".context")))

    def test_the_scripts_cases_ground_on_survive_the_strip(self):
        # Cases 111/112/115/162/163/164 ground on these. Stripping the whole of
        # evals/ would make them unanswerable and score the strip as a skill failure.
        tree = self._tree()
        capture.strip_answer_keys(tree)
        for rel in ("eval-engine.py", "eval-capture.py", "eval-grade.py",
                    "judge-traces.py", "build-review-page.py", "label-align.py"):
            self.assertTrue(os.path.exists(os.path.join(tree, "evals", "scripts", rel)), rel)

    def test_settings_disable_the_ambient_copy_of_the_plugin(self):
        path = capture.write_capture_settings(_REPO, self.parent, None)
        if path is None:
            self.skipTest("no ambient corpflow install to disable")
        with open(path, encoding="utf-8") as f:
            enabled = json.load(f)["enabledPlugins"]
        self.assertTrue(enabled)
        self.assertTrue(all(v is False for v in enabled.values()))
        self.assertTrue(all(k.split("@", 1)[0] == "corpflow" for k in enabled))

    def test_plugin_dir_is_passed_only_when_isolating(self):
        self.assertIn("--plugin-dir", capture.build_argv("m", None, "/tmp/tree"))
        self.assertNotIn("--plugin-dir", capture.build_argv("m", None, None))

    def test_a_dirty_tree_is_refused_before_any_spend(self):
        with self.assertRaises(capture.PreflightError):
            capture.assert_clean_tree(self.parent)   # not a git repo at all

    def test_the_probe_reads_an_enumeration_and_fails_closed_otherwise(self):
        got = capture.parse_probe(
            "corpflow:worktask\n- /corpflow:estimate\ncorpflow:roadmap\nevals: 0",
            "corpflow")
        self.assertEqual(got["names"], {"worktask", "estimate", "roadmap"})
        self.assertEqual(got["evals"], 0)
        blank = capture.parse_probe("I could not determine that.", "corpflow")
        self.assertEqual(blank, {"names": set(), "evals": None})

    def test_the_probe_asks_what_LOADED_not_what_is_on_disk(self):
        # The version question does not work and looked like it did: the model
        # answers it by reading SKILL.md out of the working directory, so it reported
        # the tree's version on the un-isolated surface too — while the ambient
        # release was demonstrably the plugin answering.
        prompt = capture.build_probe_prompt("corpflow")
        self.assertNotIn("SKILL.md", prompt)
        self.assertIn("not what is on the filesystem", prompt)

    def test_deleted_commands_are_what_catch_a_pin_that_did_not_bind(self):
        tree = self._tree()
        must_offer, must_not_offer = capture.probe_expectations(_REPO, tree)
        self.assertTrue(must_offer)
        self.assertFalse(must_offer & must_not_offer)
        for name in must_not_offer:
            self.assertFalse(os.path.exists(os.path.join(tree, "commands", name + ".md")))

    def test_a_name_that_became_a_skill_is_not_read_as_a_stale_command(self):
        # Commands and skills are both invocable as `<plugin>:<name>` and the model
        # lists them together, so a command promoted to a skill would otherwise look
        # like a deleted command still being served, and refuse a sound capture.
        tree = self._tree()
        _, must_not_offer = capture.probe_expectations(_REPO, tree)
        skills = {os.path.basename(os.path.dirname(f))
                  for f in glob.glob(os.path.join(tree, "skills", "*", "SKILL.md"))}
        self.assertFalse(must_not_offer & skills)


class LabelAlignFraming(unittest.TestCase):
    """The weights must describe the draw that was cut, not a frame reconstructed
    from (split, verdict) afterwards. Both defects below shipped once and neither
    was visible in any number the tool printed."""

    HELD_OUT_FROM = 122

    def _stratum(self, cid, split, verdict, floor=HELD_OUT_FROM):
        return label_align.stratum_of(cid, split, verdict, floor)

    def test_the_frame_is_dev_by_verdict_plus_the_tranche_taken_whole(self):
        self.assertEqual(self._stratum(130, "test", "pass"), "test/held-out")
        self.assertEqual(self._stratum(10, "dev", "fail"), "dev/fail")
        self.assertEqual(self._stratum(10, "dev", "pass"), "dev/pass")

    def test_test_split_below_the_floor_is_outside_the_frame(self):
        # sample-for-labelling.py never draws it: the split manifest calls its own
        # `test` membership nominal below the floor. Putting it in a `test` stratum
        # is what let 18 tranche cases carry the population of 82.
        self.assertTrue(self._stratum(99, "test", "pass").startswith("unframed/"))
        self.assertTrue(self._stratum(50, "train", "pass").startswith("unframed/"))

    def test_no_floor_means_no_tranche_rather_than_a_guessed_one(self):
        self.assertTrue(
            label_align.stratum_of(130, "test", "pass", None).startswith("unframed/"))

    def _labels(self, tmp, rows):
        path = os.path.join(tmp, "labels.jsonl")
        with open(path, "w", encoding="utf-8") as f:
            for r in rows:
                f.write(json.dumps(r) + "\n")
        return path

    def _grades(self, tmp, rows):
        path = os.path.join(tmp, "grades.json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump({"results": rows}, f)
        return path

    def _run(self, argv):
        buf, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(err):
            rc = label_align.main(argv)
        return rc, buf.getvalue(), err.getvalue()

    def test_min_id_narrows_the_population_and_p_obs_not_only_the_labels(self):
        # The defect: `ids` honoured --min-id while `population` and `p_obs` were
        # built from every grade, so "held-out only" returned corpus weights and the
        # corpus pass rate corrected by subset-derived rates.
        with tempfile.TemporaryDirectory() as tmp:
            grades = self._grades(tmp, [
                {"case_id": 1, "status": "pass", "split": "dev"},
                {"case_id": 2, "status": "fail", "split": "dev"},
                {"case_id": 3, "status": "fail", "split": "dev"},
                {"case_id": 130, "status": "pass", "split": "test"},
                {"case_id": 131, "status": "fail", "split": "test"},
            ])
            labels = self._labels(tmp, [
                {"case_id": 130, "verdict": "pass", "split": "test"},
                {"case_id": 131, "verdict": "pass", "split": "test"},
            ])
            rc, out, _ = self._run(["--labels", labels, "--grades", grades,
                                    "--held-out-from", "122", "--min-id", "130"])
            self.assertEqual(rc, 0)
            # Both selected cases are the whole selected population: weight 1.
            self.assertIn("weight 1.00", out)
            self.assertNotIn("weight 2.00", out)
            # p_obs is 1 of 2 selected, not 2 of 5 across the corpus.
            self.assertIn("observed pass rate 50%", out)

    def test_a_stratum_selector_is_exact_where_an_id_floor_is_not(self):
        # Batch 5 seeded the tranche AND dev cases, so --min-id over its id range
        # sweeps in dev labels the draw counted in a different stratum.
        with tempfile.TemporaryDirectory() as tmp:
            grades = self._grades(tmp, [
                {"case_id": 130, "status": "pass", "split": "test"},
                {"case_id": 131, "status": "pass", "split": "dev"},
            ])
            labels = self._labels(tmp, [
                {"case_id": 130, "verdict": "pass", "split": "test"},
                {"case_id": 131, "verdict": "pass", "split": "dev"},
            ])
            _, both, _ = self._run(["--labels", labels, "--grades", grades,
                                    "--held-out-from", "122", "--min-id", "130"])
            self.assertIn("dev/pass", both)
            _, only, _ = self._run(["--labels", labels, "--grades", grades,
                                    "--held-out-from", "122",
                                    "--stratum", "test/held-out"])
            self.assertNotIn("dev/pass", only)
            self.assertIn("test/held-out", only)

    def test_the_draw_supplies_the_populations_and_a_mismatch_is_refused(self):
        # A draw and a label set that disagree about which stratum a case sits in
        # means the grade set moved underneath the labels. Weighting anyway would
        # divide out a sampling fraction that was never taken.
        with tempfile.TemporaryDirectory() as tmp:
            sample = os.path.join(tmp, "sample.json")
            with open(sample, "w", encoding="utf-8") as f:
                json.dump({"held_out_from": 122,
                           "strata": {"dev/pass": {"population": 40, "sampled": 2},
                                      "dev/fail": {"population": 10, "sampled": 1}}}, f)
            labels = self._labels(tmp, [
                {"case_id": 1, "verdict": "pass", "split": "dev",
                 "harness_status": "pass"},
                {"case_id": 2, "verdict": "pass", "split": "dev",
                 "harness_status": "pass"},
                {"case_id": 3, "verdict": "fail", "split": "dev",
                 "harness_status": "fail"},
            ])
            rc, out, err = self._run(["--labels", labels, "--sample", sample,
                                      "--grades", os.path.join(tmp, "absent.json")])
            self.assertEqual(rc, 0)
            self.assertIn("weight 20.00", out)   # 40 / 2
            self.assertEqual(err.count("do not sit in the strata"), 0)

            drifted = self._labels(tmp, [
                {"case_id": 1, "verdict": "pass", "split": "dev",
                 "harness_status": "fail"},
                {"case_id": 2, "verdict": "pass", "split": "dev",
                 "harness_status": "fail"},
                {"case_id": 3, "verdict": "fail", "split": "dev",
                 "harness_status": "fail"},
            ])
            rc, _, err = self._run(["--labels", drifted, "--sample", sample,
                                    "--grades", os.path.join(tmp, "absent.json")])
            self.assertEqual(rc, 65)
            self.assertIn("do not sit in the strata", err)

    def test_a_defer_is_counted_as_drawn_but_never_as_sampled(self):
        # It shrinks the denominator — which is correct, an undecided case must not
        # vote — but the draw still handed it over, so the drift check has to see it
        # or one defer reads as the draw and the labels disagreeing.
        with tempfile.TemporaryDirectory() as tmp:
            sample = os.path.join(tmp, "sample.json")
            with open(sample, "w", encoding="utf-8") as f:
                json.dump({"held_out_from": 122,
                           "strata": {"test/held-out": {"population": 3,
                                                        "sampled": 3}}}, f)
            labels = self._labels(tmp, [
                {"case_id": 130, "verdict": "pass", "split": "test",
                 "harness_status": "pass"},
                {"case_id": 131, "verdict": "fail", "split": "test",
                 "harness_status": "fail"},
                {"case_id": 132, "verdict": "defer", "split": "test",
                 "harness_status": "fail"},
            ])
            rc, out, err = self._run(["--labels", labels, "--sample", sample,
                                      "--grades", os.path.join(tmp, "absent.json")])
            self.assertEqual(rc, 0)
            self.assertNotIn("do not sit in the strata", err)
            self.assertIn("(1 deferred)", out)
            self.assertIn("sampled   2 of   3", out)


class LabelAlignWeighting(unittest.TestCase):
    """Rates must describe the corpus, not the sample that was affordable."""

    def _rows(self, spec):
        return [{"human": h, "grader": g, "weight": w, "stratum": s}
                for h, g, w, s in spec]

    def test_weighting_recovers_the_population_rate_from_an_enriched_sample(self):
        # 1 sampled false-pass standing for 4 (weight 4) must count as 4, or
        # over-sampling the harness-fail stratum silently inflates TNR.
        rows = self._rows([("pass", "pass", 1.0, "a"), ("fail", "fail", 1.0, "a"),
                           ("fail", "pass", 4.0, "b")])
        tpr, tnr, m = label_align.weighted_rates(rows)
        self.assertEqual(m["fp"], 4.0)
        self.assertAlmostEqual(tnr, 1 / 5)
        self.assertAlmostEqual(tpr, 1.0)

    def test_all_weights_one_is_the_plain_unweighted_matrix(self):
        rows = self._rows([("pass", "pass", 1.0, "a"), ("pass", "fail", 1.0, "a"),
                           ("fail", "fail", 1.0, "a"), ("fail", "pass", 1.0, "a")])
        tpr, tnr, _ = label_align.weighted_rates(rows)
        self.assertAlmostEqual(tpr, 0.5)
        self.assertAlmostEqual(tnr, 0.5)

    def test_an_empty_class_yields_none_rather_than_a_zero(self):
        tpr, tnr, _ = label_align.weighted_rates(
            self._rows([("pass", "pass", 1.0, "a")]))
        self.assertAlmostEqual(tpr, 1.0)
        self.assertIsNone(tnr)

    def test_the_bootstrap_ci_is_seeded_and_brackets_the_estimate(self):
        rows = self._rows([("pass", "pass", 1.0, "a")] * 30
                          + [("pass", "fail", 1.0, "a")] * 10
                          + [("fail", "fail", 1.0, "b")] * 15
                          + [("fail", "pass", 1.0, "b")] * 5)
        lo, hi = label_align.bootstrap_ci(rows, 0.6, rounds=300)
        again, _ = label_align.bootstrap_ci(rows, 0.6, rounds=300)
        self.assertEqual(lo, again)                      # seeded: reproducible
        tpr, tnr, _ = label_align.weighted_rates(rows)
        theta = label_align.corrected(0.6, tpr, tnr)
        self.assertLessEqual(lo, theta)
        self.assertLessEqual(theta, hi)
        self.assertLess(lo, hi)

    def test_a_coin_flip_grader_yields_no_correction_and_no_interval(self):
        # TPR + TNR - 1 == 0: the correction divides by ~0 and anything it returns
        # is noise, so both the point estimate and the interval must decline.
        rows = self._rows([("pass", "pass", 1.0, "a"), ("pass", "fail", 1.0, "a"),
                           ("fail", "fail", 1.0, "b"), ("fail", "pass", 1.0, "b")])
        self.assertIsNone(label_align.corrected(0.5, 0.5, 0.5))
        self.assertEqual(label_align.bootstrap_ci(rows, 0.5, rounds=200), (None, None))


class LabelAlignReproducesTheRecordedBaseline(unittest.TestCase):
    """The one end-to-end check available offline: the repaired tool must still
    produce the numbers the 0.0.1 findings doc published, or the repair moved them."""

    def test_the_committed_labels_still_score_63_68(self):
        path = os.path.join(_REPO, "evals", "labels", "request-plan-0.0.1-human.jsonl")
        if not os.path.exists(path):
            self.skipTest("0.0.1 labels not present")
        rows = []
        with open(path, encoding="utf-8") as f:
            for line in f:
                if not line.strip():
                    continue
                r = json.loads(line)
                rows.append({"human": r["verdict"],
                             "grader": "pass" if r["harness_status"] == "pass" else "fail",
                             "weight": 1.0, "stratum": r["split"]})
        tpr, tnr, m = label_align.weighted_rates(rows)
        self.assertEqual((m["tp"], m["fn"], m["tn"], m["fp"]), (58, 34, 15, 7))
        self.assertEqual(round(tpr * 100), 63)
        self.assertEqual(round(tnr * 100), 68)


class StratifiedSampling(unittest.TestCase):
    """Which cases get a human verdict, when there is budget for fewer than all."""

    def test_the_budget_is_split_evenly_between_the_harness_strata(self):
        # Not proportionally. The false-pass cell — human fail, harness pass — lives
        # entirely in the harness-PASS stratum and is the rarest thing measured, so
        # starving that stratum to chase false alarms leaves TNR on one or two cases.
        take = sampler.allocate({"pass": list(range(80)), "fail": list(range(30))}, 40)
        self.assertEqual(take["pass"], 20)
        self.assertEqual(take["fail"], 20)

    def test_a_stratum_smaller_than_its_share_gives_the_rest_away(self):
        # Asking for 20 from a stratum of 5 would silently return 5 and lose 15
        # labels the other stratum could have used.
        take = sampler.allocate({"pass": list(range(80)), "fail": list(range(5))}, 40)
        self.assertEqual(take["fail"], 5)
        self.assertEqual(take["pass"], 35)
        self.assertEqual(sum(take.values()), 40)

    def _grades(self, tmp):
        rows = ([{"case_id": i, "split": "dev", "status": "pass"} for i in range(1, 41)]
                + [{"case_id": i, "split": "dev", "status": "fail"} for i in range(41, 67)]
                + [{"case_id": i, "split": "test", "status": "pass"} for i in range(100, 122)]
                + [{"case_id": i, "split": "test", "status": "pass"} for i in range(122, 140)]
                + [{"case_id": i, "split": "train", "status": "pass"} for i in range(200, 228)])
        path = os.path.join(tmp, "grades.json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump({"results": rows}, f)
        return path

    def _run(self, tmp, *extra):
        out = os.path.join(tmp, "ids.json")
        # Floor pinned, never inherited: the live manifest's floor moves every cycle,
        # and a fixture tracking it would change what these assertions mean.
        rc = sampler.main(["--grades", self._grades(tmp), "--out", out,
                           "--held-out-from", "122", *extra])
        self.assertEqual(rc, 0)
        with open(out, encoding="utf-8") as f:
            return json.load(f)

    def test_the_held_out_tranche_is_taken_whole_and_train_is_never_touched(self):
        # Ids below the floor have been read, so the manifest calls its own `test`
        # membership nominal there. Sampling the few genuinely-unseen cases would
        # leave nothing to measure.
        with tempfile.TemporaryDirectory() as tmp:
            ids = self._run(tmp)
            self.assertTrue(set(range(122, 140)).issubset(ids))   # held out, entire
            self.assertFalse([i for i in ids if 100 <= i < 122])   # nominal test: out
            self.assertFalse([i for i in ids if i >= 200])         # train: out

    def test_the_selection_is_seeded_so_the_labelled_set_is_reproducible(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(self._run(tmp), self._run(tmp))

    def test_the_budget_is_a_ceiling_that_counts_the_held_out_tranche(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertLessEqual(len(self._run(tmp, "--budget", "60")), 60)
            self.assertLessEqual(len(self._run(tmp, "--budget", "30")), 30)

    def test_a_budget_the_tranche_alone_exceeds_is_refused(self):
        # The fixture's tranche is 18. Clamping it instead would still report the draw
        # at a sampling fraction of 1.0, and label-align divides that back out — so an
        # over-budget run would silently understate the held-out population.
        with tempfile.TemporaryDirectory() as tmp:
            out = os.path.join(tmp, "ids.json")
            rc = sampler.main(["--grades", self._grades(tmp), "--out", out,
                               "--held-out-from", "122", "--budget", "3"])
            self.assertEqual(rc, 64)
            self.assertFalse(os.path.exists(out))

    def test_a_budget_equal_to_the_tranche_is_allowed_and_spends_it_all(self):
        with tempfile.TemporaryDirectory() as tmp:
            ids = self._run(tmp, "--budget", "18")
            self.assertEqual(sorted(ids), list(range(122, 140)))

    def test_the_ceiling_holds_at_every_budget_the_tranche_fits_under(self):
        with tempfile.TemporaryDirectory() as tmp:
            for budget in (18, 19, 25, 40, 60):
                self.assertLessEqual(len(self._run(tmp, "--budget", str(budget))), budget)


class TheFloorComesFromTheManifest(unittest.TestCase):
    """One recorded floor governs. A second copy goes stale against the first and
    re-samples a spent tranche while still calling the rate held-out.

    Absent is the manifest's other lawful state, and the one it holds between the
    pass that spends a tranche and the batch that replaces it. Every assertion here
    is written to hold in both states, because a floor is pinned for only part of
    each cycle and a suite that assumed one state would go quiet during the other.
    """

    @staticmethod
    def _recorded_floor():
        with open(sampler.SPLIT_MANIFEST, encoding="utf-8") as f:
            return json.load(f).get("held_out_from")

    @staticmethod
    def _highest_spent_id():
        """Highest id any labelling pass has already drawn. Every `*-sample.json` is
        a completed draw, so its ids are read whatever the split manifest calls them."""
        highest = 0
        for path in glob.glob(os.path.join(_REPO, "evals", "labels", "*-sample.json")):
            with open(path, encoding="utf-8") as f:
                highest = max(highest, max(json.load(f)["case_ids"]))
        return highest

    def test_the_manifest_never_vouches_for_a_tranche_already_read(self):
        # The key's entire contract, and the one assertion that would have caught
        # `held_out_from: 168`: it named batch 5, which the 0.3.0 cut spent whole.
        # A floor at or below a drawn id re-samples read cases and still reports the
        # rate as held-out, which is the one error no output reveals.
        floor, spent = self._recorded_floor(), self._highest_spent_id()
        self.assertTrue(spent, "no sample files found; the check would be vacuous")
        self.assertTrue(
            floor is None or floor > spent,
            f"held_out_from {floor} is at or below id {spent}, already labelled")

    def test_a_pinned_floor_is_the_value_the_manifest_records(self):
        # On a fixture rather than the live manifest, which carries no floor between
        # batches; keying this to the live file would silence it for half of each cycle.
        with tempfile.TemporaryDirectory() as tmp:
            pinned = os.path.join(tmp, "request-plan.json")
            with open(pinned, "w", encoding="utf-8") as f:
                json.dump({"note": "batch 6", "held_out_from": 213, "splits": {}}, f)
            self.assertEqual(sampler.held_out_floor(pinned), 213)

    def test_the_committed_manifest_declines_rather_than_inventing_a_floor(self):
        # The default path an operator actually hits today. It has to reach exit 64 --
        # not a traceback, and above all not a floor guessed from the split data.
        if self._recorded_floor() is not None:
            self.skipTest("a floor is pinned; absence is covered on fixtures below")
        with self.assertRaises(LookupError):
            sampler.held_out_floor(sampler.SPLIT_MANIFEST)
        with tempfile.TemporaryDirectory() as tmp:
            grades = os.path.join(tmp, "grades.json")
            with open(grades, "w", encoding="utf-8") as f:
                json.dump({"results": [{"case_id": 1, "split": "dev",
                                        "status": "pass"}]}, f)
            err = io.StringIO()
            real_err, sys.stderr = sys.stderr, err
            try:
                rc = sampler.main(["--grades", grades])
            finally:
                sys.stderr = real_err
        self.assertEqual(rc, 64)
        self.assertIn("--held-out-from", err.getvalue())
        self.assertIn("no successor has been appended", err.getvalue())

    def test_an_absent_key_and_an_unreadable_manifest_ask_for_different_things(self):
        # Absent is routine -- a pass spent the tranche. Unreadable is damage. Told to
        # "name the current tranche", an operator whose tranche is spent has only the
        # spent id to name, which is the defect the deletion exists to prevent.
        with tempfile.TemporaryDirectory() as tmp:
            bare = os.path.join(tmp, "request-plan.json")
            with open(bare, "w", encoding="utf-8") as f:
                json.dump({"note": "restratified", "splits": {}}, f)
            with self.assertRaises(LookupError) as absent:
                sampler.held_out_floor(bare)
            with self.assertRaises(LookupError) as unreadable:
                sampler.held_out_floor(os.path.join(tmp, "not-there.json"))
        self.assertIn("Append a batch", str(absent.exception))
        self.assertNotIn("Append a batch", str(unreadable.exception))

    def test_a_manifest_with_no_floor_is_refused_rather_than_defaulted(self):
        with tempfile.TemporaryDirectory() as tmp:
            bare = os.path.join(tmp, "request-plan.json")
            with open(bare, "w", encoding="utf-8") as f:
                json.dump({"note": "restratified", "splits": {}}, f)
            with self.assertRaises(LookupError):
                sampler.held_out_floor(bare)

    def test_the_cli_declines_when_the_manifest_carries_no_floor(self):
        original = sampler.SPLIT_MANIFEST
        with tempfile.TemporaryDirectory() as tmp:
            bare = os.path.join(tmp, "request-plan.json")
            with open(bare, "w", encoding="utf-8") as f:
                json.dump({"note": "restratified", "splits": {}}, f)
            grades = os.path.join(tmp, "grades.json")
            with open(grades, "w", encoding="utf-8") as f:
                json.dump({"results": [{"case_id": 1, "split": "dev", "status": "pass"}]}, f)
            sampler.SPLIT_MANIFEST = bare
            try:
                self.assertEqual(sampler.main(["--grades", grades]), 64)
                self.assertEqual(
                    sampler.main(["--grades", grades, "--held-out-from", "168"]), 0)
            finally:
                sampler.SPLIT_MANIFEST = original


class GradesAreSelfDescribing(unittest.TestCase):
    """Both the sampler and the weighting key on `split`. Without it in the grades
    they would re-open the eval set and could read a different one than was graded —
    the failure mode the prompt_digest refusal exists to prevent."""

    def test_the_grades_file_carries_each_case_tranche(self):
        eval_set = {
            "skill_name": "request-plan", "shared_assertions": [],
            "evals": [{"id": 1, "prompt": "p", "assertions": [],
                       "expected_outcome": "plan", "split": "dev"},
                      {"id": 2, "prompt": "q", "assertions": [],
                       "expected_outcome": "plan", "split": "test"}],
        }
        with tempfile.TemporaryDirectory() as tmp:
            eval_path = os.path.join(tmp, "evals.json")
            with open(eval_path, "w", encoding="utf-8") as f:
                json.dump(eval_set, f)
            responses = os.path.join(tmp, "responses")
            os.makedirs(responses)
            for cid in (1, 2):
                with open(os.path.join(responses, f"{cid}.json"), "w",
                          encoding="utf-8") as f:
                    json.dump({"case_id": cid, "skill_version": "0.2.0",
                               "response": "**Context** c **Goal** g **Scope** s",
                               "prompt_digest": engine.prompt_digest(eval_set, cid),
                               "assertions_digest":
                                   engine.assertions_digest(eval_set, cid)}, f)
            out = os.path.join(tmp, "grades.json")
            with open(out, "w", encoding="utf-8") as sink:
                real, sys.stdout = sys.stdout, sink
                try:
                    grader.main(["--eval-set", eval_path, "--responses", responses,
                                 "--json"])
                finally:
                    sys.stdout = real
            with open(out, encoding="utf-8") as f:
                results = json.load(f)["results"]
        self.assertEqual({r["case_id"]: r["split"] for r in results},
                         {1: "dev", 2: "test"})


class MixedRevisionsAreVisible(unittest.TestCase):
    """A long sweep gets interrupted and resumed, so spanning two plugin revisions is
    normal — and sound exactly when the diff between them leaves the measured surface
    alone. Refusing would block a routine resume; silence would hide it."""

    def _grade(self, shas):
        eval_set = {
            "skill_name": "request-plan", "shared_assertions": [],
            "evals": [{"id": i, "prompt": f"p{i}", "assertions": [],
                       "expected_outcome": "plan", "split": "dev"}
                      for i in range(1, len(shas) + 1)],
        }
        with tempfile.TemporaryDirectory() as tmp:
            eval_path = os.path.join(tmp, "evals.json")
            with open(eval_path, "w", encoding="utf-8") as f:
                json.dump(eval_set, f)
            responses = os.path.join(tmp, "responses")
            os.makedirs(responses)
            for cid, sha in enumerate(shas, start=1):
                with open(os.path.join(responses, f"{cid}.json"), "w",
                          encoding="utf-8") as f:
                    json.dump({"case_id": cid, "skill_version": "0.2.0",
                               "plugin_sha": sha,
                               "response": "**Context** c **Goal** g **Scope** s",
                               "prompt_digest": engine.prompt_digest(eval_set, cid),
                               "assertions_digest":
                                   engine.assertions_digest(eval_set, cid)}, f)
            err = io.StringIO()
            real_out, real_err = sys.stdout, sys.stderr
            sys.stdout, sys.stderr = io.StringIO(), err
            try:
                rc = grader.main(["--eval-set", eval_path, "--responses", responses])
            finally:
                sys.stdout, sys.stderr = real_out, real_err
        return rc, err.getvalue()

    def test_two_revisions_are_reported_and_still_graded(self):
        rc, err = self._grade(["aaaaaaa", "bbbbbbb"])
        self.assertIn("span plugin revisions", err)
        self.assertIn("aaaaaaax1", err)
        self.assertNotEqual(rc, 2)

    def test_one_revision_says_nothing(self):
        _, err = self._grade(["aaaaaaa", "aaaaaaa"])
        self.assertNotIn("span plugin revisions", err)


class ContaminationScan(unittest.TestCase):
    """The strip removes the answer key but cannot remove the fact of the strip, so
    what a capture can still leak has to be measured rather than assumed."""

    def _scan(self, responses, grounding=None):
        eval_set = {"skill_name": "request-plan", "shared_assertions": [],
                    "evals": [{"id": cid, "prompt": "p", "assertions": [],
                               "expected_outcome": "plan",
                               "grounding": (grounding or {}).get(cid, ["hooks/a.sh"])}
                              for cid in responses]}
        with tempfile.TemporaryDirectory() as tmp:
            for cid, text in responses.items():
                with open(os.path.join(tmp, f"{cid}.json"), "w", encoding="utf-8") as f:
                    json.dump({"case_id": cid, "response": text}, f)
            return scanner.scan(eval_set, tmp)

    def test_an_answer_key_read_is_separated_from_the_softer_tells(self):
        # Reading the verdict makes a case evidence of nothing; noticing the harness
        # only bounds it. Folding them into one rate would let the fatal kind hide.
        report = self._scan({1: 'the case says expected_outcome: "refute"',
                             2: "see #333 for the work",
                             3: "an ordinary plan"})
        self.assertEqual(report["by_channel"]["answer-key"], [1])
        self.assertEqual(report["by_channel"]["harness-log"], [2])
        self.assertEqual(report["tainted"], [1, 2])

    def test_grounding_excuses_naming_eval_paths_but_not_reading_the_strip(self):
        # Cases 111/112/115/162/163/164 ground on evals/scripts/*.py, so naming the
        # harness is their job. Reading that the eval files are DELETED is not: case
        # 115 grounds on the review page and reported `git status` showing six eval
        # files removed, which is the strip itself and shaped its whole answer.
        grounded = {111: ["evals/scripts/eval-capture.py"]}
        self.assertEqual(
            self._scan({111: "modify eval-capture.py and eval-engine.py"}, grounded)
                ["tainted"], [])
        self.assertEqual(
            self._scan({111: "git status shows six eval files deleted and uncommitted"},
                       grounded)["by_channel"]["strip"], [111])

    def test_grounding_never_excuses_reading_the_verdict(self):
        report = self._scan({111: "expected_outcome: refute, so I refute"},
                            {111: ["evals/scripts/eval-capture.py"]})
        self.assertEqual(report["by_channel"]["answer-key"], [111])

    def test_a_clean_capture_reports_zero_and_succeeds(self):
        report = self._scan({1: "a plan about hooks", 2: "another plan"})
        self.assertEqual(report["tainted"], [])
        self.assertEqual(report["rate"], 0.0)


class ScanPatternsDoNotFireOnCorrectWork(unittest.TestCase):
    """Every loose version of these patterns fires on a sound response, and an
    inflated contamination rate misleads exactly as much as a deflated one. Each
    case below was a real false positive in the first full scan."""

    def _scan(self, text, grounding=("hooks/a.sh",)):
        eval_set = {"skill_name": "request-plan", "shared_assertions": [],
                    "evals": [{"id": 1, "prompt": "p", "assertions": [],
                               "expected_outcome": "plan", "grounding": list(grounding)}]}
        with tempfile.TemporaryDirectory() as tmp:
            with open(os.path.join(tmp, "1.json"), "w", encoding="utf-8") as f:
                json.dump({"case_id": 1, "response": text}, f)
            return scanner.scan(eval_set, tmp)["tainted"]

    def test_a_field_name_is_not_a_verdict(self):
        # Case 146 planned documentation for the eval-set schema and listed the
        # fields, having read them from eval-engine.py — which the strip keeps on
        # purpose. Naming `expected_outcome` is not reading one.
        self.assertEqual(
            self._scan("per-case `id`, `prompt`, `expected_outcome`, `assertions[]`"), [])
        self.assertEqual(
            self._scan('the case declares expected_outcome: "refute", so I refute'), [1])

    def test_proposing_an_eval_case_is_not_noticing_one(self):
        # Cases 166, 167 and 128 all planned to ADD an eval case — the most ordinary
        # recommendation a plan makes in this repo.
        self.assertEqual(self._scan("P0: add an eval case covering the new rows"), [])
        self.assertEqual(self._scan("a live-behavior eval case proves the agent obeys"), [])

    def test_naming_the_capture_script_as_a_surface_is_not_a_leak(self):
        # Plans legitimately target eval-capture.py; the tell is reading THIS run's
        # commits, not knowing the file exists.
        self.assertEqual(self._scan("modify `eval-capture.py` to add a flag"), [])
        self.assertEqual(self._scan("recent commits (#333) are all eval work"), [1])

    def test_housekeeping_prose_about_deleting_a_file_is_not_the_strip(self):
        # The strip channel's deletion alternative has to stay bound to `eval`. Without
        # that prefix it is a generic "file(s)...deleted" matcher, and ordinary cleanup
        # prose — which this repo's plans propose constantly — inflates the rate.
        self.assertEqual(
            self._scan("the stale lock file should be deleted before the next run"), [])
        self.assertEqual(
            self._scan("plan: have the job delete its set of temp files when it exits"), [])
        self.assertEqual(
            self._scan("orphaned worktrees and their taxonomy files can be deleted"), [])

    def test_the_prefix_requirement_does_not_disarm_the_channel(self):
        # Reached only by the deletion alternative: no other pattern in the channel
        # matches this phrasing, so a green here proves the narrowing kept its teeth.
        self.assertEqual(
            self._scan("git status shows the eval taxonomy was deleted in this tree"), [1])
        self.assertEqual(
            self._scan("six evals files are showing up deleted under evals/"), [1])

    def test_saying_this_prompt_is_an_eval_case_still_trips(self):
        self.assertEqual(self._scan("this exact prompt is even a tracked eval case"), [1])
        self.assertEqual(self._scan("you're testing the skill against its own case"), [1])


if __name__ == "__main__":
    unittest.main()
