"""Tests for benchmarkkit.deterministic_run.

`run()` is the deterministic orchestrator: it is the function that decides
whether a benchmark run passed, where the record lands, and what gets rotated
into history. The two generator calls are the only impure part, so they are
replaced with recording fakes — no Swift build, no filesystem outside a
temporary directory, no network.

stdlib unittest only (no pytest).
"""

from __future__ import annotations

import json
import os
import tempfile
import unittest
from unittest import mock

from benchmarkkit import deterministic_run
from benchmarkkit.metrics import PathMetrics, Tokens


def path_metrics(pass_fail="pass", loc=120, tests=8):
    return PathMetrics(
        tokens=Tokens(input=100, output=50, total=150),
        cost_usd=None, wall_clock_s=1.5, loc_produced=loc, test_count=tests,
        coverage_pct=82.0, estimate_complexity_score=21, stage_count=10,
        pass_fail=pass_fail, app_path="benchmark/workdirs/x/app",
    )


class TestIso(unittest.TestCase):
    """The compact run-id timestamp is the only format history sorts on."""

    def test_converts_the_compact_form_to_iso8601(self):
        self.assertEqual("2020-01-02T03:04:05Z",
                         deterministic_run.iso("20200102T030405Z"))

    def test_a_value_shorter_than_the_format_passes_through_untouched(self):
        # Guards against silently emitting a mangled timestamp from a bad run id.
        self.assertEqual("2020", deterministic_run.iso("2020"))
        self.assertEqual("20200102T0304", deterministic_run.iso("20200102T0304"))

    def test_fifteen_characters_is_the_conversion_boundary(self):
        self.assertEqual("20200102T03040", deterministic_run.iso("20200102T03040"))
        self.assertEqual("2020-01-02T03:04:05Z",
                         deterministic_run.iso("20200102T030405"))

    def test_the_trailing_field_is_read_positionally_not_by_suffix(self):
        self.assertEqual("2020-01-02T03:04:05Z",
                         deterministic_run.iso("20200102T030405Z-abc1234"))


class TestRun(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = self._tmp.name
        self.addCleanup(self._tmp.cleanup)
        self.record_path = os.path.join(self.tmp, "results", "runs", "deterministic", "r.json")
        self.history = os.path.join(self.tmp, "results", "history.json")
        self.runs_dir = os.path.join(self.tmp, "results", "runs")

    def call_run(self, with_pm, without_pm, run_id="deterministic-20200102T030405Z-abc1234"):
        with mock.patch.object(deterministic_run.generators, "generate_with_plugin",
                               return_value=with_pm) as gen_with, \
             mock.patch.object(deterministic_run.generators, "generate_without_plugin",
                               return_value=without_pm) as gen_without:
            result = deterministic_run.run(
                workdir=os.path.join(self.tmp, "workdir"), run_id=run_id,
                timestamp="20200102T030405Z", git_sha="abc1234",
                record_path=self.record_path, history=self.history,
                runs_dir=self.runs_dir, template_dir="/nonexistent/template",
                plugin_root="/nonexistent/root",
                estimate_calc_path="/nonexistent/estimate-calc.py")
        return result, gen_with, gen_without

    def read_record(self):
        with open(self.record_path, encoding="utf-8") as f:
            return json.load(f)

    def test_both_arms_pass_yields_exit_code_zero_and_a_full_record(self):
        result, gen_with, gen_without = self.call_run(path_metrics(), path_metrics("pass", 90, 4))

        self.assertEqual(0, result.exit_code)
        self.assertEqual(1, gen_with.call_count)
        self.assertEqual(1, gen_without.call_count)

        record = self.read_record()
        self.assertEqual("deterministic", record["mode"])
        self.assertEqual("abc1234", record["git_sha"])
        # The timestamp reaches the record in ISO form, not the compact run-id form.
        self.assertEqual("2020-01-02T03:04:05Z", record["timestamp_utc"])
        self.assertEqual(120, record["paths"]["with"]["loc_produced"])
        self.assertEqual(90, record["paths"]["without"]["loc_produced"])

    def test_a_failing_arm_makes_the_run_fail_but_still_records_it(self):
        # Evidence must survive a failure: a run that fails and writes nothing
        # is indistinguishable from a run that never happened.
        result, _, _ = self.call_run(path_metrics("pass"), path_metrics("fail"))

        self.assertEqual(1, result.exit_code)
        self.assertTrue(os.path.isfile(self.record_path))
        self.assertEqual("fail", self.read_record()["paths"]["without"]["pass_fail"])

    def test_either_arm_failing_is_enough_to_fail_the_run(self):
        result, _, _ = self.call_run(path_metrics("fail"), path_metrics("pass"))
        self.assertEqual(1, result.exit_code)

    def test_the_record_directory_is_created_when_it_does_not_exist(self):
        self.assertFalse(os.path.isdir(os.path.dirname(self.record_path)))
        self.call_run(path_metrics(), path_metrics())
        self.assertTrue(os.path.isfile(self.record_path))

    def test_the_run_is_rotated_into_history_and_the_per_run_detail_file(self):
        self.call_run(path_metrics(), path_metrics())

        with open(self.history, encoding="utf-8") as f:
            history = json.load(f)
        run_ids = [r["run_id"] for r in history["deterministic"]]
        self.assertEqual(["deterministic-20200102T030405Z-abc1234"], run_ids)

        detail = os.path.join(self.runs_dir, "deterministic",
                              "deterministic-20200102T030405Z-abc1234.json")
        self.assertTrue(os.path.isfile(detail))

    def test_history_keeps_only_the_newest_three_runs_per_mode(self):
        for n in range(1, 6):
            self.record_path = os.path.join(
                self.tmp, "results", "runs", "deterministic", f"r{n}.json")
            self.call_run(path_metrics(), path_metrics(), run_id=f"deterministic-run-{n}")

        with open(self.history, encoding="utf-8") as f:
            history = json.load(f)
        self.assertEqual(3, len(history["deterministic"]))
        self.assertEqual(
            {"deterministic-run-3", "deterministic-run-4", "deterministic-run-5"},
            {r["run_id"] for r in history["deterministic"]})

    def test_the_generators_receive_the_workdir_and_template_they_were_given(self):
        _, gen_with, gen_without = self.call_run(path_metrics(), path_metrics())

        with_kwargs = gen_with.call_args.kwargs
        self.assertEqual(os.path.join(self.tmp, "workdir"), with_kwargs["workdir"])
        self.assertEqual("/nonexistent/template", with_kwargs["template_dir"])
        # Only the WITH arm consumes the estimate seam; wiring it into the
        # baseline would contaminate the comparison.
        self.assertIn("estimate_calc_path", with_kwargs)
        self.assertNotIn("estimate_calc_path", gen_without.call_args.kwargs)


if __name__ == "__main__":
    unittest.main()
