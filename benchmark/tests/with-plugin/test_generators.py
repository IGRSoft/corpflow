"""benchmark/tests/with-plugin/test_generators.py — AC-5 generator real-output (DV0d).

Asserts that both the WITH-plugin and WITHOUT-plugin generators:
  - Produce a runnable TTT app whose own unittest suite passes.
  - Record REAL loc_produced (>0), test_count (>0), pass_fail="pass".
  - WITH: stage_count > 1 (staged scaffold); estimate_complexity_score > 0.
  - WITHOUT: stage_count == 1 (single-shot); estimate_complexity_score == 0.
  - loc_produced and test_count are equal between both (same template, AC-5 correctness check).
  - No network call is made; no benchmark/live/ is imported.

Uses importlib to load both generators from absolute paths (no install).
"""

import importlib.util
import os
import sys
import tempfile
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
_BENCH = os.path.dirname(os.path.dirname(_HERE))           # benchmark/
_LIB = os.path.join(_BENCH, "lib")                        # benchmark/lib/
_WITH_GEN = os.path.join(_BENCH, "with-plugin", "generate.py")
_WITHOUT_GEN = os.path.join(_BENCH, "without-plugin", "generate.py")

if _LIB not in sys.path:
    sys.path.insert(0, _LIB)


def _load(name: str, path: str):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# Load once per module (expensive: drives estimate-calc.py).
_with_gen = _load("with_gen", _WITH_GEN)
_without_gen = _load("without_gen", _WITHOUT_GEN)


class TestWithPluginGenerator(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._td = tempfile.mkdtemp(prefix="ttt_test_with_")
        cls.pm = _with_gen.generate(cls._td, measure_cov=False)

    @classmethod
    def tearDownClass(cls):
        import shutil
        shutil.rmtree(cls._td, ignore_errors=True)

    def test_pass_fail_is_pass(self):
        self.assertEqual(self.pm.pass_fail, "pass",
                         "WITH generator app's unittest suite must pass")

    def test_loc_produced_positive(self):
        self.assertGreater(self.pm.loc_produced, 0)

    def test_test_count_positive(self):
        self.assertGreater(self.pm.test_count, 0)

    def test_stage_count_greater_than_one(self):
        """Staged path must have >1 stages (process-overhead signal)."""
        self.assertGreater(self.pm.stage_count, 1,
                           f"WITH stage_count expected >1, got {self.pm.stage_count}")

    def test_estimate_complexity_score_positive(self):
        """WITH drives the real estimate-calc.py -> score must be > 0."""
        self.assertGreater(self.pm.estimate_complexity_score, 0,
                           f"WITH complexity_score expected >0, got {self.pm.estimate_complexity_score}")

    def test_tokens_null_in_deterministic(self):
        self.assertIsNone(self.pm.tokens.input)
        self.assertIsNone(self.pm.tokens.output)
        self.assertIsNone(self.pm.tokens.total)

    def test_wall_clock_s_positive(self):
        self.assertGreater(self.pm.wall_clock_s, 0.0)

    def test_app_dir_contains_tictactoe_package(self):
        app_dir = os.path.join(self._td, "with")
        pkg_dir = os.path.join(app_dir, "tictactoe")
        self.assertTrue(os.path.isdir(pkg_dir), f"tictactoe package missing at {pkg_dir}")
        self.assertTrue(os.path.isfile(os.path.join(pkg_dir, "board.py")))


class TestWithoutPluginGenerator(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._td = tempfile.mkdtemp(prefix="ttt_test_without_")
        cls.pm = _without_gen.generate(cls._td, measure_cov=False)

    @classmethod
    def tearDownClass(cls):
        import shutil
        shutil.rmtree(cls._td, ignore_errors=True)

    def test_pass_fail_is_pass(self):
        self.assertEqual(self.pm.pass_fail, "pass",
                         "WITHOUT generator app's unittest suite must pass")

    def test_loc_produced_positive(self):
        self.assertGreater(self.pm.loc_produced, 0)

    def test_test_count_positive(self):
        self.assertGreater(self.pm.test_count, 0)

    def test_stage_count_is_one(self):
        """WITHOUT is single-shot: stage_count must be exactly 1."""
        self.assertEqual(self.pm.stage_count, 1,
                         f"WITHOUT stage_count expected 1, got {self.pm.stage_count}")

    def test_estimate_complexity_score_is_zero(self):
        self.assertEqual(self.pm.estimate_complexity_score, 0)

    def test_tokens_null(self):
        self.assertIsNone(self.pm.tokens.total)

    def test_app_dir_contains_tictactoe_package(self):
        app_dir = os.path.join(self._td, "without")
        pkg_dir = os.path.join(app_dir, "tictactoe")
        self.assertTrue(os.path.isdir(pkg_dir), f"tictactoe package missing at {pkg_dir}")


class TestBothGeneratorsMatchOnQuality(unittest.TestCase):
    """Both paths build the SAME template; loc + test_count must be equal (AC-5 correctness gate)."""

    @classmethod
    def setUpClass(cls):
        cls._td = tempfile.mkdtemp(prefix="ttt_test_both_")
        cls.with_pm = _with_gen.generate(cls._td, measure_cov=False)
        cls.without_pm = _without_gen.generate(cls._td, measure_cov=False)

    @classmethod
    def tearDownClass(cls):
        import shutil
        shutil.rmtree(cls._td, ignore_errors=True)

    def test_loc_produced_equal(self):
        self.assertEqual(
            self.with_pm.loc_produced, self.without_pm.loc_produced,
            "same template must produce equal loc_produced",
        )

    def test_test_count_equal(self):
        self.assertEqual(
            self.with_pm.test_count, self.without_pm.test_count,
            "same template must produce equal test_count",
        )

    def test_both_pass(self):
        self.assertEqual(self.with_pm.pass_fail, "pass")
        self.assertEqual(self.without_pm.pass_fail, "pass")

    def test_stage_count_differs(self):
        """Process-overhead comparison: WITH has more stages than WITHOUT."""
        self.assertGreater(
            self.with_pm.stage_count, self.without_pm.stage_count,
            "WITH must have higher stage_count than WITHOUT (process-overhead signal)",
        )

    def test_no_live_import(self):
        """Ensure benchmark/live/ was never imported during the deterministic run."""
        live_mods = [m for m in sys.modules if "benchmark.live" in m or "benchmark/live" in m
                     or (hasattr(sys.modules.get(m), "__file__") and sys.modules[m].__file__
                         and "benchmark/live" in (sys.modules[m].__file__ or ""))]
        self.assertEqual(live_mods, [], f"live module(s) unexpectedly imported: {live_mods}")


if __name__ == "__main__":
    unittest.main()
