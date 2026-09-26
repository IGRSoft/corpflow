"""estimate-calc.py behaviors: in-process for the arithmetic/fallback contracts,
CLI smoke for the argparse guards, and a parity check of its rate copy against
the table that owns the rates (model-selection.md § Cost Tiers).

# @test-required
# @test-tag: smoke
# @depends-on: ai_cost
# @depends-on: complexity_band
"""

import json
import os
import re
import unittest

from _scriptimport import ESTIMATE_CALC, REPO_ROOT, load_module, run_cli

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
        # 80k in / 20k out: (0.08*2 + 0.02*10) * (1+0.2) * 1.0 = 0.432
        self.assertAlmostEqual(est.ai_cost(100_000, "sonnet", "medium", "standard"), 0.432, places=6)

    def test_haiku_50k_high_novel(self):
        # 40k in / 10k out: (0.04*1 + 0.01*5) * (1+0.5) * 2.0 = 0.27
        self.assertAlmostEqual(est.ai_cost(50_000, "haiku", "high", "novel"), 0.27, places=6)

    def test_opus_prices_at_opus_5_5(self):
        # 80k in / 20k out: (0.08*4 + 0.02*20) * 1.2 = 0.864
        self.assertAlmostEqual(est.ai_cost(100_000, "opus"), 0.864, places=6)

    def test_fable_is_priced(self):
        # (0.08*10 + 0.02*50) * 1.2 = 2.16
        self.assertAlmostEqual(est.ai_cost(100_000, "fable"), 2.16, places=6)

    def test_supplied_split_replaces_default(self):
        # (0.09*2 + 0.01*10) * 1.1 = 0.308
        self.assertAlmostEqual(
            est.ai_cost(None, "sonnet", "low", "standard",
                        input_tokens=90_000, output_tokens=10_000),
            0.308, places=6)

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


class TokenSplit(unittest.TestCase):
    def test_total_only_uses_default_share(self):
        self.assertEqual(est.split_tokens(100_000), (80_000, 20_000, False))

    def test_both_sides_are_supplied(self):
        self.assertEqual(est.split_tokens(None, 7, 3), (7, 3, True))

    def test_total_and_one_side_derives_the_other(self):
        self.assertEqual(est.split_tokens(100_000, None, 5_000), (95_000, 5_000, False))

    def test_one_side_alone_uses_default_share(self):
        self.assertEqual(est.split_tokens(None, None, 20_000), (80_000, 20_000, False))

    def test_contradicting_total_rejected(self):
        with self.assertRaises(ValueError):
            est.split_tokens(100, 60, 50)

    def test_negative_rejected(self):
        with self.assertRaises(ValueError):
            est.split_tokens(-1)


def _section(path, heading):
    with open(os.path.join(REPO_ROOT, path), encoding="utf-8") as fh:
        text = fh.read()
    start = text.index(heading)
    nxt = text.find("\n#", start + len(heading))
    return text[start:] if nxt == -1 else text[start:nxt]


class RatesMatchDocumentedTable(unittest.TestCase):
    """The script's rate copy and default split must equal the documented owners."""

    def test_rates_match_model_selection_cost_tiers(self):
        body = _section("skills/shared/model-selection.md", "## Cost Tiers")
        documented = {}
        for m in re.finditer(r"^\| \*\*(\w+)\*\* \| [^|]+\| ([\d.]+) \| ([\d.]+) \|",
                             body, re.MULTILINE):
            documented[m.group(1)] = {"input": float(m.group(2)),
                                      "output": float(m.group(3))}
        self.assertTrue(documented, "no rate rows parsed from § Cost Tiers")
        self.assertEqual(documented, est.MODEL_RATES_PER_M)

    def test_default_split_matches_cost_formula(self):
        body = _section("skills/cost-optimization/SKILL.md", "### Cost Estimation Formula")
        m = re.search(r"(\d+):(\d+) input:output", body)
        self.assertIsNotNone(m, "no input:output split stated in § Cost Estimation Formula")
        share = int(m.group(1)) / (int(m.group(1)) + int(m.group(2)))
        self.assertAlmostEqual(share, est.DEFAULT_INPUT_SHARE, places=9)


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
        self.assertAlmostEqual(out["ai_cost"]["usd"], 0.432, places=6)
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

    def test_self_test_reports_checks_it_ran(self):
        r = run_cli(ESTIMATE_CALC, ["--self-test"])
        with open(ESTIMATE_CALC, encoding="utf-8") as fh:
            calls = fh.read().count('    check("')
        self.assertEqual(json.loads(r.stdout)["checks"], calls)

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
        ai = json.loads(r.stdout)["ai_cost"]
        self.assertAlmostEqual(ai["usd"], 0.432, places=6)
        # The fields callers read before the input/output split existed are all kept.
        for key in ("base_tokens", "model", "retry_complexity", "codebase_type", "usd"):
            self.assertIn(key, ai)
        self.assertEqual(ai["base_tokens"], 100000)
        self.assertEqual((ai["input_tokens"], ai["output_tokens"], ai["split"]),
                         (80000, 20000, "default"))
        self.assertEqual(ai["rates_per_m"], {"input": 2.0, "output": 10.0})

    def test_cli_input_output_tokens(self):
        r = run_cli(ESTIMATE_CALC, [
            "--input-tokens", "90000", "--output-tokens", "10000", "--model", "sonnet",
            "--retry-complexity", "low",
        ])
        self.assertEqual(r.returncode, 0, r.stderr)
        ai = json.loads(r.stdout)["ai_cost"]
        self.assertAlmostEqual(ai["usd"], 0.308, places=6)
        self.assertEqual((ai["base_tokens"], ai["split"]), (100000, "supplied"))

    def test_cli_contradicting_counts_exit_2(self):
        r = run_cli(ESTIMATE_CALC, [
            "--tokens", "100", "--input-tokens", "60", "--output-tokens", "50",
        ])
        self.assertEqual(r.returncode, 2)
        self.assertIn("tokens", r.stderr)


if __name__ == "__main__":
    unittest.main()
