"""Report parity (port of ReportTests): metric labels, +4 delta, 581,886 grouping,
app_path fallback, empty/missing history safe, cache-hit% row + em-dash degrade,
build_report writes a file. HTML is substring-gated.
"""

import os
import re
import shutil
import tempfile
import unittest

from benchmarkkit import report
from benchmarkkit.metrics import PathMetrics, Tokens, make_record


def _det_record():
    with_pm = PathMetrics(Tokens(), None, 0.03, 345, 20, 0.0, 15, 5, "pass",
                          "benchmark/workdirs/det-1/with")
    without_pm = PathMetrics(Tokens(), None, 0.001, 345, 20, 0.0, 0, 1, "pass",
                             "benchmark/workdirs/det-1/without")
    return make_record("det-1", "2026-07-05T18:48:06Z", "deterministic", "sha", None,
                       with_pm, without_pm).to_dict()


def _live_record_with_cache():
    wt = Tokens(input=574557, output=7329, total=581886, cache_read=7403, cache_creation=2597)
    with_pm = PathMetrics(wt, 1.241815, 92.191, 391, 0, 0.0, 0, 3, "pass",
                          "benchmark/workdirs/live-1/with")
    without_pm = PathMetrics(Tokens(input=1, output=1, total=2), 0.5, 10.0, 318, 0, 0.0, 0, 1,
                             "pass", "benchmark/workdirs/live-1/without")
    return make_record("live-1", "2026-07-01T07:45:49Z", "live", "sha", None,
                       with_pm, without_pm).to_dict()


class ReportTests(unittest.TestCase):
    def test_metric_labels_present(self):
        html = report.render_html({"deterministic": [_det_record()]})
        for _, label, _ in report.METRIC_ROWS:
            self.assertIn(label, html)

    def test_stage_count_plus_four_delta(self):
        html = report.render_html({"deterministic": [_det_record()]})
        self.assertIn("+4", html)  # stage_count 5 vs 1

    def test_app_paths_present(self):
        html = report.render_html({"deterministic": [_det_record()]})
        self.assertIn("benchmark/workdirs/det-1/with", html)
        self.assertIn("benchmark/workdirs/det-1/without", html)

    def test_token_grouping(self):
        html = report.render_html({"live": [_live_record_with_cache()]})
        self.assertIn("581,886", html)

    def test_cache_hit_row_computes(self):
        html = report.render_html({"live": [_live_record_with_cache()]})
        expected = report._ratio_fmt(7403 / (574557 + 2597 + 7403) * 100)
        self.assertIn(f"{expected}%", html)

    def test_cache_hit_degrades_when_cache_keys_are_null(self):
        # Null cache keys → cache-hit % row is an em-dash.
        rec = _det_record()  # deterministic tokens all null → cache-hit degrades
        html = report.render_html({"deterministic": [rec]})
        self.assertIn("cache-hit %", html)
        self.assertIn("&mdash;", html)

    def test_app_path_fallback(self):
        rec = _det_record()
        rec["paths"]["with"]["app_path"] = None
        html = report.render_html({"deterministic": [rec]})
        self.assertIn("benchmark/workdirs/det-1/with", html)  # synthesized from run_id

    def test_empty_history_safe(self):
        html = report.render_html({})
        self.assertIn("No benchmark results yet", html)

    def test_nested_background_rollup_row(self):
        from benchmarkkit.metrics import StageAttribution, StageCoverage
        rec = _live_record_with_cache()
        cov = StageCoverage(agents=["corpflow:developer"], skills=[], commands=[],
                            tool_calls=12, nested_background=3)
        rec["stages"] = [StageAttribution("DV", 100, 0, 0, 50, 0.1, coverage=cov).to_dict()]
        html = report.render_html({"live": [rec]})
        self.assertIn("nested background spawns", html)
        self.assertIn("tool calls", html)

    def test_build_report_writes_file_and_missing_safe(self):
        td = tempfile.mkdtemp(prefix="rep-")
        try:
            out = os.path.join(td, "result.html")
            # Missing history file → safe (empty report).
            report.build_report(os.path.join(td, "nope.json"), out)
            self.assertTrue(os.path.exists(out))
            with open(out, encoding="utf-8") as f:
                self.assertIn("No benchmark results yet", f.read())
        finally:
            shutil.rmtree(td, ignore_errors=True)


class CostFormatting(unittest.TestCase):
    """`cost_usd` renders at fixed 2dp in the HTML report; the generic formatter that
    still serves tokens/LOC/wall-clock keeps trimming trailing zeros."""

    def _rec(self, with_cost, without_cost, wall_clock=10.0):
        with_pm = PathMetrics(Tokens(input=1, output=1, total=2), with_cost, wall_clock,
                              345, 20, 0.0, 15, 5, "pass", "benchmark/workdirs/c-1/with")
        without_pm = PathMetrics(Tokens(input=1, output=1, total=2), without_cost, wall_clock,
                                 345, 20, 0.0, 15, 5, "pass", "benchmark/workdirs/c-1/without")
        return make_record("c-1", "2026-08-01T00:00:00Z", "live", "sha", None,
                           with_pm, without_pm).to_dict()

    def _cost_cells(self, html):
        row = html.split("cost (USD)</td>", 1)[1].split("</tr>", 1)[0]
        return re.findall(r"<td[^>]*>(.*?)</td>", row)

    def test_whole_dollar_keeps_two_decimals(self):
        html = report.render_html({"live": [self._rec(3.0, 3.0)]})
        self.assertEqual(self._cost_cells(html)[:2], ["3.00", "3.00"])

    def test_one_decimal_pads_to_two(self):
        html = report.render_html({"live": [self._rec(3.5, 3.5)]})
        self.assertEqual(self._cost_cells(html)[:2], ["3.50", "3.50"])

    def test_long_float_truncates_to_two(self):
        html = report.render_html({"live": [self._rec(3.14159265, 3.14159265)]})
        self.assertEqual(self._cost_cells(html)[:2], ["3.14", "3.14"])

    def test_sub_cent_rounds_up(self):
        html = report.render_html({"live": [self._rec(0.005, 0.005)]})
        self.assertEqual(self._cost_cells(html)[:2], ["0.01", "0.01"])

    def test_delta_keeps_sign_at_two_decimals(self):
        html = report.render_html({"live": [self._rec(3.0, 1.5)]})
        self.assertEqual(self._cost_cells(html)[2], "+1.50")
        html = report.render_html({"live": [self._rec(1.5, 3.0)]})
        self.assertEqual(self._cost_cells(html)[2], "-1.50")

    def test_missing_cost_degrades_to_em_dash(self):
        html = report.render_html({"live": [self._rec(None, None)]})
        self.assertEqual(self._cost_cells(html), ["&mdash;", "&mdash;", "&mdash;"])

    def test_budget_badge_is_two_decimals(self):
        rec = self._rec(3.0, 3.0)
        rec["budget_usd"] = 5.0
        self.assertIn("budget $5.00", report.render_html({"live": [rec]}))

    def test_non_cost_fields_keep_trimmed_formatting(self):
        html = report.render_html({"live": [self._rec(3.0, 3.0, wall_clock=10.0)]})
        self.assertIn(">10</td>", html)   # wall clock 10.0, not 10.00
        self.assertIn(">345</td>", html)  # LOC produced
        self.assertIn(">0</td>", html)    # coverage % 0.0


class CoverageAbsentVsZero(unittest.TestCase):
    """Item 3 (HTML side): a live record whose coverage is unmeasured (both arms None) drops
    the coverage row; a deterministic record with a measured 0.0 keeps it."""

    def _live_no_coverage(self):
        wt = Tokens(input=1000, output=500, total=1500, cache_read=300, cache_creation=100)
        with_pm = PathMetrics(wt, 0.2, 10.0, 400, 10, None, 0, 3, "pass",
                              "benchmark/workdirs/live-nc/with")
        without_pm = PathMetrics(Tokens(input=400, output=200, total=600), 0.1, 5.0, 300, 8,
                                 None, 0, 3, "pass", "benchmark/workdirs/live-nc/without")
        return make_record("live-nc", "2026-07-22T00:00:00Z", "live", "sha", None,
                           with_pm, without_pm).to_dict()

    def test_absent_coverage_row_omitted(self):
        html = report.render_html({"live": [self._live_no_coverage()]})
        self.assertNotIn("coverage %", html)

    def test_measured_zero_coverage_row_present(self):
        html = report.render_html({"deterministic": [_det_record()]})  # coverage_pct 0.0
        self.assertIn("coverage %", html)


class PerStageArmAttribution(unittest.TestCase):
    """Item 2 (HTML side): the per-stage token-share line tags each entry with its arm so the
    paired path no longer lists a bare stage name twice."""

    def test_token_share_labels_arm(self):
        from benchmarkkit.metrics import StageAttribution
        rec = _live_record_with_cache()
        rec["stages"] = [
            StageAttribution("DV", 900, 0, 0, 100, 0.1, arm="with").to_dict(),
            StageAttribution("DV", 100, 0, 0, 10, 0.1, arm="without").to_dict(),
        ]
        html = report.render_html({"live": [rec]})
        self.assertIn("DV (with)", html)
        self.assertIn("DV (without)", html)


if __name__ == "__main__":
    unittest.main()
