"""Metrics schema parity (port of MetricsSchemaTests): top-level fields, tokens
shim (in/out/total, 5 keys always), deterministic null / live populated,
comparison shape, D1/D2 deltas, round-trips.
"""

import json
import unittest

from benchmarkkit.metrics import (
    BenchmarkRecord,
    MetricDelta,
    PathMetrics,
    StageAttribution,
    StageCoverage,
    Tokens,
    dumps,
    loads,
    make_record,
)


def _det_pm(**over):
    d = dict(
        tokens=Tokens(),
        cost_usd=None,
        wall_clock_s=0.03,
        loc_produced=345,
        test_count=20,
        coverage_pct=0.0,
        estimate_complexity_score=15,
        stage_count=5,
        pass_fail="pass",
        app_path="benchmark/workdirs/x/with",
    )
    d.update(over)
    return PathMetrics(**d)


def _live_pm(**over):
    d = dict(
        tokens=Tokens(input=574557, output=7329, total=581886),
        cost_usd=1.241815,
        wall_clock_s=92.191,
        loc_produced=391,
        test_count=0,
        coverage_pct=0.0,
        estimate_complexity_score=0,
        stage_count=3,
        pass_fail="pass",
        app_path=None,
    )
    d.update(over)
    return PathMetrics(**d)


class MetricsSchema(unittest.TestCase):
    def test_top_level_fields(self):
        rec = make_record("r", "2026-07-05T18:48:06Z", "deterministic", "sha", None,
                          _det_pm(), _det_pm(estimate_complexity_score=0, stage_count=1))
        d = rec.to_dict()
        for key in ("run_id", "timestamp_utc", "mode", "git_sha", "budget_usd", "paths", "comparison"):
            self.assertIn(key, d)
        self.assertNotIn("live_partial", d)  # omit-when-false
        self.assertNotIn("stages", d)        # omit-when-empty

    def test_path_required_keys(self):
        d = _det_pm().to_dict()
        for key in ("tokens", "cost_usd", "wall_clock_s", "loc_produced", "test_count",
                    "coverage_pct", "estimate_complexity_score", "stage_count", "pass_fail", "app_path"):
            self.assertIn(key, d)

    def test_tokens_shim_keys_and_always_five(self):
        d = Tokens(input=1, output=2, total=3).to_dict()
        self.assertEqual(list(d.keys()), ["in", "out", "total", "cache_read", "cache_creation"])
        self.assertNotIn("input", d)
        self.assertNotIn("output", d)

    def test_deterministic_tokens_and_cost_null(self):
        d = _det_pm().to_dict()
        self.assertIsNone(d["cost_usd"])
        self.assertIsNone(d["tokens"]["in"])
        self.assertIsNone(d["tokens"]["total"])

    def test_live_populated(self):
        d = _live_pm().to_dict()
        self.assertEqual(d["tokens"]["total"], 581886)
        self.assertEqual(d["cost_usd"], 1.241815)

    def test_comparison_shape_deterministic(self):
        rec = make_record("r", "t", "deterministic", "s", None,
                          _det_pm(), _det_pm(estimate_complexity_score=0, stage_count=1))
        comp = rec.to_dict()["comparison"]
        self.assertEqual(list(comp.keys()),
                         ["loc_produced", "test_count", "coverage_pct", "wall_clock_s",
                          "estimate_complexity_score", "stage_count"])
        for md in comp.values():
            self.assertEqual(set(md.keys()), {"with", "without", "delta"})
        self.assertEqual(comp["stage_count"]["delta"], 4)

    def test_comparison_live_adds_tokens_total_and_cost(self):
        rec = make_record("r", "t", "live", "s", None,
                          _live_pm(), _live_pm(tokens=Tokens(input=218476, output=5745, total=224221),
                                               cost_usd=0.561047))
        comp = rec.to_dict()["comparison"]
        self.assertIn("tokens_total", comp)
        self.assertIn("cost_usd", comp)
        self.assertEqual(comp["tokens_total"]["delta"], 581886 - 224221)

    def test_metric_delta_nil_propagation(self):
        md = MetricDelta.of(None, 5)
        self.assertIsNone(md.delta)
        self.assertEqual(md.without, 5)

    def test_stage_attribution_shape_and_coverage_after_cost(self):
        cov = StageCoverage(agents=["a"], skills=["s"], commands=["c"], tool_calls=3)
        sa = StageAttribution(stage="PL", fresh_in=10, cache_creation=1, cache_read=2,
                              out=3, cost_usd=0.5, coverage=cov)
        d = sa.to_dict()
        self.assertEqual(list(d.keys()),
                         ["stage", "fresh_in", "cache_creation", "cache_read", "out",
                          "cost_usd", "coverage"])  # coverage AFTER cost_usd
        # Without coverage → key omitted.
        d2 = StageAttribution(stage="PL", fresh_in=1, cache_creation=None, cache_read=None,
                              out=1, cost_usd=None).to_dict()
        self.assertNotIn("coverage", d2)

    def test_coverage_pct_none_survives_round_trip(self):
        # Absent coverage (live) must serialize as null and decode back to None, never 0.0.
        d = _live_pm(coverage_pct=None).to_dict()
        self.assertIsNone(d["coverage_pct"])
        self.assertIsNone(PathMetrics.from_dict(d).coverage_pct)

    def test_record_missing_coverage_key_decodes_none(self):
        # A record that omits coverage_pct decodes to None (not a fabricated 0.0), keeping
        # "absent" distinct from a measured zero for the renderer.
        d = _det_pm().to_dict()
        del d["coverage_pct"]
        self.assertIsNone(PathMetrics.from_dict(d).coverage_pct)

    def test_paired_live_comparison_coverage_is_null(self):
        rec = make_record("r", "t", "live", "s", None,
                          _live_pm(coverage_pct=None), _live_pm(coverage_pct=None))
        cov = rec.to_dict()["comparison"]["coverage_pct"]
        self.assertEqual(cov, {"with": None, "without": None, "delta": None})

    def test_round_trips(self):
        rec = make_record("r", "2026-07-05T18:48:06Z", "live", "sha", 5.0,
                          _live_pm(), _live_pm(), live_partial=True,
                          stages=[StageAttribution("PL", 1, 2, 3, 4, 0.1)])
        text = dumps(rec)
        back = loads(text)
        self.assertEqual(dumps(back), text)  # stable round-trip
        d = json.loads(text)
        self.assertTrue(d["live_partial"])
        self.assertEqual(len(d["stages"]), 1)


if __name__ == "__main__":
    unittest.main()
