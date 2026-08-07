"""Rotation parity (port of RotationTests): latest-3 per mode, 4th drops oldest,
other mode byte-identical, newest-last sort, empty-file init, no .tmp leftovers,
valid JSON after write, rotate_detail prune.
"""

import glob
import json
import os
import shutil
import tempfile
import unittest

from benchmarkkit import rotation


def _rec(mode, ts, run_id=None):
    return {"run_id": run_id or f"{mode}-{ts}", "timestamp_utc": ts, "mode": mode}


class RotationTests(unittest.TestCase):
    def setUp(self):
        self.td = tempfile.mkdtemp(prefix="rot-")
        self.history = os.path.join(self.td, "history.json")

    def tearDown(self):
        shutil.rmtree(self.td, ignore_errors=True)

    def test_latest_three_per_mode_and_fourth_drops_oldest(self):
        for i in range(4):
            rotation.rotate(self.history, _rec("deterministic", f"2026-07-05T18:0{i}:00Z"))
        with open(self.history) as f:
            data = json.load(f)
        det = data["deterministic"]
        self.assertEqual(len(det), 3)
        # Oldest (…18:00:00Z) dropped; newest LAST.
        self.assertEqual(det[0]["timestamp_utc"], "2026-07-05T18:01:00Z")
        self.assertEqual(det[-1]["timestamp_utc"], "2026-07-05T18:03:00Z")

    def test_live_records_are_never_rotated_away(self):
        """A live record costs real money and is the only evidence of its run."""
        for i in range(6):
            rotation.rotate(self.history, _rec("live", f"2026-07-05T18:0{i}:00Z"))
        with open(self.history) as f:
            live = json.load(f)["live"]
        self.assertEqual(len(live), 6)
        self.assertEqual(live[0]["timestamp_utc"], "2026-07-05T18:00:00Z")
        self.assertEqual(live[-1]["timestamp_utc"], "2026-07-05T18:05:00Z")

    def test_unbounded_detail_prune_keeps_every_file(self):
        """Unbounded retention must keep files, not delete the whole directory."""
        runs = os.path.join(self.td, "runs")
        for i in range(5):
            rotation.rotate_detail(runs, f"live-{i}",
                                   _rec("live", f"2026-07-05T18:0{i}:00Z", f"live-{i}"))
        self.assertEqual(len(os.listdir(os.path.join(runs, "live"))), 5)

    def test_other_mode_byte_identical(self):
        rotation.rotate(self.history, _rec("live", "2026-07-01T00:00:00Z"))
        with open(self.history) as f:
            live_before = json.dumps(json.load(f)["live"], indent=2)
        for i in range(2):
            rotation.rotate(self.history, _rec("deterministic", f"2026-07-05T18:0{i}:00Z"))
        with open(self.history) as f:
            self.assertEqual(json.dumps(json.load(f)["live"], indent=2), live_before)

    def test_empty_file_init_and_valid_json(self):
        rotation.rotate(self.history, _rec("deterministic", "2026-07-05T18:00:00Z"))
        with open(self.history) as f:
            data = json.load(f)  # valid JSON
        self.assertIn("deterministic", data)
        self.assertIn("live", data)

    def test_no_tmp_leftovers(self):
        rotation.rotate(self.history, _rec("deterministic", "2026-07-05T18:00:00Z"))
        self.assertEqual(glob.glob(os.path.join(self.td, "*.tmp")), [])

    def test_no_trailing_newline(self):
        rotation.rotate(self.history, _rec("deterministic", "2026-07-05T18:00:00Z"))
        with open(self.history, "rb") as f:
            self.assertNotEqual(f.read()[-1:], b"\n")

    def test_rotate_detail_writes_and_prunes(self):
        runs = os.path.join(self.td, "runs")
        for i in range(4):
            rotation.rotate_detail(runs, f"deterministic-{i}",
                                   _rec("deterministic", f"2026-07-05T18:0{i}:00Z", f"deterministic-{i}"))
        det_files = os.listdir(os.path.join(runs, "deterministic"))
        self.assertEqual(len(det_files), 3)

    def test_rotate_detail_live_does_not_touch_deterministic_dir(self):
        runs = os.path.join(self.td, "runs")
        rotation.rotate_detail(runs, "deterministic-a",
                               _rec("deterministic", "2026-07-05T18:00:00Z", "deterministic-a"))
        rotation.rotate_detail(runs, "live-a", _rec("live", "2026-07-01T00:00:00Z", "live-a"))
        self.assertTrue(os.path.exists(os.path.join(runs, "deterministic", "deterministic-a.json")))
        self.assertTrue(os.path.exists(os.path.join(runs, "live", "live-a.json")))


if __name__ == "__main__":
    unittest.main()
