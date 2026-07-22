"""App-measurement parity (D4): baseline.measure_app is None without a
Package.swift; a present-but-broken package still yields a real loc/fail
measurement with `.build` swept; `exclude_dirs` prunes a sibling arm dir;
`dispatch(without_arm="real")` fills both arms' app metrics post-run.
"""

import json
import os
import shutil
import tempfile
import unittest

from benchmarklive import baseline
from benchmarklive.dispatch import dispatch

import sys as _sys
_sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # _helpers under any runner
from _helpers import (
    SequencedFakeDispatcher,
    fake_estimate_runner,
    load_json,
    make_live_sandbox,
    single_object_usage,
    stub_git_sha,
)

_ENV = {"ANTHROPIC_API_KEY": "k"}


def _write_min_package(app_dir: str, n_lines: int) -> None:
    """A Package.swift too old to resolve — `swift test` fails fast (no full build)."""
    os.makedirs(app_dir, exist_ok=True)
    with open(os.path.join(app_dir, "Package.swift"), "w", encoding="utf-8") as f:
        f.write("garbage-manifest\n")
    with open(os.path.join(app_dir, "Main.swift"), "w", encoding="utf-8") as f:
        f.write("\n".join(f"let v{i} = {i}" for i in range(n_lines)) + "\n")


class AppMeasure(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="am-")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_none_without_package_swift(self):
        app_dir = os.path.join(self.tmp, "app")
        os.makedirs(app_dir)
        with open(os.path.join(app_dir, "Notes.swift"), "w") as f:
            f.write("let a = 1\n")
        self.assertIsNone(baseline.measure_app(app_dir, self.tmp))

    def test_broken_package_loc_positive_fail_and_build_swept(self):
        app_dir = os.path.join(self.tmp, "app")
        _write_min_package(app_dir, n_lines=2)
        os.makedirs(os.path.join(app_dir, ".build"))
        m = baseline.measure_app(app_dir, self.tmp)
        self.assertIsNotNone(m)
        self.assertGreater(m.loc_produced, 0)
        self.assertEqual(m.pass_fail, "fail")
        self.assertFalse(os.path.exists(os.path.join(app_dir, ".build")))

    def test_exclude_dirs_prunes_sibling_arm(self):
        app_dir = os.path.join(self.tmp, "app")
        _write_min_package(app_dir, n_lines=1)
        _write_min_package(os.path.join(app_dir, "without"), n_lines=50)
        m = baseline.measure_app(app_dir, self.tmp, exclude_dirs={"without"})
        self.assertIsNotNone(m)
        self.assertEqual(m.loc_produced, 2)  # Main.swift(1) + Package.swift(1, itself *.swift)


class DispatchFillsAppMetrics(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="am-dispatch-")
        self.sb = make_live_sandbox(self.tmp)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _dispatch(self):
        fake = SequencedFakeDispatcher([single_object_usage(cost=0.01)])
        rc = dispatch(
            workdir=self.sb.run_id, budget=100.0, record_path=self.sb.record_path,
            benchmark_dir=self.sb.benchmark_dir, dispatcher=fake, env=_ENV,
            estimate_runner=fake_estimate_runner(0.001), stages=["PL"],
            git_sha_runner=stub_git_sha, without_arm="real")
        return rc

    def test_fills_with_app_from_arm_folder(self):
        # Per-arm folders: each arm is measured in its own with/ or without/ dir.
        _write_min_package(os.path.join(self.sb.workdir_path, "with"), n_lines=3)
        _write_min_package(os.path.join(self.sb.workdir_path, "without"), n_lines=50)
        self._dispatch()
        rec = load_json(self.sb.record_path)
        self.assertEqual(rec["paths"]["with"]["loc_produced"], 4)  # Main.swift(3) + Package.swift(1)

    def test_fills_without_app(self):
        _write_min_package(os.path.join(self.sb.workdir_path, "with"), n_lines=1)
        _write_min_package(os.path.join(self.sb.workdir_path, "without"), n_lines=4)
        self._dispatch()
        rec = load_json(self.sb.record_path)
        self.assertEqual(rec["paths"]["without"]["loc_produced"], 5)  # Main.swift(4) + Package.swift(1)


if __name__ == "__main__":
    unittest.main()
