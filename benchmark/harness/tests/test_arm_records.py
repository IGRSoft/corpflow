"""Independently-runnable arms (AC-1 to AC-6): selection resolution, whole-budget
semantics, single-arm partial scoping, the arm record shape, and own-arm measurement
plus oracle grading.

All dispatch is faked and the grader is injected — zero real `claude -p` calls, no
credential, no spend.
"""

import os
import shutil
import sys as _sys
import tempfile
import unittest

from benchmarkkit import oracle
from benchmarklive import baseline
from benchmarklive.dispatch import _measure_arm, build_arm_record, dispatch

_sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # _helpers under any runner
from _helpers import (  # noqa: E402
    RecordingFakeDispatcher,
    SequencedFakeDispatcher,
    fake_estimate_runner,
    load_json,
    make_live_sandbox,
    single_object_usage,
    stub_git_sha,
)

_ENV = {"ANTHROPIC_API_KEY": "k"}


class ArmSelectionMatrix(unittest.TestCase):
    """The truth table AD-5 fixes; `--arm` unset is distinct from `--arm both`."""

    def _sel(self, arm=None, without_arm=None, stages=None):
        return baseline.resolve_arm_selection(arm, without_arm, stages)

    def test_unset_on_full_run_is_legacy_paired(self):
        sel = self._sel()
        self.assertEqual(sel.dispatch, ("without", "with"))
        self.assertEqual(sel.record_shape, baseline.SHAPE_PAIRED)
        self.assertIsNone(sel.arm)

    def test_unset_on_stage_subset_keeps_the_legacy_skip_default(self):
        sel = self._sel(stages=["PL"])
        self.assertEqual(sel.dispatch, ("with",))
        self.assertEqual(sel.record_shape, baseline.SHAPE_PAIRED)

    def test_unset_with_explicit_real_pairs(self):
        self.assertEqual(self._sel(without_arm="real", stages=["PL"]).dispatch,
                         ("without", "with"))

    def test_unset_with_explicit_skip_runs_with_alone(self):
        self.assertEqual(self._sel(without_arm="skip").dispatch, ("with",))

    def test_arm_both_pairs_and_tolerates_explicit_real(self):
        for without_arm in (None, "real"):
            sel = self._sel(arm="both", without_arm=without_arm)
            self.assertEqual(sel.dispatch, ("without", "with"))
            self.assertEqual(sel.record_shape, baseline.SHAPE_PAIRED)

    def test_arm_both_contradicts_skip(self):
        with self.assertRaises(baseline.ArmSelectionError):
            self._sel(arm="both", without_arm="skip")

    def test_single_arm_selection_shape(self):
        for arm in ("with", "without"):
            sel = self._sel(arm=arm)
            self.assertEqual(sel.dispatch, (arm,))
            self.assertEqual(sel.record_shape, baseline.SHAPE_ARM)
            self.assertEqual(sel.arm, arm)

    def test_explicit_arm_overrides_the_implicit_subset_skip(self):
        # Explicit beats implicit, mirroring resolve_arm_mode's existing precedence.
        self.assertEqual(self._sel(arm="without", stages=["PL"]).dispatch, ("without",))

    def test_single_arm_contradicts_any_explicit_without_arm(self):
        for without_arm in ("real", "skip"):
            with self.assertRaises(baseline.ArmSelectionError):
                self._sel(arm="with", without_arm=without_arm)

    def test_unknown_values_are_usage_errors(self):
        with self.assertRaises(baseline.ArmSelectionError):
            self._sel(arm="neither")
        with self.assertRaises(baseline.ArmSelectionError):
            self._sel(without_arm="maybe")

    def test_resolve_arm_mode_is_untouched(self):
        self.assertEqual(baseline.resolve_arm_mode(None, None), baseline.ARM_REAL)
        self.assertEqual(baseline.resolve_arm_mode(None, ["PL"]), baseline.ARM_SKIP)


class SingleArmDispatch(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="arm-rec-")
        self.sb = make_live_sandbox(self.tmp)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _dispatch(self, dispatcher, arm, budget_usd=100.0, stages=None, est_cost=0.001):
        return dispatch(
            workdir=self.sb.run_id, budget=budget_usd, record_path=self.sb.record_path,
            benchmark_dir=self.sb.benchmark_dir, dispatcher=dispatcher, env=_ENV,
            estimate_runner=fake_estimate_runner(est_cost), stages=stages or ["PL"],
            git_sha_runner=stub_git_sha,
            selection=baseline.resolve_arm_selection(arm, None, None))

    def test_arm_without_dispatches_only_that_arm_bare(self):
        fake = RecordingFakeDispatcher()
        self.assertEqual(self._dispatch(fake, "without"), 0)
        self.assertEqual(len(fake.calls), 1)
        argv, _ = fake.calls[0]
        self.assertNotIn("--agent", argv)

    def test_arm_with_dispatches_only_that_arm_bound(self):
        fake = RecordingFakeDispatcher()
        self.assertEqual(self._dispatch(fake, "with"), 0)
        self.assertEqual(len(fake.calls), 1)
        argv, _ = fake.calls[0]
        self.assertIn("--agent", argv)

    def test_arm_record_shape(self):
        # AC-6: the discriminator is present, only the dispatched arm's metrics are
        # populated, the opposite key is omitted outright, and there is no comparison.
        self.assertEqual(self._dispatch(RecordingFakeDispatcher(), "with"), 0)
        rec = load_json(self.sb.record_path)
        self.assertEqual(rec["arm"], "with")
        self.assertEqual(list(rec["paths"].keys()), ["with"])
        self.assertNotIn("without", rec["paths"])
        self.assertNotIn("comparison", rec)
        self.assertEqual(rec["mode"], "live")

    def test_arm_record_omits_rather_than_reusing_the_skip_placeholder(self):
        # R7: the placeholder reads pass_fail="pass" with stage_count 1, so reusing it
        # for an arm that ran elsewhere would render a fabricated pass.
        self.assertEqual(self._dispatch(RecordingFakeDispatcher(), "without"), 0)
        rec = load_json(self.sb.record_path)
        self.assertNotIn("with", rec["paths"])
        self.assertEqual(list(rec["paths"].keys()), ["without"])

    def test_arm_stage_rows_are_tagged_with_their_own_arm(self):
        self.assertEqual(self._dispatch(RecordingFakeDispatcher(), "without"), 0)
        rec = load_json(self.sb.record_path)
        self.assertTrue(rec["stages"])
        self.assertTrue(all(s["arm"] == "without" for s in rec["stages"]))

    def test_single_arm_run_gets_the_whole_budget(self):
        # AC-2: est 0.4/stage over 2 stages. A paired run would reserve half of 1.0 and
        # gate the second stage; a single-arm run has the whole 1.0 and completes both.
        fake = SequencedFakeDispatcher([single_object_usage(cost=0.4),
                                        single_object_usage(cost=0.4)])
        rc = self._dispatch(fake, "with", budget_usd=1.0, stages=["PL", "AR"],
                            est_cost=0.4)
        self.assertEqual(rc, 0)
        self.assertEqual(len(fake.calls), 2)
        rec = load_json(self.sb.record_path)
        self.assertEqual(rec["paths"]["with"]["stage_count"], 2)

    def test_preflight_projects_one_arm_only(self):
        # A paired run would project 2 x 0.5 = 1.0 and decline against 0.6; one arm
        # projects 0.5 and proceeds.
        rc = self._dispatch(RecordingFakeDispatcher(), "with", budget_usd=0.6,
                            est_cost=0.5)
        self.assertEqual(rc, 0)

    def test_clean_single_arm_run_omits_the_partial_flag(self):
        self.assertEqual(self._dispatch(RecordingFakeDispatcher(), "with"), 0)
        self.assertNotIn("live_partial", load_json(self.sb.record_path))

    def test_degraded_single_arm_run_sets_partial_on_that_arm(self):
        # AC-3: the flag is attributable to the one arm that ran; no other arm exists
        # to have raised it.
        rc = self._dispatch(SequencedFakeDispatcher(["not json at all"]), "without")
        self.assertEqual(rc, 4)
        rec = load_json(self.sb.record_path)
        self.assertTrue(rec["live_partial"])
        self.assertEqual(rec["arm"], "without")
        self.assertIsNone(rec["paths"]["without"]["tokens"]["total"])

    def test_single_arm_run_is_measured_and_graded(self):
        # AC-4/R5: the behaviour change. Grading used to be reached only on the paired
        # path, so a single-arm run produced no oracle payload at all.
        self.assertEqual(self._dispatch(RecordingFakeDispatcher(), "with"), 0)
        rec = load_json(self.sb.record_path)
        oracle_payload = rec["paths"]["with"]["oracle"]
        self.assertIsNotNone(oracle_payload)
        self.assertFalse(oracle_payload["built"])  # sandbox arm ships no Package.swift
        self.assertIn("cases_digest", oracle_payload)

    def test_legacy_skip_path_is_also_graded_now(self):
        # The same R5 gap: --without-arm skip is a WITH-only run and was ungraded too.
        rc = dispatch(
            workdir=self.sb.run_id, budget=100.0, record_path=self.sb.record_path,
            benchmark_dir=self.sb.benchmark_dir, dispatcher=RecordingFakeDispatcher(),
            env=_ENV, estimate_runner=fake_estimate_runner(0.001), stages=["PL"],
            git_sha_runner=stub_git_sha, without_arm=baseline.ARM_SKIP)
        self.assertEqual(rc, 0)
        rec = load_json(self.sb.record_path)
        self.assertIsNotNone(rec["paths"]["with"]["oracle"])
        self.assertNotIn("arm", rec)  # still the legacy paired shape


class ArmGrading(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="arm-grade-")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_measure_arm_uses_the_injected_grader(self):
        graded = oracle.OracleResult(built=True, cases_total=2, cases_passed=2,
                                     cases_digest="sha256:" + "a" * 64)
        seen = []

        def grader(app_dir, warn=None):
            seen.append(app_dir)
            return graded

        arm_cwd = os.path.join(self.tmp, "with")
        os.makedirs(arm_cwd)
        app = _measure_arm(arm_cwd, self.tmp, dispatched=1, warn=lambda _s: None,
                           grader=grader)
        self.assertEqual(seen, [arm_cwd])
        self.assertEqual(app.oracle["cases_digest"], "sha256:" + "a" * 64)

    def test_build_arm_record_carries_the_graded_payload(self):
        app = baseline.AppMeasure(loc_produced=120, test_count=4, pass_fail="pass",
                                  app_path="benchmark/workdirs/r/with",
                                  oracle={"built": True, "cases_total": 2,
                                          "cases_passed": 2, "pass_rate": 1.0,
                                          "cases_digest": "sha256:" + "b" * 64})
        rec = build_arm_record("live-r-with", "2026-08-14T10:20:01Z", "abc1234", 50.0,
                               "with", usages=[], stages_dispatched=1,
                               arm_partial=False, app=app).to_dict()
        self.assertEqual(rec["arm"], "with")
        self.assertEqual(rec["paths"]["with"]["loc_produced"], 120)
        self.assertEqual(rec["paths"]["with"]["oracle"]["cases_digest"],
                         "sha256:" + "b" * 64)
        self.assertNotIn("comparison", rec)


class CaseSetDigest(unittest.TestCase):
    _CASES = [
        {"id": "b", "description": "second", "args": ["--moves", "1"],
         "expect": {"exit_code": 0, "stdout": "x"}, "tier": "specified"},
        {"id": "a", "description": "first", "args": ["--moves", "0"],
         "expect": {"exit_code": 0, "stdout": "y"}, "tier": "implied"},
    ]

    def test_digest_shape(self):
        digest = oracle.oracle_cases_digest(self._CASES)
        self.assertTrue(digest.startswith("sha256:"))
        self.assertEqual(len(digest), len("sha256:") + 64)

    def test_digest_is_order_insensitive(self):
        self.assertEqual(oracle.oracle_cases_digest(self._CASES),
                         oracle.oracle_cases_digest(list(reversed(self._CASES))))

    def test_changing_the_case_set_changes_the_digest(self):
        # AC-12: the whole point of the axis.
        changed = [dict(c) for c in self._CASES]
        changed[0]["expect"] = {"exit_code": 1, "stdout": "x"}
        self.assertNotEqual(oracle.oracle_cases_digest(self._CASES),
                            oracle.oracle_cases_digest(changed))

    def test_rewording_a_description_does_not_change_the_digest(self):
        # A fail-closed gate that fires on cosmetics is a gate that gets bypassed.
        reworded = [dict(c) for c in self._CASES]
        reworded[0]["description"] = "completely different prose"
        self.assertEqual(oracle.oracle_cases_digest(self._CASES),
                         oracle.oracle_cases_digest(reworded))

    def test_adding_a_scoring_key_changes_the_digest(self):
        # Exclude-list, not include-list: a new key is covered by default.
        extended = [dict(c) for c in self._CASES]
        extended[0]["timeout_s"] = 5
        self.assertNotEqual(oracle.oracle_cases_digest(self._CASES),
                            oracle.oracle_cases_digest(extended))

    def test_grade_stamps_the_digest_even_when_the_arm_does_not_build(self):
        tmp = tempfile.mkdtemp(prefix="arm-digest-")
        try:
            result = oracle.grade(tmp, cases=self._CASES, warn=lambda _s: None)
            self.assertFalse(result.built)
            self.assertEqual(result.cases_digest,
                             oracle.oracle_cases_digest(self._CASES))
            self.assertEqual(list(result.to_dict())[-1], "cases_digest")
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    def test_hand_built_result_without_a_digest_keeps_its_byte_shape(self):
        out = oracle.OracleResult(built=True, cases_total=1, cases_passed=1).to_dict()
        self.assertNotIn("cases_digest", out)


class ArmRecordDegradation(unittest.TestCase):
    """AC-14: an arm record handed straight to the analyzer and the reporter degrades
    — the absent arm shows as absent, never as a zero and never as a fabricated pass."""

    def setUp(self):
        from benchmarkkit import analysis, metrics, report
        self.analysis, self.report = analysis, report
        pm = metrics.PathMetrics(
            tokens=metrics.Tokens(input=250, output=50, total=300,
                                  cache_read=10, cache_creation=20),
            cost_usd=0.5, wall_clock_s=12.5, loc_produced=100, test_count=4,
            coverage_pct=None, estimate_complexity_score=0, stage_count=1,
            pass_fail="pass", app_path="benchmark/workdirs/r/with",
            oracle={"built": True, "cases_total": 2, "cases_passed": 2,
                    "pass_rate": 1.0, "cases_digest": "sha256:" + "c" * 64})
        self.record = metrics.make_arm_record(
            run_id="live-r-with", timestamp_utc="2026-08-14T10:20:01Z", mode="live",
            git_sha="abc1234", budget_usd=50.0, arm="with", pm=pm).to_dict()

    def test_analyzer_reports_the_absent_arm_as_absent(self):
        result = self.analysis.analyze(self.record)
        without = result["quality"]["without"]
        self.assertIsNone(without["loc_produced"])
        self.assertIsNone(without["pass_fail"])   # never a fabricated pass
        self.assertIsNone(without["oracle"])
        self.assertNotIn("—0", self.analysis.render_markdown(result))

    def test_analyzer_adds_no_placeholder_caveat_and_no_arm_outlier(self):
        result = self.analysis.analyze(self.record)
        self.assertTrue(any("single-arm record" in c for c in result["caveats"]))
        self.assertFalse(any("mechanism-default placeholder" in c
                             for c in result["caveats"]))
        self.assertEqual([f for f in result["outliers"]
                          if f["type"] == "missing_app_verdict"], [])

    def test_reporter_renders_the_absent_arm_path_as_an_em_dash(self):
        # R18: deriving `workdirs/<run_id>/without` would render a path that never
        # existed as though it did.
        self.assertEqual(self.report._app_path(self.record, "without"), "—")
        self.assertEqual(self.report._app_path(self.record, "with"),
                         "benchmark/workdirs/r/with")
        html = self.report.render_html({"live": [self.record]})
        self.assertIn("WITHOUT app:", html)

    def test_reporter_still_derives_a_workdir_for_a_present_but_unmeasured_arm(self):
        # Byte-stability: a paired live record whose arm carries app_path=None keeps
        # the derived path it has always rendered.
        paired = dict(self.record)
        paired["paths"] = {"with": dict(self.record["paths"]["with"], app_path=None),
                           "without": dict(self.record["paths"]["with"], app_path=None)}
        self.assertEqual(self.report._app_path(paired, "without"),
                         "benchmark/workdirs/live-r-with/without")


class AnalyzerFallbackSkipsArmRecords(unittest.TestCase):
    """R19/AC-14: the newest-record fallback must not select half a comparison."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="arm-fallback-")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.bin_dir = os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "bin")

    def _write(self, relpath, payload):
        import json
        path = os.path.join(self.tmp, relpath)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(payload, f)
        return path

    def _paired(self, run_id):
        return {"run_id": run_id, "timestamp_utc": "2026-08-14T10:20:01Z",
                "mode": "live", "git_sha": "abc1234", "budget_usd": 50.0,
                "paths": {"with": {"loc_produced": 120, "pass_fail": "pass"},
                          "without": {"loc_produced": 90, "pass_fail": "pass"}},
                "comparison": {}, "stages": []}

    def _arm(self, run_id):
        record = dict(self._paired(run_id))
        record["paths"] = {"with": record["paths"]["with"]}
        record["arm"] = "with"
        record.pop("comparison")
        return record

    def _analyze(self, args):
        import subprocess
        return subprocess.run(
            [_sys.executable, os.path.join(self.bin_dir, "bench-analyze"), *args],
            cwd=self.tmp, stdin=subprocess.DEVNULL, capture_output=True, text=True,
            timeout=120)

    def test_history_fallback_skips_an_arm_record(self):
        history = self._write("benchmark/results/history.json",
                              {"live": [self._paired("live-complete"),
                                        self._arm("live-arm-only")]})
        out = os.path.join(self.tmp, "analysis.md")
        proc = self._analyze(["--history", history, "--out", out])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        with open(out, encoding="utf-8") as f:
            markdown = f.read()
        self.assertIn("live-complete", markdown.splitlines()[0])
        self.assertNotIn("live-arm-only", markdown.splitlines()[0])

    def test_runs_dir_fallback_skips_a_newer_arm_record(self):
        runs = os.path.join("benchmark", "results", "runs", "live")
        self._write(os.path.join(runs, "a-complete.json"), self._paired("live-complete"))
        arm_path = self._write(os.path.join(runs, "b-arm.json"), self._arm("live-arm-only"))
        os.utime(arm_path, (2 ** 31, 2 ** 31))  # newest by mtime
        out = os.path.join(self.tmp, "analysis.md")
        proc = self._analyze(["--history", os.path.join(self.tmp, "missing.json"),
                              "--out", out])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        with open(out, encoding="utf-8") as f:
            self.assertIn("live-complete", f.read().splitlines()[0])


if __name__ == "__main__":
    unittest.main()
