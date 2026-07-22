"""Re-homed PluginScriptsTests/LayoutCalcTests behaviors (17) against the UNCHANGED
layout-calc.py — in-process for the real geometry/ValueError contracts plus CLI
smoke for the argparse guards and end-to-end JSON shape.

# @test-required
# @test-tag: smoke
# @depends-on: compute_layout
# @depends-on: full_bleed_result
"""

import argparse
import json
import unittest

from _scriptimport import LAYOUT_CALC, load_module, run_cli

lay = load_module(LAYOUT_CALC, "layout_calc")

_PHONE = lay._PHONE_ASPECT
_MAC = lay._MAC_ASPECT
_IPHONE = lay._DEVICE_REGISTRY["iphone-6.9-1320x2868"]


def _layout(spec, key):
    return lay.compute_layout(spec.w, spec.h, spec.platform, key, spec.headline_fs, spec.subtitle_fs)


class ComputeLayoutGeometry(unittest.TestCase):
    def test_layout_a_headline_and_subtitle(self):
        r = _layout(_IPHONE, "A")
        self.assertEqual(r["headline"]["x"], round(1320 * 0.06))
        self.assertEqual(r["headline"]["y"], round(2868 * 0.04))
        self.assertEqual(r["headline"]["w"], round(1320 * 0.88))
        self.assertEqual(r["headline"]["fontSize"], 72)
        self.assertEqual(r["subtitle"]["opacity"], 0.75)

    def test_layout_a_screenshot_centered(self):
        ss = _layout(_IPHONE, "A")["screenshot"]
        ss_h = round(2868 * 0.74)
        ss_w = round(ss_h / _PHONE)
        ss_x = round((1320 - ss_w) / 2)
        self.assertEqual(ss["h"], ss_h)
        self.assertEqual(ss["w"], ss_w)
        self.assertEqual(ss["x"], ss_x)
        self.assertEqual(ss["cornerRadius"], 32)

    def test_layout_d_taller_than_a(self):
        a = _layout(_IPHONE, "A")["screenshot"]["h"]
        d = _layout(_IPHONE, "D")["screenshot"]["h"]
        self.assertGreater(d, a)

    def test_layout_c_screenshot_top(self):
        r = _layout(_IPHONE, "C")
        self.assertEqual(r["screenshot"]["h"], round(2868 * 0.65))
        self.assertEqual(r["screenshot"]["y"], round(2868 * 0.03))
        self.assertEqual(r["headline"]["y"], round(2868 * 0.72))


class FullBleedAndErrors(unittest.TestCase):
    def test_full_bleed_passthrough(self):
        tv = lay._DEVICE_REGISTRY["appletv-4k-3840x2160"]
        fb = lay.full_bleed_result(tv)
        self.assertTrue(fb["full_bleed"])
        self.assertEqual(fb["screenshot"]["w"], 3840)
        self.assertEqual(fb["screenshot"]["h"], 2160)
        self.assertEqual(fb["screenshot"]["cornerRadius"], 0)

    def test_unknown_layout_raises_value_error(self):
        # True in-process contract: compute_layout raises ValueError for "Z".
        with self.assertRaises(ValueError):
            lay.compute_layout(1320, 2868, "ios", "Z", 72, 42)

    def test_unknown_layout_rejected_at_cli(self):
        r = run_cli(LAYOUT_CALC, ["iphone-6.9-1320x2868", "--layout", "Z"])
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("--layout", r.stderr)

    def test_mac_uses_landscape_aspect(self):
        mac = lay._DEVICE_REGISTRY["mac-2880x1800"]
        ss = _layout(mac, "A")["screenshot"]
        mac_ss_h = round(1800 * 0.68)
        self.assertEqual(ss["h"], mac_ss_h)
        self.assertEqual(ss["w"], round(mac_ss_h * _MAC))
        self.assertEqual(ss["cornerRadius"], 16)

    def test_resolve_spec_by_device_key(self):
        ns = argparse.Namespace(device="iphone-6.9-1320x2868", w=None, h=None, platform=None)
        spec = lay._resolve_spec(ns)
        self.assertEqual(spec.w, 1320)
        self.assertEqual(spec.h, 2868)


class CliShapeAndSelfTest(unittest.TestCase):
    def test_json_stdout_shape_by_device_key(self):
        r = run_cli(LAYOUT_CALC, ["iphone-6.9-1320x2868", "--layout", "A"])
        self.assertEqual(r.returncode, 0, r.stderr)
        data = json.loads(r.stdout)
        self.assertEqual(data["device"]["w"], 1320)
        self.assertEqual(data["device"]["h"], 2868)
        for key in ("headline", "subtitle", "screenshot"):
            self.assertIn(key, data)

    def test_full_bleed_device_json(self):
        r = run_cli(LAYOUT_CALC, ["appletv-4k-3840x2160"])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(json.loads(r.stdout)["full_bleed"])

    def test_self_test_exit_zero(self):
        r = run_cli(LAYOUT_CALC, ["--self-test"])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("self-test passed", r.stdout)

    def test_unknown_device_key_exits_nonzero(self):
        r = run_cli(LAYOUT_CALC, ["no-such-device-key"])
        self.assertNotEqual(r.returncode, 0)

    def test_list_devices(self):
        r = run_cli(LAYOUT_CALC, ["--list-devices"])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("iphone-6.9-1320x2868", r.stdout)

    def test_manual_canvas_ios(self):
        r = run_cli(LAYOUT_CALC, ["--w", "1320", "--h", "2868", "--platform", "ios", "--layout", "B"])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("device", json.loads(r.stdout))

    def test_no_args_help_exit_0(self):
        r = run_cli(LAYOUT_CALC, [])
        self.assertEqual(r.returncode, 0)


if __name__ == "__main__":
    unittest.main()
