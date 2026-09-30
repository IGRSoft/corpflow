"""The harness leaves the WITH arm's ledger as the orchestrator would before DV and QA.

Runner is a fake: no test here spawns state-patch.sh except the one gated on jq, which
drives the real script against a throwaway ledger. No LLM call, no spend.
"""

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from types import SimpleNamespace

from benchmarklive import ledger_seed
from benchmarklive.dispatch import dispatch

import sys as _sys
_sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _helpers import fake_estimate_runner, make_live_sandbox, stub_git_sha

_PLUGIN_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))))


class RecordingRunner:
    def __init__(self, exit_code=0):
        self.calls = []
        self.exit_code = exit_code

    def __call__(self, argv, env, cwd):
        self.calls.append(SimpleNamespace(argv=list(argv), env=env, cwd=cwd))
        return SimpleNamespace(exit_code=self.exit_code, stdout="", stderr="boom")

    def ops(self):
        return [c.argv[c.argv.index("--log") + 2:] for c in self.calls]


def write_ledger(arm_cwd, tasks=None, **top):
    os.makedirs(os.path.join(arm_cwd, ".context", "logs"), exist_ok=True)
    ledger = {"version": 2, "run_index": 0,
              "tasks": tasks if tasks is not None else {"PL0": {"status": "completed"}}}
    ledger.update(top)
    with open(os.path.join(arm_cwd, ".context", "state.json"), "w", encoding="utf-8") as f:
        json.dump(ledger, f)


class SeedStage(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="seed-")
        self.arm = os.path.join(self.tmp, "with")
        self.warnings = []
        self.runner = RecordingRunner()

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def seed(self, stage="DV"):
        return ledger_seed.seed_stage(stage, self.arm, "/plugin", self.warnings.append,
                                      runner=self.runner)

    def test_dv_gets_approval_row_and_in_progress_in_that_order(self):
        write_ledger(self.arm)
        done = self.seed("DV")
        self.assertEqual(done, ["PL0 approved=auto", "DV0 created", "DV0 in_progress"])
        ops = self.runner.ops()
        self.assertEqual(ops[0], ["--task-meta", "PL0", "--set", '{"approved":"auto"}'])
        self.assertEqual(ops[1][:3], ["--task-create", "DV0", "--metadata"])
        self.assertEqual(ops[2], ["--task-status", "DV0", "in_progress"])

    def test_every_call_names_state_and_log_explicitly_and_pins_context_dir(self):
        write_ledger(self.arm)
        self.seed("DV")
        for call in self.runner.calls:
            self.assertEqual(call.argv[:2], ["bash", "/plugin/skills/worktask/scripts/state-patch.sh"])
            self.assertEqual(call.argv[call.argv.index("--state") + 1],
                             os.path.join(self.arm, ".context", "state.json"))
            self.assertEqual(call.argv[call.argv.index("--log") + 1],
                             os.path.join(self.arm, ".context", "logs", "state-merge.log"))
            self.assertEqual(call.env["CONTEXT_DIR"], os.path.join(self.arm, ".context"))
            self.assertEqual(call.cwd, self.arm)

    def test_created_row_carries_every_key_task_create_requires(self):
        write_ledger(self.arm)
        self.seed("DV")
        metadata = json.loads(self.runner.ops()[1][3])
        for key in ("effort", "isolation", "base_ref", "requires_screenshots", "workspace_path"):
            self.assertIn(key, metadata)
        self.assertEqual(metadata["agent"], "corpflow:developer")
        self.assertEqual(metadata["stage"], "DV")
        self.assertEqual(metadata["artifact"], ".context/development-0.md")
        self.assertEqual(metadata["plan_file"], "planning-0.md")
        self.assertEqual(metadata["workspace_path"], os.path.realpath(self.arm))

    def test_run_wide_values_the_plan_stamped_are_propagated(self):
        write_ledger(self.arm, run_index=2, metadata={
            "base_ref": "develop", "requires_screenshots": False, "test_mode": "full"})
        self.seed("DV")
        metadata = json.loads(next(o for o in self.runner.ops() if o[0] == "--task-create")[3])
        self.assertEqual((metadata["base_ref"], metadata["requires_screenshots"],
                          metadata["test_mode"], metadata["run_index"]),
                         ("develop", False, "full", 2))
        self.assertEqual(metadata["artifact"], ".context/development-2.md")
        self.assertEqual(metadata["plan_file"], "planning-2.md")

    def test_qa_row_is_seeded_the_same_way(self):
        write_ledger(self.arm)
        self.seed("QA")
        self.assertEqual(self.runner.ops()[1][:2], ["--task-create", "QA0"])
        self.assertEqual(self.runner.ops()[2], ["--task-status", "QA0", "in_progress"])
        self.assertEqual(json.loads(self.runner.ops()[1][3])["artifact"], ".context/testing-0.md")

    def test_existing_row_and_approval_are_left_alone(self):
        write_ledger(self.arm, tasks={
            "PL0": {"status": "completed", "metadata": {"approved": "user"}},
            "DV0": {"status": "in_progress"}})
        self.assertEqual(self.seed("DV"), [])
        self.assertEqual(self.runner.calls, [])

    def test_a_pending_row_is_only_claimed_not_recreated(self):
        write_ledger(self.arm, tasks={
            "PL0": {"status": "completed", "metadata": {"approved": "auto"}},
            "DV0": {"status": "pending"}})
        self.assertEqual(self.seed("DV"), ["DV0 in_progress"])

    def test_a_settled_row_is_not_reopened(self):
        write_ledger(self.arm, tasks={
            "PL0": {"metadata": {"approved": "user"}}, "DV0": {"status": "completed"}})
        self.assertEqual(self.seed("DV"), [])

    def test_a_human_approval_is_never_overwritten(self):
        write_ledger(self.arm, tasks={"PL0": {"metadata": {"approved": "user"}}})
        self.seed("DV")
        self.assertNotIn("--task-meta", [o[0] for o in self.runner.ops()])

    def test_missing_pl0_skips_the_approval_only(self):
        write_ledger(self.arm, tasks={})
        self.assertEqual(self.seed("DV"), ["DV0 created", "DV0 in_progress"])

    def test_stages_that_showed_no_failure_are_not_seeded(self):
        write_ledger(self.arm)
        for stage in ("PL", "AR", "TL", "DR", "SR", "DC", "FN", "ST"):
            self.assertEqual(self.seed(stage), [])
        self.assertEqual(self.runner.calls, [])

    def test_absent_ledger_warns_and_writes_nothing(self):
        self.assertEqual(self.seed("DV"), [])
        self.assertEqual(self.runner.calls, [])
        self.assertIn("no readable ledger", self.warnings[0])

    def test_unparseable_ledger_is_treated_as_absent(self):
        os.makedirs(os.path.join(self.arm, ".context"))
        with open(os.path.join(self.arm, ".context", "state.json"), "w") as f:
            f.write("{not json")
        self.assertEqual(self.seed("DV"), [])
        self.assertTrue(self.warnings)

    def test_a_failed_write_warns_and_does_not_raise(self):
        write_ledger(self.arm)
        self.runner.exit_code = 2
        self.assertEqual(self.seed("DV"), [])
        self.assertEqual(len(self.warnings), 3)
        self.assertIn("rc=2", self.warnings[0])


class DispatchSeedsWithArmOnly(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="seedd-")
        self.sb = make_live_sandbox(self.tmp)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _run(self, stages):
        write_ledger(os.path.join(self.sb.workdir_path, "with"))
        order = []
        runner = RecordingRunner()

        class Dispatcher:
            def run(_self, argv, prompt_text):
                order.append(("run", "with" if "--agent" in argv else "without", len(runner.calls)))
                return json.dumps({"type": "result", "usage": {"input_tokens": 1, "output_tokens": 1},
                                   "total_cost_usd": 0.01})

        dispatch(workdir=self.sb.run_id, budget=100.0, record_path=self.sb.record_path,
                 benchmark_dir=self.sb.benchmark_dir, dispatcher=Dispatcher(), env={"ANTHROPIC_API_KEY": "k"},
                 estimate_runner=fake_estimate_runner(0.001), stages=stages,
                 git_sha_runner=stub_git_sha, without_arm="real",
                 stderr=lambda _m: None, seed_runner=runner)
        return order, runner

    def test_seeding_precedes_the_dv_dispatch_and_skips_the_baseline(self):
        order, runner = self._run(["DV"])
        self.assertEqual(len(runner.calls), 3)
        # WITHOUT ran first with nothing seeded; WITH ran after all three writes.
        self.assertEqual(order, [("run", "without", 0), ("run", "with", 3)])

    def test_a_stage_outside_the_seeded_set_writes_nothing(self):
        _, runner = self._run(["PL"])
        self.assertEqual(runner.calls, [])


@unittest.skipUnless(shutil.which("jq"), "state-patch.sh needs jq")
class RealStatePatch(unittest.TestCase):
    """Drives the real scripts: the ledger a stage agent sees after seeding."""

    def test_seeded_ledger_passes_task_create_and_the_gate_reads_one_in_progress(self):
        tmp = tempfile.mkdtemp(prefix="seedr-")
        try:
            arm = os.path.realpath(tmp)
            os.makedirs(os.path.join(arm, ".context", "logs"))
            seed = subprocess.run(
                ["bash", os.path.join(_PLUGIN_ROOT, "skills", "worktask", "scripts", "seed-state.sh"),
                 "--worktask-id", "t1", "--goal", "g", "--context-dir",
                 os.path.join(arm, ".context"), "--workspace-path", arm],
                capture_output=True, text=True)
            self.assertEqual(seed.returncode, 0, seed.stderr)
            warnings = []
            done = ledger_seed.seed_stage("DV", arm, _PLUGIN_ROOT, warnings.append)
            self.assertEqual((done, warnings),
                             (["PL0 approved=auto", "DV0 created", "DV0 in_progress"], []))
            with open(os.path.join(arm, ".context", "state.json"), encoding="utf-8") as f:
                tasks = json.load(f)["tasks"]
            self.assertEqual(tasks["PL0"]["metadata"]["approved"], "auto")
            self.assertEqual(tasks["DV0"]["status"], "in_progress")
            self.assertEqual(tasks["DV0"]["metadata"]["workspace_path"], arm)
            # A second seed is a no-op.
            self.assertEqual(ledger_seed.seed_stage("DV", arm, _PLUGIN_ROOT, warnings.append), [])
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
