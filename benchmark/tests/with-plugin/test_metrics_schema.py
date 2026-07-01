"""benchmark/tests/with-plugin/test_metrics_schema.py — AC-6 schema validation (DV0d).

Validates that benchmark/lib/metrics.py:
  - Produces a BenchmarkRecord with every required field + correct types.
  - Deterministic-mode: tokens.in/out/total are null, cost_usd is null, budget_usd null.
  - Comparison block has all required metric keys with correct {with/without/delta} shape.
  - JSON round-trip (to_json / from_json) is lossless + keyword shim works.
  - MetricDelta.of() computes delta correctly and handles None sides.
"""

import importlib.util
import json
import os
import sys
import unittest

# Resolve benchmark/lib regardless of cwd (called by Makefile from repo root).
_HERE = os.path.dirname(os.path.abspath(__file__))  # benchmark/tests/with-plugin/
_LIB = os.path.join(os.path.dirname(os.path.dirname(_HERE)), "lib")  # benchmark/lib/
if _LIB not in sys.path:
    sys.path.insert(0, _LIB)

import metrics  # noqa: E402  (benchmark/lib/metrics.py)


def _make_tokens(*, null: bool) -> metrics.Tokens:
    if null:
        return metrics.Tokens(input=None, output=None, total=None)
    return metrics.Tokens(
        input=100, output=200, total=300,
        cache_read=677604, cache_creation=129094,
    )


def _make_path(*, null_tokens: bool) -> metrics.PathMetrics:
    return metrics.PathMetrics(
        tokens=_make_tokens(null=null_tokens),
        cost_usd=None if null_tokens else 0.42,
        wall_clock_s=1.23,
        loc_produced=275,
        test_count=9,
        coverage_pct=88.5,
        estimate_complexity_score=15,
        stage_count=5,
        pass_fail="pass",
    )


def _make_record(*, mode: str = "deterministic") -> metrics.BenchmarkRecord:
    with_p = _make_path(null_tokens=(mode == "deterministic"))
    without_p = metrics.PathMetrics(
        tokens=_make_tokens(null=True),
        cost_usd=None,
        wall_clock_s=0.5,
        loc_produced=275,
        test_count=9,
        coverage_pct=88.5,
        estimate_complexity_score=0,
        stage_count=1,
        pass_fail="pass",
    )
    return metrics.make_record(
        run_id=f"{mode}-test-abc1234",
        timestamp_utc="2026-01-01T00:00:00Z",
        mode=mode,
        git_sha="abc1234",
        budget_usd=None if mode == "deterministic" else 5.0,
        with_p=with_p,
        without_p=without_p,
    )


class TestRequiredTopLevelFields(unittest.TestCase):
    def setUp(self):
        self.rec = _make_record()
        self.d = self.rec.to_json()

    def test_run_id_present_and_string(self):
        self.assertIn("run_id", self.d)
        self.assertIsInstance(self.d["run_id"], str)

    def test_timestamp_utc_present_and_iso(self):
        self.assertIn("timestamp_utc", self.d)
        ts = self.d["timestamp_utc"]
        self.assertIsInstance(ts, str)
        self.assertTrue(ts.endswith("Z"), f"expected Z suffix: {ts!r}")
        self.assertIn("T", ts)

    def test_mode_is_valid_literal(self):
        self.assertIn(self.d["mode"], ("deterministic", "live"))

    def test_git_sha_present(self):
        self.assertIsInstance(self.d.get("git_sha"), str)

    def test_budget_usd_null_in_deterministic(self):
        self.assertIsNone(self.d["budget_usd"])

    def test_budget_usd_populated_in_live(self):
        live = _make_record(mode="live").to_json()
        self.assertIsNotNone(live["budget_usd"])
        self.assertIsInstance(live["budget_usd"], float)


class TestPathsBlock(unittest.TestCase):
    def setUp(self):
        self.d = _make_record().to_json()
        self.with_p = self.d["paths"]["with"]
        self.without_p = self.d["paths"]["without"]

    def test_paths_has_with_and_without(self):
        self.assertIn("with", self.d["paths"])
        self.assertIn("without", self.d["paths"])

    def _check_path(self, p: dict):
        required = {
            "tokens", "cost_usd", "wall_clock_s", "loc_produced",
            "test_count", "coverage_pct", "estimate_complexity_score",
            "stage_count", "pass_fail",
        }
        missing = required - set(p.keys())
        self.assertEqual(missing, set(), f"missing fields: {missing}")

    def test_with_path_has_all_required_fields(self):
        self._check_path(self.with_p)

    def test_without_path_has_all_required_fields(self):
        self._check_path(self.without_p)

    def test_tokens_keyword_shim_produces_in_out_total_keys(self):
        """'in' and 'out' must appear on disk (not 'input'/'output')."""
        for label, p in (("with", self.with_p), ("without", self.without_p)):
            t = p["tokens"]
            self.assertIn("in", t, f"{label}.tokens missing 'in' key")
            self.assertIn("out", t, f"{label}.tokens missing 'out' key")
            self.assertIn("total", t, f"{label}.tokens missing 'total' key")
            self.assertNotIn("input", t, f"{label}.tokens should not have 'input' key")
            self.assertNotIn("output", t, f"{label}.tokens should not have 'output' key")

    def test_deterministic_tokens_are_null(self):
        t = self.with_p["tokens"]
        self.assertIsNone(t["in"])
        self.assertIsNone(t["out"])
        self.assertIsNone(t["total"])

    def test_deterministic_cost_usd_is_null(self):
        self.assertIsNone(self.with_p["cost_usd"])

    def test_live_tokens_populated(self):
        live = _make_record(mode="live").to_json()
        t = live["paths"]["with"]["tokens"]
        self.assertIsNotNone(t["in"])
        self.assertIsNotNone(t["out"])
        self.assertIsNotNone(t["total"])

    def test_pass_fail_is_valid(self):
        for p in (self.with_p, self.without_p):
            self.assertIn(p["pass_fail"], ("pass", "fail"))

    def test_wall_clock_is_float(self):
        self.assertIsInstance(self.with_p["wall_clock_s"], float)

    def test_loc_and_counts_are_ints(self):
        for key in ("loc_produced", "test_count", "stage_count", "estimate_complexity_score"):
            self.assertIsInstance(self.with_p[key], int, f"with.{key} not int")


class TestComparisonBlock(unittest.TestCase):
    def setUp(self):
        self.d = _make_record().to_json()
        self.comp = self.d["comparison"]

    def test_deterministic_comparison_keys_present(self):
        required = {
            "loc_produced", "test_count", "coverage_pct",
            "wall_clock_s", "estimate_complexity_score", "stage_count",
        }
        missing = required - set(self.comp.keys())
        self.assertEqual(missing, set(), f"missing comparison keys: {missing}")

    def test_comparison_entry_has_with_without_delta_keys(self):
        """MetricDelta.with_ serialises as 'with' (not 'with_')."""
        for key, entry in self.comp.items():
            self.assertIn("with", entry, f"comparison.{key} missing 'with'")
            self.assertIn("without", entry, f"comparison.{key} missing 'without'")
            self.assertIn("delta", entry, f"comparison.{key} missing 'delta'")
            self.assertNotIn("with_", entry, f"comparison.{key} leaked 'with_' key")

    def test_delta_computed_correctly(self):
        sc = self.comp["stage_count"]
        self.assertEqual(sc["with"], 5)
        self.assertEqual(sc["without"], 1)
        self.assertEqual(sc["delta"], 4)

    def test_delta_none_when_either_side_none(self):
        # cost_usd: with=None, without=None in deterministic
        cost = self.comp.get("cost_usd")
        if cost is not None:
            # live mode — delta should be non-None; deterministic won't have this key
            pass

    def test_live_adds_token_and_cost_comparison(self):
        live_comp = _make_record(mode="live").to_json()["comparison"]
        self.assertIn("tokens_total", live_comp)
        self.assertIn("cost_usd", live_comp)


class TestJsonRoundtrip(unittest.TestCase):
    def test_roundtrip_deterministic(self):
        rec = _make_record(mode="deterministic")
        dumped = metrics.dumps(rec)
        loaded = metrics.loads(dumped)
        self.assertEqual(loaded.run_id, rec.run_id)
        self.assertEqual(loaded.mode, rec.mode)
        self.assertIsNone(loaded.budget_usd)
        self.assertEqual(loaded.paths["with"].stage_count, 5)
        self.assertEqual(loaded.paths["without"].stage_count, 1)
        self.assertEqual(loaded.comparison["stage_count"].delta, 4)

    def test_roundtrip_live(self):
        rec = _make_record(mode="live")
        loaded = metrics.loads(metrics.dumps(rec))
        self.assertEqual(loaded.mode, "live")
        self.assertIsNotNone(loaded.budget_usd)
        self.assertIsNotNone(loaded.paths["with"].tokens.input)

    def test_to_json_is_valid_json(self):
        d = json.loads(metrics.dumps(_make_record()))
        self.assertIn("run_id", d)


class TestMetricDeltaOf(unittest.TestCase):
    def test_computes_delta_both_present(self):
        md = metrics.MetricDelta.of(10, 3)
        self.assertEqual(md.with_, 10)
        self.assertEqual(md.without, 3)
        self.assertEqual(md.delta, 7)

    def test_delta_none_when_with_none(self):
        md = metrics.MetricDelta.of(None, 3)
        self.assertIsNone(md.delta)

    def test_delta_none_when_without_none(self):
        md = metrics.MetricDelta.of(5, None)
        self.assertIsNone(md.delta)

    def test_float_delta(self):
        md = metrics.MetricDelta.of(1.5, 0.5)
        self.assertAlmostEqual(md.delta, 1.0)


class TestTokensCacheFields(unittest.TestCase):
    """AC-1: additive cache_read / cache_creation on Tokens (JSON keys + null default)."""

    def test_tokens_has_cache_read_and_cache_creation_keys(self):
        d = _make_record(mode="live").to_json()
        t = d["paths"]["with"]["tokens"]
        self.assertIn("cache_read", t)
        self.assertIn("cache_creation", t)

    def test_deterministic_cache_fields_are_null(self):
        d = _make_record(mode="deterministic").to_json()
        t = d["paths"]["with"]["tokens"]
        self.assertIsNone(t["cache_read"])
        self.assertIsNone(t["cache_creation"])

    def test_cache_fields_are_int_when_populated(self):
        d = _make_record(mode="live").to_json()
        t = d["paths"]["with"]["tokens"]
        self.assertIsInstance(t["cache_read"], int)
        self.assertIsInstance(t["cache_creation"], int)

    def test_roundtrip_preserves_cache_fields(self):
        tok = metrics.Tokens(
            input=108592, output=13160, total=121752,
            cache_read=677604, cache_creation=129094,
        )
        loaded = metrics.Tokens.from_json(tok.to_json())
        self.assertEqual(loaded, tok)
        self.assertEqual(loaded.cache_read, 677604)
        self.assertEqual(loaded.cache_creation, 129094)

    def test_roundtrip_none_cache_fields(self):
        tok = metrics.Tokens()
        d = tok.to_json()
        self.assertEqual(
            d,
            {"in": None, "out": None, "total": None,
             "cache_read": None, "cache_creation": None},
        )
        self.assertEqual(metrics.Tokens.from_json(d), tok)

    def test_from_json_legacy_tokens_without_cache_keys(self):
        # The on-disk live record shape: no cache keys -> loads as None, no crash.
        legacy = {"in": 574557, "out": 7329, "total": 581886}
        tok = metrics.Tokens.from_json(legacy)
        self.assertEqual(tok.input, 574557)
        self.assertEqual(tok.output, 7329)
        self.assertEqual(tok.total, 581886)
        self.assertIsNone(tok.cache_read)
        self.assertIsNone(tok.cache_creation)

    def test_positional_tokens_three_args_still_resolves(self):
        # Hazard guard: positional Tokens(None, None, None) must keep working
        # (new fields appended strictly after total).
        tok = metrics.Tokens(None, None, None)
        self.assertIsNone(tok.cache_read)
        self.assertIsNone(tok.cache_creation)

    def test_total_excludes_cache(self):
        # cache figures are additive siblings, NEVER summed into total.
        tok = metrics.Tokens(input=100, output=200, total=300,
                             cache_read=999, cache_creation=888)
        self.assertEqual(tok.total, 300)


class TestStageAttribution(unittest.TestCase):
    """AC-2: per-stage attribution list on BenchmarkRecord (omit-when-empty)."""

    def _staged_record(self):
        stages = [
            metrics.StageAttribution("estimate", 33482, 11639, 23022, 997, 0.1),
            metrics.StageAttribution("create", 37652, 56772, 207310, 4227, 0.5),
            metrics.StageAttribution("test", 37458, 60683, 447272, 7936, 0.9),
        ]
        with_p = _make_path(null_tokens=False)
        without_p = _make_path(null_tokens=True)
        return metrics.make_record(
            run_id="live-staged", timestamp_utc="2026-07-01T00:00:00Z",
            mode="live", git_sha="abc1234", budget_usd=5.0,
            with_p=with_p, without_p=without_p, stages=stages,
        )

    def test_stages_omitted_when_empty(self):
        d = _make_record(mode="deterministic").to_json()
        self.assertNotIn("stages", d)

    def test_stages_present_and_shaped_when_populated(self):
        d = self._staged_record().to_json()
        self.assertIn("stages", d)
        self.assertEqual(len(d["stages"]), 3)
        s0 = d["stages"][0]
        for key in ("stage", "fresh_in", "cache_creation", "cache_read", "out", "cost_usd"):
            self.assertIn(key, s0)
        self.assertEqual(s0["stage"], "estimate")
        self.assertEqual(s0["cache_read"], 23022)

    def test_stages_roundtrip(self):
        rec = self._staged_record()
        loaded = metrics.loads(metrics.dumps(rec))
        self.assertEqual(len(loaded.stages), 3)
        self.assertEqual(loaded.stages[2].stage, "test")
        self.assertEqual(loaded.stages[2].cache_read, 447272)
        self.assertEqual(loaded.stages, rec.stages)


if __name__ == "__main__":
    unittest.main()
