"""Neither arm may read a plugin cache outside its own CLAUDE_CONFIG_DIR.

Detector tests run over NDJSON fixtures cut from a real python-2 stage capture; the
dispatch tests use fake dispatchers, so nothing here spends.
"""

import json
import os
import shutil
import tempfile
import unittest

from benchmarkkit import pairing
from benchmarklive import config_leak
from benchmarklive.dispatch import CAPTURE_STREAM_JSON, dispatch
from benchmarklive.stage_table import HARNESS_GENERATION, build_era

import sys as _sys
_sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _helpers import fake_estimate_runner, load_json, make_live_sandbox, single_object_usage, stub_git_sha

_ENV = {"ANTHROPIC_API_KEY": "k"}
_FIXTURES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")
_CONFIG = "/Users/operator/.claude-eval"
_REAL_RUN1_AR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "workdirs", "live-20260930T080425Z-89500e0", "captures", "with-AR.jsonl")


def fixture(name):
    with open(os.path.join(_FIXTURES, name), encoding="utf-8") as f:
        return f.read()


def tool_use_stream(*commands, parent=None):
    """One assistant event per Bash command, optionally as a sub-agent's."""
    return "\n".join(json.dumps({
        "type": "assistant", "parent_tool_use_id": parent,
        "message": {"content": [{"type": "tool_use", "name": "Bash", "input": {"command": c}}]},
    }) for c in commands)


class Detector(unittest.TestCase):
    def test_run1_ar_fixture_detects_the_user_cache_reads(self):
        self.assertEqual(config_leak.find_leaks(fixture("ar-config-leak.jsonl"), _CONFIG),
                         ["/Users/operator/.claude/plugins/cache/apple-developer"])

    def test_without_capture_is_clean(self):
        self.assertEqual(config_leak.find_leaks(fixture("without-clean.jsonl"), _CONFIG), [])

    @unittest.skipUnless(os.path.exists(_REAL_RUN1_AR), "run-1 capture is gitignored; absent in a clean clone")
    def test_real_run1_ar_capture_detects_the_1_32_0_reads(self):
        with open(_REAL_RUN1_AR, encoding="utf-8") as f:
            text = f.read()
        leaks = config_leak.find_leaks(text, os.path.expanduser("~/.claude-eval"))
        self.assertEqual(leaks, [os.path.expanduser("~/.claude/plugins/cache/apple-developer")])
        self.assertIn("apple-developer/1.32.0", text)

    def test_only_tool_inputs_count_never_tool_results(self):
        result_only = json.dumps({"type": "user", "message": {"content": [{
            "type": "tool_result", "tool_use_id": "t",
            "content": "/Users/operator/.claude/plugins/cache/apple-developer/x"}]}})
        self.assertEqual(config_leak.find_leaks(result_only, _CONFIG), [])

    def test_subagent_events_are_scanned(self):
        stream = tool_use_stream("cat /Users/operator/.claude/plugins/cache/m/p/1/F.md",
                                 parent="toolu_parent")
        self.assertEqual(config_leak.find_leaks(stream, _CONFIG),
                         ["/Users/operator/.claude/plugins/cache/m"])

    def test_the_arms_own_config_dir_is_not_a_leak(self):
        stream = tool_use_stream(f"cat {_CONFIG}/plugins/cache/apple-developer/apple-developer/1.31.0/x")
        self.assertEqual(config_leak.find_leaks(stream, _CONFIG), [])

    def test_a_sibling_dir_sharing_the_config_name_prefix_is_still_a_leak(self):
        stream = tool_use_stream("ls /Users/operator/.claude-eval-old/plugins/cache/m")
        self.assertEqual(config_leak.find_leaks(stream, _CONFIG),
                         ["/Users/operator/.claude-eval-old/plugins/cache/m"])

    def test_home_shorthands_expand_and_dedupe_with_the_absolute_form(self):
        stream = tool_use_stream("ls ~/.claude/plugins/cache/m",
                                 "ls $HOME/.claude/plugins/cache/m",
                                 "ls ${HOME}/.claude/plugins/cache/m",
                                 "ls /Users/operator/.claude/plugins/cache/m/p")
        self.assertEqual(config_leak.find_leaks(stream, _CONFIG, home="/Users/operator"),
                         ["/Users/operator/.claude/plugins/cache/m"])

    def test_marketplaces_dirs_count_and_assignments_are_seen(self):
        stream = tool_use_stream("P=/Users/operator/.claude/plugins/marketplaces/m; ls $P")
        self.assertEqual(config_leak.find_leaks(stream, _CONFIG),
                         ["/Users/operator/.claude/plugins/marketplaces/m"])

    def test_file_path_inputs_are_scanned_like_commands(self):
        event = json.dumps({"type": "assistant", "message": {"content": [{
            "type": "tool_use", "name": "Read",
            "input": {"file_path": "/Users/operator/.claude/plugins/cache/m/p/1/SKILL.md"}}]}})
        self.assertEqual(config_leak.find_leaks(event, _CONFIG),
                         ["/Users/operator/.claude/plugins/cache/m"])

    def test_a_relative_plugins_cache_fragment_is_not_a_leak(self):
        self.assertEqual(config_leak.find_leaks(tool_use_stream("ls vendor/plugins/cache/x"), _CONFIG), [])

    def test_distinct_and_sorted(self):
        stream = tool_use_stream("ls /a/plugins/cache/z", "ls /a/plugins/cache/b", "ls /a/plugins/cache/z")
        self.assertEqual(config_leak.find_leaks(stream, _CONFIG),
                         ["/a/plugins/cache/b", "/a/plugins/cache/z"])

    def test_garbage_lines_are_skipped(self):
        self.assertEqual(config_leak.find_leaks("not json\n[1]\n{}\n", _CONFIG), [])


class DispatchRefusesALeak(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="leak-")
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.sb = make_live_sandbox(self.tmp)
        self.tree = os.path.realpath(self.tmp)
        self.cfg = os.path.join(self.tmp, "cfg")

    def _stream(self, *commands):
        init = {"type": "system", "subtype": "init", "plugins": [
            {"name": "corpflow", "path": self.tree, "version": "1.0.0"}]}
        body = tool_use_stream(*commands, parent="toolu_p") if commands else ""
        return "\n".join(x for x in (json.dumps(init), body, single_object_usage()) if x)

    def _run(self, with_stdout, capture_mode=CAPTURE_STREAM_JSON, stages=("PL", "AR")):
        class Serving:
            calls = 0

            def run(self_inner, argv, prompt_text):
                self_inner.calls += 1
                if "--agent" in argv:
                    return with_stdout
                init = {"type": "system", "subtype": "init", "plugins": []}
                return json.dumps(init) + "\n" + single_object_usage()

        fake = Serving()
        warnings = []
        rc = dispatch(
            workdir=self.sb.run_id, budget=100.0, record_path=self.sb.record_path,
            benchmark_dir=self.sb.benchmark_dir, workdir_root=self.sb.workdir_root,
            dispatcher=fake, env=_ENV, estimate_runner=fake_estimate_runner(0.001),
            stages=list(stages), git_sha_runner=stub_git_sha, without_arm="real",
            capture_mode=capture_mode, stderr=warnings.append, config_dir=self.cfg)
        return rc, fake, warnings

    def test_a_leak_refuses_with_rc_5_after_one_with_stage_and_names_the_prefix(self):
        rc, fake, warnings = self._run(self._stream("ls /Users/operator/.claude/plugins/cache/apple-developer"))
        self.assertEqual(rc, 5)
        self.assertEqual(fake.calls, 3)  # WITHOUT PL+AR, then WITH PL only
        self.assertIn("/Users/operator/.claude/plugins/cache/apple-developer", "\n".join(warnings))

    def test_the_leak_is_stamped_in_the_partial_record(self):
        self._run(self._stream("ls /Users/operator/.claude/plugins/cache/apple-developer"))
        record = load_json(self.sb.record_path)
        self.assertEqual(record["era"]["config_leaks"]["with"],
                         ["/Users/operator/.claude/plugins/cache/apple-developer"])
        self.assertTrue(record["live_partial"])

    def test_a_clean_run_stamps_an_empty_list_per_arm(self):
        rc, _, _ = self._run(self._stream(f"ls {self.cfg}/plugins/cache/apple-developer"))
        self.assertEqual(rc, 0)
        self.assertEqual(load_json(self.sb.record_path)["era"]["config_leaks"],
                         {"with": [], "without": []})

    def test_a_leak_on_a_later_stage_is_caught(self):
        class Later:
            n = 0

            def run(inner, argv, prompt_text):
                if "--agent" not in argv:
                    return json.dumps({"type": "system", "subtype": "init", "plugins": []}) \
                        + "\n" + single_object_usage()
                inner.n += 1
                return self_outer._stream("ls /x/.claude/plugins/cache/m" if inner.n == 2 else "ls /tmp")

        self_outer = self
        warnings = []
        rc = dispatch(
            workdir=self.sb.run_id, budget=100.0, record_path=self.sb.record_path,
            benchmark_dir=self.sb.benchmark_dir, workdir_root=self.sb.workdir_root,
            dispatcher=Later(), env=_ENV, estimate_runner=fake_estimate_runner(0.001),
            stages=["PL", "AR"], git_sha_runner=stub_git_sha, without_arm="real",
            capture_mode=CAPTURE_STREAM_JSON, stderr=warnings.append, config_dir=self.cfg)
        self.assertEqual(rc, 5)
        self.assertIn("stage AR", "\n".join(warnings))

    def test_json_capture_stamps_no_guard_result(self):
        rc, _, _ = self._run(single_object_usage(), capture_mode="json")
        self.assertNotEqual(rc, 5)
        self.assertNotIn("config_leaks", load_json(self.sb.record_path)["era"])

    def _without_leaking(self, stages=("PL", "AR"), single_arm=False):
        class WithoutLeaks:
            calls = []

            def run(inner, argv, prompt_text):
                inner.calls.append("--agent" in argv)
                if "--agent" in argv:
                    return self_outer._stream("ls /tmp")
                init = {"type": "system", "subtype": "init", "plugins": []}
                return "\n".join([json.dumps(init),
                                  tool_use_stream("cat /Users/operator/.claude/plugins/cache/m/p/1/F.md",
                                                  parent="toolu_p"),
                                  single_object_usage()])

        self_outer = self
        fake = WithoutLeaks()
        fake.calls = []
        warnings = []
        rc = dispatch(
            workdir=self.sb.run_id, budget=100.0, record_path=self.sb.record_path,
            benchmark_dir=self.sb.benchmark_dir, workdir_root=self.sb.workdir_root,
            dispatcher=fake, env=_ENV, estimate_runner=fake_estimate_runner(0.001),
            stages=list(stages), git_sha_runner=stub_git_sha, without_arm="real",
            capture_mode=CAPTURE_STREAM_JSON, stderr=warnings.append, config_dir=self.cfg)
        return rc, fake, warnings

    def test_a_without_arm_leak_is_refused_with_rc_5_before_the_with_arm_runs(self):
        rc, fake, warnings = self._without_leaking()
        self.assertEqual(rc, 5)
        self.assertEqual(fake.calls, [False])  # one WITHOUT stage, no WITH dispatch
        message = "\n".join(warnings)
        self.assertIn("without arm", message)
        self.assertIn("/Users/operator/.claude/plugins/cache/m", message)

    def test_the_without_leak_is_stamped_under_its_own_arm(self):
        self._without_leaking()
        record = load_json(self.sb.record_path)
        self.assertEqual(record["era"]["config_leaks"],
                         {"without": ["/Users/operator/.claude/plugins/cache/m"]})
        self.assertTrue(record["live_partial"])

    def test_a_clean_without_arm_beside_a_leaking_with_arm_is_still_refused(self):
        rc, _, _ = self._run(self._stream("ls /Users/operator/.claude/plugins/cache/m"))
        self.assertEqual(rc, 5)
        self.assertEqual(load_json(self.sb.record_path)["era"]["config_leaks"],
                         {"with": ["/Users/operator/.claude/plugins/cache/m"], "without": []})


class EraStamp(unittest.TestCase):
    def test_build_era_omits_config_leaks_unless_the_guard_ran(self):
        self.assertNotIn("config_leaks", build_era())
        self.assertNotIn("config_leaks", build_era(config_leaks={}))
        self.assertEqual(build_era(config_leaks={"with": []})["config_leaks"], {"with": []})
        self.assertEqual(
            build_era(config_leaks={"without": ["/a/plugins/cache/m"], "with": []})["config_leaks"],
            {"with": [], "without": ["/a/plugins/cache/m"]})

    def test_config_leaks_is_arm_scoped_for_pairing(self):
        base = {"harness": HARNESS_GENERATION, "prompt_contract": "scripted-cli-v3", "model_pins": {}}
        with_era = dict(base, config_leaks={"with": []})
        self.assertIsNone(pairing._era_refusal(with_era, dict(base)))
        without_era = dict(base, config_leaks={"without": []})
        self.assertIsNone(pairing._era_refusal(with_era, without_era))

    def test_join_carries_both_arms_entries(self):
        base = {"harness": HARNESS_GENERATION, "prompt_contract": "scripted-cli-v3", "model_pins": {}}
        joined = pairing._join_era(dict(base, config_leaks={"with": []}),
                                   dict(base, config_leaks={"without": []}))
        self.assertEqual(joined["config_leaks"], {"with": [], "without": []})

    def test_harness_generation_is_python_3(self):
        self.assertEqual(HARNESS_GENERATION, "python-3")


if __name__ == "__main__":
    unittest.main()
