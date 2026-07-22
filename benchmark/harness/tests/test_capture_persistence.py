"""A3 capture persistence: persist_capture writes raw stdout to
captures/<arm>-<stage>.jsonl BEFORE parsing; captures_dir=None is a no-op;
over-cap payloads are truncated with a marker; a failing write never raises.
"""

import os
import shutil
import tempfile
import unittest

from benchmarklive import dispatch
from benchmarklive.dispatch import persist_capture


class PersistCapture(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="cap-")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_writes_raw_stdout_per_arm_stage(self):
        captures = os.path.join(self.tmp, "captures")
        persist_capture(captures, "with", "PL", '{"type":"result"}')
        persist_capture(captures, "without", "PL", "raw-without")
        with open(os.path.join(captures, "with-PL.jsonl"), encoding="utf-8") as f:
            self.assertEqual(f.read(), '{"type":"result"}')
        with open(os.path.join(captures, "without-PL.jsonl"), encoding="utf-8") as f:
            self.assertEqual(f.read(), "raw-without")

    def test_none_captures_dir_is_noop(self):
        # No exception, nothing written.
        persist_capture(None, "with", "PL", "x")

    def test_truncation_marker_over_cap(self):
        captures = os.path.join(self.tmp, "captures")
        orig = dispatch.CAPTURE_TRUNCATE_BYTES
        dispatch.CAPTURE_TRUNCATE_BYTES = 10
        try:
            persist_capture(captures, "with", "DR", "0123456789ABCDEF")
        finally:
            dispatch.CAPTURE_TRUNCATE_BYTES = orig
        with open(os.path.join(captures, "with-DR.jsonl"), encoding="utf-8") as f:
            body = f.read()
        self.assertTrue(body.startswith("0123456789"))
        self.assertIn("TRUNCATED", body)

    def test_write_failure_swallowed(self):
        # captures_dir collides with an existing file → makedirs raises, swallowed.
        clash = os.path.join(self.tmp, "clash")
        with open(clash, "w", encoding="utf-8") as f:
            f.write("x")
        persist_capture(os.path.join(clash, "sub"), "with", "PL", "data")  # no raise


if __name__ == "__main__":
    unittest.main()
