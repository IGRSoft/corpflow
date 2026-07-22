"""Re-homed PluginScriptsTests/EstimateCalcTests behaviors (21) against the
UNCHANGED estimate-calc.py — in-process for the real arithmetic/fallback contracts
plus CLI smoke for the argparse guards.

# @test-required
# @test-tag: smoke
# @depends-on: ai_cost
# @depends-on: complexity_band
"""

import json
import unittest

from _scriptimport import ESTIMATE_CALC, load_module, run_cli

est = load_module(ESTIMATE_CALC, "estimate_calc")


class ComplexityBandBoundaries(unittest.TestCase):
    def test_sum10_is_low(self):
        self.assertEqual(est.complexity_band([2, 2, 2, 2, 2]), (10, "LOW"))

    def test_sum15_is_medium(self):
        self.assertEqual(est.complexity_band([3, 3, 3, 3, 3]), (15, "MEDIUM"))

    def test_sum20_is_high(self):
        self.assertEqual(est.complexity_band([4, 4, 4, 4, 4]), (20, "HIGH"))

    def test_sum25_clamps_high(self):
        self.assertEqual(est.complexity_band([5, 5, 5, 5, 5]), (25, "HIGH"))

    def test_band_edges_11_17_18(self):
        self.assertEqual(est.complexity_band([2, 2, 2, 2, 3]), (11, "MEDIUM"))
        self.assertEqual(est.complexity_band([3, 4, 3, 4, 3]), (17, "MEDIUM"))
        self.assertEqual(est.complexity_band([4, 4, 4, 3, 3]), (18, "HIGH"))

    def test_below_range_clamps_low(self):
        self.assertEqual(est.complexity_band([0, 0, 0, 0, 0]), (0, "LOW"))


class AiCostArithmetic(unittest.TestCase):
    def test_sonnet_100k_medium_standard(self):
        # 100000/1e6 * 3.0 * (1+0.2) * 1.0 = 0.36
        self.assertAlmostEqual(est.ai_cost(100_000, "sonnet", "medium", "standard"), 0.36, places=6)

    def test_haiku_50k_high_novel(self):
        # 50000/1e6 * 0.25 * (1+0.5) * 2.0 = 0.0375
        self.assertAlmostEqual(est.ai_cost(50_000, "haiku", "high", "novel"), 0.0375, places=6)

    def test_unknown_model_falls_back_to_sonnet_rate(self):
        # The true in-process contract the Swift subprocess port could not reach:
        # ai_cost uses MODEL_RATES_PER_M.get(model, sonnet).
        self.assertEqual(
            est.ai_cost(100_000, "nonexistent"),
            est.ai_cost(100_000, "sonnet"),
        )

    def test_unknown_model_rejected_at_cli(self):
        # Argparse-guard smoke: the CLI layer rejects unknown models (rc=2), the
        # complementary protection to the in-process fallback.
        r = run_cli(ESTIMATE_CALC, ["--tokens", "100000", "--model", "nonexistent"])
        self.assertEqual(r.returncode, 2)
        self.assertIn("--model", r.stderr)


class HoursArithmetic(unittest.TestCase):
    def test_m_senior_base_hours(self):
        self.assertEqual(est.hours_range(4, 5, est.MULTIPLIERS["senior"]), (24.0, 30.0))

    def test_m_senior_buffered_total(self):
        b_min, b_max = est.buffered_hours(24.0, 30.0)
        self.assertEqual(round(b_min, 2), 27.6)
        self.assertEqual(round(b_max, 2), 34.5)

    def test_tshirt_m_lookup(self):
        self.assertEqual(est.TSHIRT_SP["M"], (4, 5))

    def test_budget_arithmetic(self):
        self.assertEqual(est.budget(27.6, 34.5, 150.0), (4140.0, 5175.0))


class RunAndCliShape(unittest.TestCase):
    def test_run_end_to_end_shape(self):
        ns = est._build_parser().parse_args([
            "--size", "M", "--level", "senior", "--rate", "150",
            "--tokens", "100000", "--model", "sonnet",
            "--retry-complexity", "medium", "--codebase-type", "standard",
            "--factors", "3", "3", "3", "3", "3",
        ])
        out = est._run(ns)
        self.assertEqual(out["total_hours"]["min"], 27.6)
        self.assertEqual(out["total_hours"]["max"], 34.5)
        self.assertAlmostEqual(out["ai_cost"]["usd"], 0.36, places=6)
        self.assertEqual(out["complexity"]["total"], 15)
        self.assertEqual(out["complexity"]["band"], "MEDIUM")

    def test_run_size_level_only(self):
        ns = est._build_parser().parse_args(["--size", "L", "--level", "mid"])
        out = est._run(ns)
        self.assertIn("sp", out)
        self.assertIn("total_hours", out)


class CliSmoke(unittest.TestCase):
    def test_self_test_exit_zero(self):
        r = run_cli(ESTIMATE_CALC, ["--self-test"])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(json.loads(r.stdout)["self_test"], "ok")

    def test_no_args_exits_1(self):
        r = run_cli(ESTIMATE_CALC, [])
        self.assertEqual(r.returncode, 1)

    def test_cli_size_level_total_hours(self):
        r = run_cli(ESTIMATE_CALC, ["--size", "M", "--level", "senior", "--rate", "150"])
        self.assertEqual(r.returncode, 0, r.stderr)
        total = json.loads(r.stdout)["total_hours"]
        self.assertEqual(total["min"], 27.6)
        self.assertEqual(total["max"], 34.5)

    def test_cli_factors_band(self):
        r = run_cli(ESTIMATE_CALC, ["--factors", "3", "3", "2", "2", "3"])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(json.loads(r.stdout)["complexity"]["band"], "MEDIUM")

    def test_cli_tokens_ai_cost(self):
        r = run_cli(ESTIMATE_CALC, [
            "--tokens", "100000", "--model", "sonnet",
            "--retry-complexity", "medium", "--codebase-type", "standard",
        ])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertAlmostEqual(json.loads(r.stdout)["ai_cost"]["usd"], 0.36, places=6)


if __name__ == "__main__":
    unittest.main()
