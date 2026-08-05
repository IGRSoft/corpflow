"""Re-homed PluginScriptsTests/LayoutCalcTests behaviors (17) against the UNCHANGED
layout-calc.py — in-process for the real geometry/ValueError contracts plus CLI
smoke for the argparse guards and end-to-end JSON shape.

Geometry expectations are independent hard-coded goldens, not re-derivations of
the production formula. The previous form (``round(1320 * 0.06)`` etc.) restated
layout-calc.py's own arithmetic, so a changed coefficient or aspect constant
moved the expectation with the code and the assertion could not fail.

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

_IPHONE = lay._DEVICE_REGISTRY["iphone-6.9-1320x2868"]


def _layout(spec, key):
    return lay.compute_layout(spec.w, spec.h, spec.platform, key, spec.headline_fs, spec.subtitle_fs)


class ComputeLayoutGeometry(unittest.TestCase):
    """Goldens for the 1320x2868 iPhone canvas."""

    def test_layout_a_headline_and_subtitle(self):
        r = _layout(_IPHONE, "A")
        self.assertEqual(
            r["headline"],
            {"x": 79, "y": 115, "w": 1162, "fontSize": 72, "textAlign": "center"},
        )
        self.assertEqual(
            r["subtitle"],
            {"x": 132, "y": 373, "w": 1056, "fontSize": 42, "opacity": 0.75, "textAlign": "center"},
        )

    def test_layout_a_screenshot_centered(self):
        ss = _layout(_IPHONE, "A")["screenshot"]
        self.assertEqual(ss, {"x": 170, "y": 688, "w": 979, "h": 2122, "cornerRadius": 32})
        # Centred: the two margins on a 1320-wide canvas agree to within the
        # one pixel that integer rounding of an odd remainder can cost.
        self.assertLessEqual(abs((1320 - ss["x"] - ss["w"]) - ss["x"]), 1)

    def test_layout_d_taller_than_a(self):
        a = _layout(_IPHONE, "A")["screenshot"]
        d = _layout(_IPHONE, "D")["screenshot"]
        self.assertEqual(a["h"], 2122)
        self.assertEqual(d["h"], 2237)
        self.assertGreater(d["h"], a["h"])

    def test_layout_c_screenshot_top(self):
        r = _layout(_IPHONE, "C")
        self.assertEqual(r["screenshot"], {"x": 230, "y": 86, "w": 860, "h": 1864, "cornerRadius": 32})
        # Text sits below the screenshot in layout C.
        self.assertEqual(r["headline"]["y"], 2065)
        self.assertGreater(r["headline"]["y"], r["screenshot"]["y"] + r["screenshot"]["h"])


class FullBleedAndErrors(unittest.TestCase):
    def test_full_bleed_passthrough(self):
        tv = lay._DEVICE_REGISTRY["appletv-4k-3840x2160"]
        fb = lay.full_bleed_result(tv)
        self.assertTrue(fb["full_bleed"])
        self.assertEqual(fb["screenshot"], {"x": 0, "y": 0, "w": 3840, "h": 2160, "cornerRadius": 0})

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
        r = _layout(mac, "A")
        # Landscape: wider than tall, unlike every phone golden above.
        self.assertEqual(r["screenshot"], {"x": 461, "y": 540, "w": 1958, "h": 1224, "cornerRadius": 16})
        self.assertGreater(r["screenshot"]["w"], r["screenshot"]["h"])
        self.assertEqual(r["headline"]["fontSize"], 84)

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
        self.assertEqual(data["device"], {"name": 'iPhone 6.9" (1320x2868)', "w": 1320, "h": 2868})
        # The CLI must emit the same geometry the in-process call produces.
        self.assertEqual(data["screenshot"], {"x": 170, "y": 688, "w": 979, "h": 2122, "cornerRadius": 32})
        for key in ("headline", "subtitle", "screenshot"):
            self.assertIn(key, data)

    def test_full_bleed_device_json(self):
        r = run_cli(LAYOUT_CALC, ["appletv-4k-3840x2160"])
        self.assertEqual(r.returncode, 0, r.stderr)
        data = json.loads(r.stdout)
        self.assertTrue(data["full_bleed"])
        self.assertEqual(data["screenshot"]["w"], 3840)
        # A full-bleed device emits no text frames.
        self.assertNotIn("headline", data)

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
        data = json.loads(r.stdout)
        # A manual canvas names itself from the platform, not the registry.
        self.assertEqual(data["device"], {"name": "IOS (1320x2868)", "w": 1320, "h": 2868})
        # Layout B is the left-aligned variant of A: same boxes, different align.
        self.assertEqual(data["headline"]["textAlign"], "left")
        self.assertEqual(data["subtitle"]["textAlign"], "left")
        self.assertEqual(data["subtitle"]["x"], 79)
        self.assertEqual(data["screenshot"], {"x": 170, "y": 688, "w": 979, "h": 2122, "cornerRadius": 32})

    def test_no_args_prints_help_exit_0(self):
        r = run_cli(LAYOUT_CALC, [])
        self.assertEqual(r.returncode, 0)
        # rc==0 alone said nothing: assert the help text is what was printed.
        self.assertIn("usage: layout-calc.py", r.stdout)
        self.assertIn("--list-devices", r.stdout)
        self.assertEqual(r.stdout.count("{"), r.stdout.count("}"))


if __name__ == "__main__":
    unittest.main()
