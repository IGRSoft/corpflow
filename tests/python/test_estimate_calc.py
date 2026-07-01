#!/usr/bin/env python3
"""Unit tests for skills/estimation-methodology/scripts/estimate-calc.py (DV0c).

Imports the module under test by file path via importlib (no install step) and
asserts the REAL documented arithmetic contracts (AC-4 priority target):
  - complexity_band exact boundaries: 10->LOW, 11->MEDIUM, 17->MEDIUM, 18->HIGH,
    out-of-range 25->HIGH (clamp), and the mandate's named inputs summing to
    10/15/20/25.
  - ai_cost: 100k tokens, sonnet, medium retry, standard codebase -> $0.36.
  - buffered_hours: M(senior) base 24/30 -> 27.6 / 34.5 total hours.
  - CLI: json.loads(stdout) shape assertion + --self-test exit path.
"""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import unittest
from pathlib import Path

# ---------------------------------------------------------------------------
# Locate the module under test relative to PLUGIN_ROOT (tests/python/ -> ../../)
# ---------------------------------------------------------------------------
PLUGIN_ROOT = Path(__file__).resolve().parents[2]
TARGET = PLUGIN_ROOT / "skills" / "estimation-methodology" / "scripts" / "estimate-calc.py"


def _load_module():
    name = "estimate_calc_under_test"
    spec = importlib.util.spec_from_file_location(name, TARGET)
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


EC = _load_module()


class ComplexityBandBoundaries(unittest.TestCase):
    """AC-4: exact numeric band boundaries (sum of 5 factors, each 1-5)."""

    def test_sum_10_is_low(self):
        # Mandate: complexity band inputs summing to 10 -> "LOW".
        self.assertEqual(EC.complexity_band([2, 2, 2, 2, 2]), (10, "LOW"))

    def test_sum_15_is_medium(self):
        # Mandate: summing to 15 -> "MEDIUM" (15 lies in the 11-17 band).
        self.assertEqual(EC.complexity_band([3, 3, 3, 3, 3]), (15, "MEDIUM"))

    def test_sum_20_is_high(self):
        # Mandate: summing to 20 -> "HIGH" (20 lies in the 18-25 band).
        self.assertEqual(EC.complexity_band([4, 4, 4, 4, 4]), (20, "HIGH"))

    def test_sum_25_clamps_high(self):
        # Mandate: summing to 25 -> "HIGH" (top of the defined range; clamp).
        self.assertEqual(EC.complexity_band([5, 5, 5, 5, 5]), (25, "HIGH"))

    def test_band_edges_11_and_17_and_18(self):
        # The exact MEDIUM/HIGH inflection points documented in the source.
        self.assertEqual(EC.complexity_band([2, 2, 2, 2, 3]), (11, "MEDIUM"))
        self.assertEqual(EC.complexity_band([3, 4, 3, 4, 3]), (17, "MEDIUM"))
        self.assertEqual(EC.complexity_band([4, 4, 4, 3, 3]), (18, "HIGH"))

    def test_below_range_clamps_low(self):
        # A negative/0 total cannot match a band; clamp to the lowest (LOW).
        total, band = EC.complexity_band([0, 0, 0, 0, 0])
        self.assertEqual((total, band), (0, "LOW"))


class AiCostArithmetic(unittest.TestCase):
    """AC-4: 100k-token sonnet medium/standard -> 0.36."""

    def test_sonnet_100k_medium_standard(self):
        # 100000/1e6 * 3.0 * (1+0.2) * 1.0 = 0.1 * 3.0 * 1.2 = 0.36
        self.assertEqual(round(EC.ai_cost(100_000, "sonnet", "medium", "standard"), 6), 0.36)

    def test_haiku_50k_high_novel(self):
        # 50000/1e6 * 0.25 * (1+0.5) * 2.0 = 0.05*0.25*1.5*2.0 = 0.0375
        self.assertEqual(round(EC.ai_cost(50_000, "haiku", "high", "novel"), 6), 0.0375)

    def test_unknown_model_defaults_to_sonnet_rate(self):
        # Unknown model falls back to the sonnet rate (3.0/M).
        self.assertEqual(
            EC.ai_cost(100_000, "nonexistent", "medium", "standard"),
            EC.ai_cost(100_000, "sonnet", "medium", "standard"),
        )


class HoursArithmetic(unittest.TestCase):
    """AC-4: M + senior factor sum -> 27.6 / 34.5 total hours."""

    def test_m_senior_base_hours(self):
        # M = (4,5) SP, senior multiplier = 6 -> base 24 / 30 hours.
        self.assertEqual(EC.hours_range(4, 5, 6), (24.0, 30.0))

    def test_m_senior_buffered_total(self):
        b_min, b_max = EC.buffered_hours(24.0, 30.0)
        self.assertEqual(round(b_min, 2), 27.6)
        self.assertEqual(round(b_max, 2), 34.5)

    def test_tshirt_m_lookup(self):
        self.assertEqual(EC.TSHIRT_SP["M"], (4, 5))


class CliShapeAndSelfTest(unittest.TestCase):
    """CLI contract: json.loads(stdout) shape + --self-test exit path."""

    def _run(self, *args):
        return subprocess.run(
            [sys.executable, str(TARGET), *args],
            capture_output=True,
            text=True,
        )

    def test_json_stdout_shape(self):
        # End-to-end: M senior, rate, 100k tokens, factors summing to 15.
        proc = self._run(
            "--size", "M", "--level", "senior", "--rate", "150",
            "--tokens", "100000", "--model", "sonnet",
            "--factors", "3", "3", "3", "3", "3",
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        data = json.loads(proc.stdout)  # shape assertion: parses as JSON object
        self.assertIsInstance(data, dict)
        self.assertEqual(data["total_hours"], {"min": 27.6, "max": 34.5})
        self.assertEqual(data["ai_cost"]["usd"], round(0.36, 6))
        self.assertEqual(data["complexity"]["total"], 15)
        self.assertEqual(data["complexity"]["band"], "MEDIUM")

    def test_self_test_exit_zero(self):
        proc = self._run("--self-test")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        payload = json.loads(proc.stdout)
        self.assertEqual(payload["self_test"], "ok")

    def test_no_args_exits_nonzero(self):
        # No meaningful input -> help on stderr + exit 1.
        proc = self._run()
        self.assertEqual(proc.returncode, 1)


class CLIInProcess(unittest.TestCase):
    """In-process CLI coverage: drive main()/_build_parser()/_run() so coverage.py
    records the argparse + entry-point lines that the subprocess CLI tests exercise
    but cannot register for in-process measurement (AC-3)."""

    @staticmethod
    def _run_main(argv):
        import contextlib
        import io
        saved = sys.argv
        sys.argv = ["estimate-calc.py", *argv]
        out, err = io.StringIO(), io.StringIO()
        code = 0
        try:
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                EC.main()
        except SystemExit as exc:
            code = 0 if exc.code in (0, None) else (exc.code if isinstance(exc.code, int) else 1)
        finally:
            sys.argv = saved
        return code, out.getvalue(), err.getvalue()

    def test_main_self_test_ok(self):
        code, out, _ = self._run_main(["--self-test"])
        self.assertEqual(code, 0)
        self.assertIn("self_test", out)

    def test_main_size_level_total_hours(self):
        code, out, _ = self._run_main(["--size", "M", "--level", "senior", "--rate", "150"])
        self.assertEqual(code, 0)
        data = json.loads(out)
        self.assertEqual(data["total_hours"]["min"], 27.6)
        self.assertEqual(data["total_hours"]["max"], 34.5)

    def test_main_factors_only_band(self):
        code, out, _ = self._run_main(["--factors", "3", "3", "2", "2", "3"])
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out)["complexity"]["band"], "MEDIUM")

    def test_main_tokens_only_ai_cost(self):
        code, out, _ = self._run_main(
            ["--tokens", "100000", "--model", "sonnet",
             "--retry-complexity", "medium", "--codebase-type", "standard"])
        self.assertEqual(code, 0)
        self.assertAlmostEqual(json.loads(out)["ai_cost"]["usd"], 0.36, places=4)

    def test_main_no_input_exits_1(self):
        code, _, _ = self._run_main([])
        self.assertEqual(code, 1)

    def test_build_parser_and_run_directly(self):
        parser = EC._build_parser()
        ns = parser.parse_args(["--size", "L", "--level", "mid"])
        result = EC._run(ns)
        self.assertIn("sp", result)
        self.assertIn("total_hours", result)


if __name__ == "__main__":
    unittest.main()
