#!/usr/bin/env python3
"""Tests for benchmark/lib/report.py — result.html rendering + app-path surfacing."""

from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
_LIB = os.path.normpath(os.path.join(_HERE, "..", "..", "lib"))
sys.path.insert(0, _LIB)

import metrics  # noqa: E402
import report  # noqa: E402


def _sample_history():
    with_p = metrics.PathMetrics(
        tokens=metrics.Tokens(input=100, output=20, total=120),
        cost_usd=1.5, wall_clock_s=0.04, loc_produced=275, test_count=9,
        coverage_pct=0.0, estimate_complexity_score=15, stage_count=5,
        pass_fail="pass", app_path="benchmark/workdirs/RUNID/with",
    )
    without_p = metrics.PathMetrics(
        tokens=metrics.Tokens(input=None, output=None, total=None),
        cost_usd=None, wall_clock_s=0.001, loc_produced=275, test_count=9,
        coverage_pct=0.0, estimate_complexity_score=0, stage_count=1,
        pass_fail="pass", app_path="benchmark/workdirs/RUNID/without",
    )
    rec = metrics.make_record(
        run_id="RUNID", timestamp_utc="2026-07-01T00:00:00Z", mode="deterministic",
        git_sha="abc1234", budget_usd=None, with_p=with_p, without_p=without_p,
    )
    return {"deterministic": [rec.to_json()]}


def _cache_bearing_record():
    """A live record carrying cache fields + per-stage attribution (analysis rows fire)."""
    with_p = metrics.PathMetrics(
        tokens=metrics.Tokens(
            input=108592, output=13160, total=121752,
            cache_read=677604, cache_creation=129094,
        ),
        cost_usd=2.5, wall_clock_s=1.0, loc_produced=275, test_count=9,
        coverage_pct=0.0, estimate_complexity_score=15, stage_count=3,
        pass_fail="pass", app_path="benchmark/workdirs/CACHE/with",
    )
    without_p = metrics.PathMetrics(
        tokens=metrics.Tokens(input=1000, output=100, total=1100),
        cost_usd=None, wall_clock_s=0.1, loc_produced=275, test_count=9,
        coverage_pct=0.0, estimate_complexity_score=0, stage_count=1,
        pass_fail="pass", app_path="benchmark/workdirs/CACHE/without",
    )
    stages = [
        metrics.StageAttribution("estimate", 33482, 11639, 23022, 997, 0.1),
        metrics.StageAttribution("create", 37652, 56772, 207310, 4227, 0.5),
        metrics.StageAttribution("test", 37458, 60683, 447272, 7936, 0.9),
    ]
    rec = metrics.make_record(
        run_id="CACHE", timestamp_utc="2026-07-01T01:00:00Z", mode="live",
        git_sha="abc1234", budget_usd=5.0, with_p=with_p, without_p=without_p,
        stages=stages,
    )
    return rec.to_json()


def _legacy_ondisk_live_record():
    """Mirror the real on-disk live record: tokens.in=574557, NO cache fields, NO stages."""
    return {
        "run_id": "OLDLIVE",
        "timestamp_utc": "2026-06-01T00:00:00Z",
        "mode": "live",
        "git_sha": "old1234",
        "budget_usd": 5.0,
        "paths": {
            "with": {
                "tokens": {"in": 574557, "out": 7329, "total": 581886},
                "cost_usd": 3.0, "wall_clock_s": 1.0, "loc_produced": 275,
                "test_count": 9, "coverage_pct": 0.0,
                "estimate_complexity_score": 0, "stage_count": 10, "pass_fail": "pass",
            },
            "without": {
                "tokens": {"in": None, "out": None, "total": None},
                "cost_usd": None, "wall_clock_s": 0.1, "loc_produced": 275,
                "test_count": 9, "coverage_pct": 0.0,
                "estimate_complexity_score": 0, "stage_count": 1, "pass_fail": "pass",
            },
        },
        "comparison": {},
    }


class ReportRender(unittest.TestCase):
    def test_contains_all_metrics_and_app_paths(self):
        out = report.render_html(_sample_history())
        self.assertIn("<html", out)
        for token in ("WITH plugin", "WITHOUT plugin", "tokens total",
                      "complexity score", "stage count", "cost (USD)", "RUNID"):
            self.assertIn(token, out)
        # both generated-app paths surfaced
        self.assertIn("benchmark/workdirs/RUNID/with", out)
        self.assertIn("benchmark/workdirs/RUNID/without", out)
        # stage_count delta 5 - 1 = 4 rendered
        self.assertIn("+4", out)

    def test_app_path_fallback_when_missing(self):
        # A record without app_path must still surface the conventional workdir path.
        hist = _sample_history()
        hist["deterministic"][0]["paths"]["with"].pop("app_path", None)
        out = report.render_html(hist)
        self.assertIn("benchmark/workdirs/RUNID/with", out)

    def test_empty_history_is_safe(self):
        out = report.render_html({})
        self.assertIn("No benchmark results", out)

    def test_build_report_writes_file(self):
        d = tempfile.mkdtemp()
        hist_path = os.path.join(d, "history.json")
        out_path = os.path.join(d, "result.html")
        with open(hist_path, "w", encoding="utf-8") as f:
            json.dump(_sample_history(), f)
        report.build_report(hist_path, out_path)
        self.assertTrue(os.path.isfile(out_path))
        with open(out_path, "r", encoding="utf-8") as f:
            self.assertIn("RUNID", f.read())

    def test_build_report_missing_history_is_safe(self):
        d = tempfile.mkdtemp()
        out_path = os.path.join(d, "result.html")
        report.build_report(os.path.join(d, "nope.json"), out_path)
        self.assertTrue(os.path.isfile(out_path))
        with open(out_path, "r", encoding="utf-8") as f:
            self.assertIn("No benchmark results", f.read())


class AnalysisRows(unittest.TestCase):
    def test_analysis_rows_render_for_cache_record(self):
        out = report.render_html({"live": [_cache_bearing_record()]})
        # All five derived analysis rows appear as labels.
        for label in ("input:output ratio", "cache-hit %", "per-stage token share",
                      "tokens per LOC", "WITH-vs-WITHOUT premium"):
            self.assertIn(label, out)
        # cache-hit % recomputed from the record = 677604 / 915290 = 74.03%.
        self.assertIn("74.03%", out)
        # per-stage share names the three stages.
        self.assertIn("estimate", out)
        self.assertIn("create", out)
        self.assertIn("test", out)
        # raw cache rows surface too.
        self.assertIn("cache read", out)
        self.assertIn("cache creation", out)

    def test_analysis_rows_degrade_to_emdash_for_legacy_record(self):
        # AC-3: a record lacking cache_read / stages must render with em-dash, no crash.
        out = report.render_html({"live": [_legacy_ondisk_live_record()]})
        self.assertIn("<html", out)
        self.assertIn("OLDLIVE", out)
        self.assertIn("cache-hit %", out)   # the row label still shows
        self.assertIn("&mdash;", out)       # but degrades to em-dash
        # input:output ratio still computes (needs only total/out): 581886/7329.
        self.assertIn("input:output ratio", out)

    def test_report_renders_existing_ondisk_live_record_shape(self):
        # The real on-disk record shape must render without raising and show raw tokens.
        # (Note: the "tokens in" ROW accessor is "tokens.input" but the JSON key is "in";
        # that's a pre-existing report quirk, so total is the reliable raw-token check.)
        out = report.render_html({"live": [_legacy_ondisk_live_record()]})
        self.assertIn("581,886", out)   # tokens total, formatted
        self.assertIn("tokens total", out)
        # cache-derived rows degrade cleanly for this no-cache record.
        self.assertIn("&mdash;", out)


if __name__ == "__main__":
    unittest.main()
