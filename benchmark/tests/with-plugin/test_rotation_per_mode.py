"""benchmark/tests/with-plugin/test_rotation_per_mode.py — AC-7 rotation (DV0d).

Tests benchmark/lib/rotation.py per-mode latest-3 correctness:
  - Seeding 3 deterministic + 3 live records keeps all 6.
  - A 4th deterministic run drops the OLDEST deterministic; live untouched.
  - A 4th live run drops the OLDEST live; deterministic untouched.
  - Order is stable (newest last, sorted by timestamp_utc).
  - Atomic write: tmp file is cleaned up after replace.
  - rotate_detail: per-run detail files rotate per mode, other mode dir untouched.
"""

import importlib.util
import json
import os
import sys
import tempfile
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
_LIB = os.path.join(os.path.dirname(os.path.dirname(_HERE)), "lib")
if _LIB not in sys.path:
    sys.path.insert(0, _LIB)

import rotation  # noqa: E402
import metrics   # noqa: E402


def _rec(mode: str, ts: str, idx: int = 0) -> dict:
    """Minimal but schema-valid dict resembling a BenchmarkRecord JSON blob."""
    pm = metrics.PathMetrics(
        tokens=metrics.Tokens(None, None, None),
        cost_usd=None, wall_clock_s=float(idx),
        loc_produced=100, test_count=9, coverage_pct=0.0,
        estimate_complexity_score=0, stage_count=1, pass_fail="pass",
    )
    rec = metrics.make_record(
        run_id=f"{mode}-{ts}-{idx:04d}",
        timestamp_utc=ts,
        mode=mode,
        git_sha=f"sha{idx:04d}",
        budget_usd=None,
        with_p=pm, without_p=pm,
    )
    return rec.to_json()


class TestRotateKeepsLatestThreePerMode(unittest.TestCase):
    def setUp(self):
        self.td = tempfile.mkdtemp()
        self.history = os.path.join(self.td, "history.json")

    def tearDown(self):
        import shutil
        shutil.rmtree(self.td, ignore_errors=True)

    def _seed(self, history_path: str) -> None:
        """Seed 3 deterministic + 3 live records."""
        for i, ts in enumerate(("2026-01-01T00:00:00Z",
                                "2026-01-02T00:00:00Z",
                                "2026-01-03T00:00:00Z")):
            rotation.rotate(history_path, _rec("deterministic", ts, i))
        for i, ts in enumerate(("2026-02-01T00:00:00Z",
                                "2026-02-02T00:00:00Z",
                                "2026-02-03T00:00:00Z")):
            rotation.rotate(history_path, _rec("live", ts, i + 10))

    def test_seed_keeps_all_six(self):
        self._seed(self.history)
        with open(self.history) as f:
            data = json.load(f)
        self.assertEqual(len(data["deterministic"]), 3)
        self.assertEqual(len(data["live"]), 3)

    def test_fourth_deterministic_drops_oldest_deterministic(self):
        self._seed(self.history)
        fourth = _rec("deterministic", "2026-01-04T00:00:00Z", 99)
        rotation.rotate(self.history, fourth)
        with open(self.history) as f:
            data = json.load(f)
        det = data["deterministic"]
        self.assertEqual(len(det), 3, "deterministic must remain at 3")
        timestamps = [r["timestamp_utc"] for r in det]
        self.assertNotIn("2026-01-01T00:00:00Z", timestamps, "oldest det should be dropped")
        self.assertIn("2026-01-04T00:00:00Z", timestamps, "newest det should be present")

    def test_fourth_deterministic_leaves_live_untouched(self):
        self._seed(self.history)
        with open(self.history) as f:
            before = json.load(f)["live"]
        rotation.rotate(self.history, _rec("deterministic", "2026-01-04T00:00:00Z", 99))
        with open(self.history) as f:
            after = json.load(f)["live"]
        self.assertEqual(before, after, "live bucket must be byte-identical after deterministic rotation")

    def test_fourth_live_drops_oldest_live(self):
        self._seed(self.history)
        rotation.rotate(self.history, _rec("live", "2026-02-04T00:00:00Z", 99))
        with open(self.history) as f:
            data = json.load(f)
        live = data["live"]
        self.assertEqual(len(live), 3)
        timestamps = [r["timestamp_utc"] for r in live]
        self.assertNotIn("2026-02-01T00:00:00Z", timestamps, "oldest live should be dropped")
        self.assertIn("2026-02-04T00:00:00Z", timestamps)

    def test_fourth_live_leaves_deterministic_untouched(self):
        self._seed(self.history)
        with open(self.history) as f:
            before = json.load(f)["deterministic"]
        rotation.rotate(self.history, _rec("live", "2026-02-04T00:00:00Z", 99))
        with open(self.history) as f:
            after = json.load(f)["deterministic"]
        self.assertEqual(before, after)

    def test_order_stable_newest_last(self):
        self._seed(self.history)
        rotation.rotate(self.history, _rec("deterministic", "2026-01-04T00:00:00Z", 99))
        with open(self.history) as f:
            det = json.load(f)["deterministic"]
        timestamps = [r["timestamp_utc"] for r in det]
        self.assertEqual(timestamps, sorted(timestamps), "records must be sorted newest-last")
        self.assertEqual(timestamps[-1], "2026-01-04T00:00:00Z")

    def test_empty_history_file_initialised(self):
        # non-existent path — rotate creates it.
        path = os.path.join(self.td, "new_history.json")
        self.assertFalse(os.path.exists(path))
        rotation.rotate(path, _rec("deterministic", "2026-01-01T00:00:00Z", 1))
        self.assertTrue(os.path.exists(path))
        with open(path) as f:
            data = json.load(f)
        self.assertEqual(len(data["deterministic"]), 1)
        self.assertEqual(len(data["live"]), 0)


class TestAtomicWrite(unittest.TestCase):
    def setUp(self):
        self.td = tempfile.mkdtemp()
        self.history = os.path.join(self.td, "history.json")

    def tearDown(self):
        import shutil
        shutil.rmtree(self.td, ignore_errors=True)

    def test_no_tmp_files_left_after_write(self):
        rotation.rotate(self.history, _rec("deterministic", "2026-01-01T00:00:00Z", 1))
        leftovers = [f for f in os.listdir(self.td) if f.endswith(".tmp")]
        self.assertEqual(leftovers, [], f"stale tmp files: {leftovers}")

    def test_history_is_valid_json_after_write(self):
        rotation.rotate(self.history, _rec("live", "2026-01-01T00:00:00Z", 1))
        with open(self.history) as f:
            data = json.load(f)  # raises if corrupt
        self.assertIn("deterministic", data)
        self.assertIn("live", data)


class TestRotateDetail(unittest.TestCase):
    def setUp(self):
        self.td = tempfile.mkdtemp()
        self.runs = os.path.join(self.td, "runs")

    def tearDown(self):
        import shutil
        shutil.rmtree(self.td, ignore_errors=True)

    def test_detail_file_written(self):
        rec = _rec("deterministic", "2026-01-01T00:00:00Z", 1)
        path = rotation.rotate_detail(self.runs, rec["run_id"], rec)
        self.assertTrue(os.path.exists(path))
        with open(path) as f:
            data = json.load(f)
        self.assertEqual(data["run_id"], rec["run_id"])

    def test_fourth_detail_prunes_oldest(self):
        for i, ts in enumerate(("2026-01-01T00:00:00Z",
                                "2026-01-02T00:00:00Z",
                                "2026-01-03T00:00:00Z",
                                "2026-01-04T00:00:00Z")):
            rec = _rec("deterministic", ts, i)
            rotation.rotate_detail(self.runs, rec["run_id"], rec)
        mode_dir = os.path.join(self.runs, "deterministic")
        files = [f for f in os.listdir(mode_dir) if f.endswith(".json")]
        self.assertEqual(len(files), 3, f"expected 3 detail files, got {files}")

    def test_live_detail_does_not_touch_deterministic_dir(self):
        det_rec = _rec("deterministic", "2026-01-01T00:00:00Z", 1)
        rotation.rotate_detail(self.runs, det_rec["run_id"], det_rec)
        det_files_before = set(os.listdir(os.path.join(self.runs, "deterministic")))

        for i in range(4):
            live_rec = _rec("live", f"2026-02-0{i+1}T00:00:00Z", i + 10)
            rotation.rotate_detail(self.runs, live_rec["run_id"], live_rec)

        det_files_after = set(os.listdir(os.path.join(self.runs, "deterministic")))
        self.assertEqual(det_files_before, det_files_after)


if __name__ == "__main__":
    unittest.main()
