"""A1 permission fix: both arms dispatch under bypassPermissions (never
permission-mode default), the deny-list settings file is threaded into BOTH argvs
when present and degrades silently when absent, and dispatch.PERMISSION_MODE is
mirrored verbatim in baseline.py with no cross-import.
"""

import inspect
import json
import os
import tempfile
import unittest

from benchmarklive import baseline
from benchmarklive.dispatch import (
    CAPTURE_JSON,
    CAPTURE_STREAM_JSON,
    PERMISSION_MODE,
    build_arm_stage_argv,
)


class PermissionMode(unittest.TestCase):
    def test_bypass_permissions_and_no_default_literal(self):
        argv = build_arm_stage_argv("PL", bind_agent=True)
        self.assertIn("--permission-mode", argv)
        self.assertEqual(argv[argv.index("--permission-mode") + 1], "bypassPermissions")
        self.assertNotIn("default", argv)

    def test_dispatch_baseline_literal_parity_without_cross_import(self):
        self.assertEqual(PERMISSION_MODE, baseline.PERMISSION_MODE)
        # baseline keeps its genlib-only boundary: no import line pulls dispatch/metrics.
        import_lines = [ln for ln in inspect.getsource(baseline).splitlines()
                        if ln.startswith(("import ", "from "))]
        for ln in import_lines:
            self.assertNotIn("dispatch", ln)
            self.assertNotIn("metrics", ln)

    def test_bound_and_bare_argv_identical_except_agent(self):
        bound = build_arm_stage_argv("PL", bind_agent=True)
        bare = build_arm_stage_argv("PL", bind_agent=False)
        self.assertEqual([a for a in bound if a not in ("--agent", "igrsoft:product-manager")], bare)


class SettingsThreading(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="perm-")
        self.settings = os.path.join(self.tmp, "benchmark-settings.json")

    def test_absent_settings_degrades_silently(self):
        argv = build_arm_stage_argv("PL", settings_path=self.settings)
        self.assertNotIn("--settings", argv)

    def test_present_settings_threaded_into_both_arms(self):
        with open(self.settings, "w", encoding="utf-8") as f:
            f.write("{}")
        for bind in (True, False):
            argv = build_arm_stage_argv("PL", bind_agent=bind, settings_path=self.settings)
            self.assertIn("--settings", argv)
            self.assertEqual(argv[argv.index("--settings") + 1], self.settings)

    def test_stream_json_keeps_verbose_with_settings(self):
        with open(self.settings, "w", encoding="utf-8") as f:
            f.write("{}")
        argv = build_arm_stage_argv("PL", capture_mode=CAPTURE_STREAM_JSON, settings_path=self.settings)
        self.assertIn("--verbose", argv)
        argv_json = build_arm_stage_argv("PL", capture_mode=CAPTURE_JSON, settings_path=self.settings)
        self.assertNotIn("--verbose", argv_json)


class DenyListContent(unittest.TestCase):
    def test_committed_deny_list_covers_spend_and_network(self):
        harness = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        benchmark_dir = os.path.dirname(harness)
        path = os.path.join(benchmark_dir, "live", "settings", "benchmark-settings.json")
        with open(path, encoding="utf-8") as f:
            deny = json.load(f)["permissions"]["deny"]
        blob = " ".join(deny)
        for token in ("git push", "gh", "curl", "wget", "WebFetch", "WebSearch"):
            self.assertIn(token, blob, f"deny-list missing {token!r}")


if __name__ == "__main__":
    unittest.main()
