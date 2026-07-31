"""A1 permission fix + SR-M1 fail-closed: both arms dispatch under bypassPermissions
(never permission-mode default), the deny-list settings file is threaded into BOTH
argvs when present, and — because headless has no interactive guardrail — a MISSING
settings file fails closed (BenchmarkSettingsMissing) BEFORE any dispatch instead of
silently dropping the deny-list. dispatch.PERMISSION_MODE is mirrored verbatim in
baseline.py with no cross-import.
"""

import inspect
import json
import os
import shutil
import tempfile
import unittest

from benchmarklive import baseline
from benchmarklive.dispatch import (
    CAPTURE_JSON,
    CAPTURE_STREAM_JSON,
    PERMISSION_MODE,
    BenchmarkSettingsMissing,
    build_arm_stage_argv,
    dispatch,
    require_settings,
)

import sys as _sys
_sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # _helpers under any runner
from _helpers import (  # noqa: E402 — path shim must precede import
    TripwireDispatcher,
    fake_estimate_runner,
    make_live_sandbox,
    stub_git_sha,
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
        self.assertEqual([a for a in bound if a not in ("--agent", "company-workflow:product-manager")], bare)


class SettingsThreading(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="perm-")
        self.settings = os.path.join(self.tmp, "benchmark-settings.json")

    def test_builder_is_bytestable_when_settings_absent(self):
        # The low-level argv builder stays byte-stable (no --settings) for callers
        # that pass no path; fail-closed enforcement is dispatch-level, not here.
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


class FailClosed(unittest.TestCase):
    """SR-M1: a missing deny-list under bypassPermissions must raise, not fail open."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="failclosed-")
        self.settings = os.path.join(self.tmp, "benchmark-settings.json")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_require_settings_raises_when_missing_under_bypass(self):
        with self.assertRaises(BenchmarkSettingsMissing) as ctx:
            require_settings(self.settings)
        self.assertIn(self.settings, str(ctx.exception))  # actionable: names the path

    def test_require_settings_ok_when_present(self):
        with open(self.settings, "w", encoding="utf-8") as f:
            f.write("{}")
        self.assertIsNone(require_settings(self.settings))  # no raise

    def test_require_settings_ignores_non_bypass_mode(self):
        # Other modes carry their own guardrail; the fail-closed check is scoped
        # strictly to bypassPermissions and must not fire for them.
        self.assertIsNone(require_settings(self.settings, permission_mode="default"))

    def test_dispatch_fails_closed_before_any_dispatch(self):
        sb = make_live_sandbox(self.tmp)
        os.remove(os.path.join(sb.benchmark_dir, "live", "settings", "benchmark-settings.json"))
        # TripwireDispatcher raises AssertionError if ANY stage is dispatched; the
        # guard must raise BenchmarkSettingsMissing first, proving pre-dispatch order.
        with self.assertRaises(BenchmarkSettingsMissing):
            dispatch(
                workdir=sb.run_id, budget=100.0, record_path=sb.record_path,
                benchmark_dir=sb.benchmark_dir, dispatcher=TripwireDispatcher(),
                env={"ANTHROPIC_API_KEY": "k"}, estimate_runner=fake_estimate_runner(0.001),
                stages=["PL"], git_sha_runner=stub_git_sha)


if __name__ == "__main__":
    unittest.main()
