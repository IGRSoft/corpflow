#!/usr/bin/env python3
"""Unit tests for skills/appstore-screenshots/scripts/layout-calc.py (DV0c).

Imports the module under test by file path via importlib (no install step) and
asserts the REAL geometry contracts:
  - compute_layout proportional math for an iPhone device (Layout A).
  - full_bleed_result canvas-fill passthrough for tvOS.
  - Layout D screenshot taller than Layout A.
  - Unknown layout raises ValueError.
  - CLI: json.loads(stdout) shape assertion + --self-test exit path + list/help.
"""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import unittest
from pathlib import Path

PLUGIN_ROOT = Path(__file__).resolve().parents[2]
TARGET = PLUGIN_ROOT / "skills" / "appstore-screenshots" / "scripts" / "layout-calc.py"


def _load_module():
    name = "layout_calc_under_test"
    spec = importlib.util.spec_from_file_location(name, TARGET)
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    # Register before exec: Python 3.14 @dataclass resolves cls.__module__ via
    # sys.modules during class creation, which is None for unregistered modules.
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


LC = _load_module()


class ComputeLayoutGeometry(unittest.TestCase):
    """Happy path: proportional geometry for iPhone 6.9 Layout A."""

    def setUp(self):
        self.spec = LC._DEVICE_REGISTRY["iphone-6.9-1320x2868"]

    def test_layout_a_headline_and_subtitle(self):
        res = LC.compute_layout(
            self.spec.w, self.spec.h, self.spec.platform, "A",
            self.spec.headline_fs, self.spec.subtitle_fs,
        )
        self.assertEqual(res["headline"]["x"], round(1320 * 0.06))
        self.assertEqual(res["headline"]["y"], round(2868 * 0.04))
        self.assertEqual(res["headline"]["w"], round(1320 * 0.88))
        self.assertEqual(res["headline"]["fontSize"], 72)
        self.assertEqual(res["subtitle"]["opacity"], 0.75)

    def test_layout_a_screenshot_centered(self):
        res = LC.compute_layout(
            self.spec.w, self.spec.h, self.spec.platform, "A",
            self.spec.headline_fs, self.spec.subtitle_fs,
        )
        ss_h = round(2868 * 0.74)
        ss_w = round(ss_h / LC._PHONE_ASPECT)
        ss_x = round((1320 - ss_w) / 2)
        self.assertEqual(res["screenshot"]["h"], ss_h)
        self.assertEqual(res["screenshot"]["w"], ss_w)
        self.assertEqual(res["screenshot"]["x"], ss_x)
        self.assertEqual(res["screenshot"]["cornerRadius"], 32)

    def test_layout_d_taller_than_a(self):
        a = LC.compute_layout(self.spec.w, self.spec.h, self.spec.platform, "A",
                              self.spec.headline_fs, self.spec.subtitle_fs)
        d = LC.compute_layout(self.spec.w, self.spec.h, self.spec.platform, "D",
                              self.spec.headline_fs, self.spec.subtitle_fs)
        self.assertGreater(d["screenshot"]["h"], a["screenshot"]["h"])


class FullBleedAndErrors(unittest.TestCase):
    """Edge + failure: full-bleed passthrough and unknown-layout error."""

    def test_full_bleed_passthrough(self):
        tv = LC._DEVICE_REGISTRY["appletv-4k-3840x2160"]
        fb = LC.full_bleed_result(tv)
        self.assertTrue(fb["full_bleed"])
        self.assertEqual(fb["screenshot"]["w"], 3840)
        self.assertEqual(fb["screenshot"]["h"], 2160)
        self.assertEqual(fb["screenshot"]["cornerRadius"], 0)

    def test_unknown_layout_raises(self):
        spec = LC._DEVICE_REGISTRY["iphone-6.9-1320x2868"]
        with self.assertRaises(ValueError):
            LC.compute_layout(spec.w, spec.h, spec.platform, "Z",
                              spec.headline_fs, spec.subtitle_fs)

    def test_mac_uses_landscape_aspect(self):
        mac = LC._DEVICE_REGISTRY["mac-2880x1800"]
        res = LC.compute_layout(mac.w, mac.h, mac.platform, "A",
                                mac.headline_fs, mac.subtitle_fs)
        mac_ss_h = round(1800 * 0.68)
        mac_ss_w = round(mac_ss_h * LC._MAC_ASPECT)
        self.assertEqual(res["screenshot"]["h"], mac_ss_h)
        self.assertEqual(res["screenshot"]["w"], mac_ss_w)
        self.assertEqual(res["screenshot"]["cornerRadius"], 16)


class CliShapeAndSelfTest(unittest.TestCase):
    """CLI contract: json.loads(stdout) shape + --self-test exit path."""

    def _run(self, *args):
        return subprocess.run(
            [sys.executable, str(TARGET), *args],
            capture_output=True,
            text=True,
        )

    def test_json_stdout_shape_by_device_key(self):
        proc = self._run("iphone-6.9-1320x2868", "--layout", "A")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        data = json.loads(proc.stdout)  # shape assertion
        self.assertIsInstance(data, dict)
        self.assertEqual(data["device"]["w"], 1320)
        self.assertEqual(data["device"]["h"], 2868)
        for key in ("headline", "subtitle", "screenshot"):
            self.assertIn(key, data)

    def test_full_bleed_device_json(self):
        proc = self._run("appletv-4k-3840x2160")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        data = json.loads(proc.stdout)
        self.assertTrue(data["full_bleed"])

    def test_self_test_exit_zero(self):
        proc = self._run("--self-test")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("self-test passed", proc.stdout)

    def test_unknown_device_key_exits_nonzero(self):
        proc = self._run("no-such-device-key")
        self.assertNotEqual(proc.returncode, 0)


class CLIInProcess(unittest.TestCase):
    """In-process CLI coverage for main()/_resolve_spec(): drives the argparse entry
    point so coverage.py records the CLI + dispatch lines the subprocess tests exercise
    but cannot register for in-process measurement (AC-3)."""

    @staticmethod
    def _run_main(argv):
        import contextlib
        import io
        saved = sys.argv
        sys.argv = ["layout-calc.py", *argv]
        out, err = io.StringIO(), io.StringIO()
        code = 0
        try:
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                LC.main()
        except SystemExit as exc:
            code = 0 if exc.code in (0, None) else (exc.code if isinstance(exc.code, int) else 1)
        finally:
            sys.argv = saved
        return code, out.getvalue(), err.getvalue()

    def test_main_self_test_ok(self):
        code, _, _ = self._run_main(["--self-test"])
        self.assertEqual(code, 0)

    def test_main_list_devices(self):
        code, out, _ = self._run_main(["--list-devices"])
        self.assertEqual(code, 0)
        self.assertIn("iphone-6.9-1320x2868", out)

    def test_main_device_key_emits_json(self):
        code, out, _ = self._run_main(["iphone-6.9-1320x2868", "--layout", "A"])
        self.assertEqual(code, 0)
        self.assertIsInstance(json.loads(out), dict)

    def test_main_manual_canvas_ios(self):
        code, out, _ = self._run_main(["--w", "1320", "--h", "2868", "--platform", "ios", "--layout", "B"])
        self.assertEqual(code, 0)
        self.assertIn("device", json.loads(out))

    def test_main_full_bleed_device(self):
        code, out, _ = self._run_main(["appletv-4k-3840x2160"])
        self.assertEqual(code, 0)
        self.assertTrue(json.loads(out)["full_bleed"])

    def test_main_no_args_help_exit_0(self):
        code, _, _ = self._run_main([])
        self.assertEqual(code, 0)

    def test_resolve_spec_directly(self):
        import argparse
        ns = argparse.Namespace(device="iphone-6.9-1320x2868", w=None, h=None,
                                platform=None, layout="A", aspect=None,
                                list_devices=False, self_test=False)
        spec = LC._resolve_spec(ns)
        self.assertEqual(spec.w, 1320)
        self.assertEqual(spec.h, 2868)


if __name__ == "__main__":
    unittest.main()
