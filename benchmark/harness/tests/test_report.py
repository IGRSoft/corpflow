"""Report parity (port of ReportTests): metric labels, +4 delta, 581,886 grouping,
app_path fallback, empty/missing history safe, cache-hit% row + em-dash degrade,
build_report writes a file. HTML is substring-gated.
"""

import os
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

    def test_cache_hit_degrades_for_legacy_record(self):
        # Legacy live record (no cache keys) → cache-hit % row is an em-dash.
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
        cov = StageCoverage(agents=["igrsoft:developer"], skills=[], commands=[],
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


if __name__ == "__main__":
    unittest.main()
