"""Generators parity (port of GeneratorsTests) — REAL nested `swift test` on a
copied ttt-template (the retained measurement instrument). WITH is staged +
estimate-driven; WITHOUT is single-shot. Memoized once (two swift builds) and
shared across assertions; temp dirs cleaned in tearDownClass.
"""

import os
import re
import shutil
import subprocess
import tempfile
import unittest

from benchmarkkit import generators


def _swift_toolchain_usable():
    """A swiftly shim stays on PATH after its toolchain is uninstalled, so
    presence on PATH does not imply a usable toolchain."""
    if not shutil.which("swift"):
        return False
    try:
        return subprocess.run(
            ["swift", "--version"],
            capture_output=True,
            timeout=60,
        ).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False

_HARNESS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_PLUGIN_ROOT = os.path.dirname(os.path.dirname(_HARNESS))  # <root>/benchmark/harness -> <root>
_TEMPLATE = os.path.join(_PLUGIN_ROOT, "benchmark", "ttt-template")
_ESTIMATE = os.path.join(_PLUGIN_ROOT, "skills", "estimation-methodology", "scripts", "estimate-calc.py")


@unittest.skipUnless(_swift_toolchain_usable(), "working swift toolchain required (measurement instrument)")
class Generators(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._workdir = tempfile.mkdtemp(prefix="gen-")
        cls.with_pm = generators.generate_with_plugin(
            workdir=cls._workdir, template_dir=_TEMPLATE, plugin_root=_PLUGIN_ROOT,
            estimate_calc_path=_ESTIMATE)
        cls.without_pm = generators.generate_without_plugin(
            workdir=cls._workdir, template_dir=_TEMPLATE, plugin_root=_PLUGIN_ROOT)
        cls.with_app = os.path.join(cls._workdir, "with")
        cls.without_app = os.path.join(cls._workdir, "without")

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls._workdir, ignore_errors=True)

    def test_with_passes_and_measures(self):
        self.assertEqual(self.with_pm.pass_fail, "pass")
        self.assertGreater(self.with_pm.loc_produced, 0)
        self.assertGreater(self.with_pm.test_count, 0)
        self.assertGreater(self.with_pm.stage_count, 1)
        self.assertGreater(self.with_pm.estimate_complexity_score, 0)
        self.assertGreater(self.with_pm.wall_clock_s, 0)

    def test_with_tokens_null_in_deterministic(self):
        self.assertIsNone(self.with_pm.tokens.total)
        self.assertIsNone(self.with_pm.cost_usd)

    def test_with_app_has_expected_files(self):
        self.assertTrue(os.path.exists(os.path.join(self.with_app, "Package.swift")))
        self.assertTrue(os.path.exists(
            os.path.join(self.with_app, "Sources", "TicTacToeKit", "Engine", "Board.swift")))

    def test_without_passes_single_shot(self):
        self.assertEqual(self.without_pm.pass_fail, "pass")
        self.assertEqual(self.without_pm.stage_count, 1)
        self.assertEqual(self.without_pm.estimate_complexity_score, 0)

    def test_both_paths_equal_loc_and_test_count(self):
        self.assertEqual(self.with_pm.loc_produced, self.without_pm.loc_produced)
        self.assertEqual(self.with_pm.test_count, self.without_pm.test_count)

    def test_with_stage_count_greater_than_without(self):
        self.assertGreater(self.with_pm.stage_count, self.without_pm.stage_count)

    def test_no_live_linkage(self):
        # Static, order-independent (a shared discover run pollutes sys.modules via
        # sibling live-test modules): the benchmarkkit sources never import benchmarklive.
        kit_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                               "benchmarkkit")
        live_import = re.compile(r"^\s*(import\s+benchmarklive|from\s+benchmarklive)", re.MULTILINE)
        for name in os.listdir(kit_dir):
            if name.endswith(".py"):
                with open(os.path.join(kit_dir, name), encoding="utf-8") as f:
                    self.assertIsNone(live_import.search(f.read()), f"{name} imports benchmarklive")


if __name__ == "__main__":
    unittest.main()
