"""Arms run outside the repo, each in a git repo of its own.

Real ``git`` runs against throwaway directories (it spends nothing); dispatch is fake.
"""

import os
import shutil
import subprocess
import tempfile
import unittest
from types import SimpleNamespace

from benchmarklive import workdirs
from benchmarklive.dispatch import dispatch

import sys as _sys
_sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _helpers import (
    RecordingFakeDispatcher,
    fake_estimate_runner,
    load_json,
    make_live_sandbox,
    stub_git_sha,
)

_ENV = {"ANTHROPIC_API_KEY": "k"}


def git(cwd, *args):
    return subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)


class ResolveWorkdirRoot(unittest.TestCase):
    def test_flag_beats_env_beats_default(self):
        env = {"BENCH_WORKDIR_ROOT": "/from/env", "TMPDIR": "/tmp-x"}
        self.assertEqual(workdirs.resolve_workdir_root("/from/flag", env),
                         os.path.realpath("/from/flag"))
        self.assertEqual(workdirs.resolve_workdir_root(None, env), os.path.realpath("/from/env"))

    def test_default_is_corpflow_bench_under_tmpdir(self):
        self.assertEqual(workdirs.resolve_workdir_root(None, {"TMPDIR": "/scratch/t/"}),
                         os.path.realpath("/scratch/t/corpflow-bench"))

    def test_default_falls_back_to_tmp_when_tmpdir_is_unset(self):
        saved = os.environ.pop("TMPDIR", None)
        try:
            self.assertEqual(workdirs.resolve_workdir_root(None, {}),
                             os.path.realpath("/tmp/corpflow-bench"))
        finally:
            if saved is not None:
                os.environ["TMPDIR"] = saved

    def test_root_is_symlink_resolved_so_it_matches_what_git_reports(self):
        with tempfile.TemporaryDirectory() as tmp:
            real = os.path.join(tmp, "real")
            os.makedirs(real)
            link = os.path.join(tmp, "link")
            os.symlink(real, link)
            self.assertEqual(workdirs.resolve_workdir_root(link, {}), os.path.realpath(real))


class InitArmRepo(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="wd-")
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)

    def test_arm_resolves_git_to_itself_even_when_nested_in_another_repo(self):
        outer = os.path.join(self.tmp, "outer")
        os.makedirs(outer)
        git(outer, "init", "-q")
        arm = os.path.join(outer, "workdirs", "run", "with")
        self.assertIsNone(workdirs.init_arm_repo(arm))
        top = git(arm, "rev-parse", "--show-toplevel").stdout.strip()
        self.assertEqual(os.path.realpath(top), os.path.realpath(arm))

    def test_tree_is_clean_with_a_resolvable_head_on_master(self):
        arm = os.path.join(self.tmp, "arm")
        self.assertIsNone(workdirs.init_arm_repo(arm))
        self.assertEqual(git(arm, "rev-parse", "--verify", "HEAD").returncode, 0)
        self.assertEqual(git(arm, "branch", "--show-current").stdout.strip(), "master")
        self.assertEqual(git(arm, "status", "--porcelain").stdout, "")

    def test_existing_repo_is_left_alone(self):
        arm = os.path.join(self.tmp, "arm")
        workdirs.init_arm_repo(arm)
        head = git(arm, "rev-parse", "HEAD").stdout
        self.assertIsNone(workdirs.init_arm_repo(arm))
        self.assertEqual(git(arm, "rev-parse", "HEAD").stdout, head)

    def test_a_failing_git_is_reported_not_raised(self):
        seen = []

        def failing(argv, cwd):
            seen.append(argv[0])
            return SimpleNamespace(exit_code=128, stderr="fatal: nope\n")

        problem = workdirs.init_arm_repo(os.path.join(self.tmp, "arm"), runner=failing)
        self.assertIn("rc=128", problem)
        self.assertEqual(seen, ["init"])  # stops at the first failing step


class LinkPersisted(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="wd-")
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.arm = os.path.join(self.tmp, "arms", "with")
        os.makedirs(self.arm)
        self.persist = os.path.join(self.tmp, "repo", "workdirs", "run")

    def test_links_the_arm_under_the_persisted_dir(self):
        self.assertIsNone(workdirs.link_persisted(self.persist, "with", self.arm))
        self.assertEqual(os.path.realpath(os.path.join(self.persist, "with")),
                         os.path.realpath(self.arm))

    def test_relinking_the_same_arm_is_a_no_op(self):
        workdirs.link_persisted(self.persist, "with", self.arm)
        self.assertIsNone(workdirs.link_persisted(self.persist, "with", self.arm))

    def test_an_existing_real_dir_is_never_replaced(self):
        os.makedirs(os.path.join(self.persist, "with"))
        self.assertIn("already exists", workdirs.link_persisted(self.persist, "with", self.arm))
        self.assertFalse(os.path.islink(os.path.join(self.persist, "with")))


class DispatchPlacesArmsOutsideTheRepo(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="wdd-")
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.sb = make_live_sandbox(self.tmp)

    def _run(self, **overrides):
        warnings = []
        kwargs = dict(
            workdir=self.sb.run_id, budget=100.0, record_path=self.sb.record_path,
            benchmark_dir=self.sb.benchmark_dir, workdir_root=self.sb.workdir_root,
            dispatcher=RecordingFakeDispatcher(), env=_ENV,
            estimate_runner=fake_estimate_runner(0.001), stages=["PL"],
            git_sha_runner=stub_git_sha, without_arm="real", stderr=warnings.append)
        kwargs.update(overrides)
        return dispatch(**kwargs), warnings

    def test_arm_dirs_are_under_the_root_not_the_benchmark_tree(self):
        self._run()
        for arm in ("with", "without"):
            self.assertTrue(os.path.isdir(os.path.join(self.sb.arm_dir(arm), ".context", "logs")))
            # The persisted entry is a link to the arm, never a second copy of it.
            self.assertTrue(os.path.islink(os.path.join(self.sb.workdir_path, arm)))

    def test_each_arm_is_its_own_git_repo(self):
        self._run()
        for arm in ("with", "without"):
            top = git(self.sb.arm_dir(arm), "rev-parse", "--show-toplevel").stdout.strip()
            self.assertEqual(os.path.realpath(top), os.path.realpath(self.sb.arm_dir(arm)))

    def test_the_root_is_not_inside_the_benchmark_tree(self):
        self._run()
        arm = os.path.realpath(self.sb.arm_dir("with"))
        self.assertFalse(arm.startswith(os.path.realpath(self.sb.benchmark_dir) + os.sep))

    def test_captures_and_arm_links_stay_under_the_persisted_workdir(self):
        self._run()
        self.assertTrue(os.path.isfile(os.path.join(self.sb.workdir_path, "captures", "with-PL.jsonl")))
        for arm in ("with", "without"):
            link = os.path.join(self.sb.workdir_path, arm)
            self.assertTrue(os.path.islink(link))
            self.assertEqual(os.path.realpath(link), os.path.realpath(self.sb.arm_dir(arm)))

    def test_recorded_app_path_stays_repo_relative(self):
        self._run()
        paths = load_json(self.sb.record_path)["paths"]
        self.assertEqual(paths["with"]["app_path"], f"benchmark/workdirs/{self.sb.run_id}/with")
        self.assertEqual(paths["without"]["app_path"], f"benchmark/workdirs/{self.sb.run_id}/without")

    def test_env_root_is_used_when_no_flag_is_given(self):
        root = os.path.join(self.tmp, "env-root")
        self._run(workdir_root=None, env=dict(_ENV, BENCH_WORKDIR_ROOT=root))
        self.assertTrue(os.path.isdir(os.path.join(os.path.realpath(root), self.sb.run_id, "with")))

    def test_a_failed_git_init_warns_and_the_run_continues(self):
        def failing(argv, cwd):
            return SimpleNamespace(exit_code=1, stderr="no git")

        rc, warnings = self._run(git_runner=failing)
        self.assertEqual(rc, 0)
        self.assertTrue(any("not its own git repo" in w for w in warnings))


if __name__ == "__main__":
    unittest.main()
