"""The harness leaves the WITH arm's ledger as the orchestrator would before DV and QA.

Runner is a fake: no test here spawns state-patch.sh except the one gated on jq, which
drives the real script against a throwaway ledger. No LLM call, no spend.
"""

import json
import os
import shutil
import tempfile
import unittest
from types import SimpleNamespace

from benchmarklive import ledger_seed
from benchmarklive.dispatch import dispatch

import sys as _sys
_sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _helpers import fake_estimate_runner, make_live_sandbox, scrub_env, stub_git_sha

_PLUGIN_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))))


class RecordingRunner:
    def __init__(self, exit_code=0):
        self.calls = []
        self.exit_code = exit_code

    def __call__(self, argv, env, cwd):
        self.calls.append(SimpleNamespace(argv=list(argv), env=scrub_env(env), cwd=cwd))
        return SimpleNamespace(exit_code=self.exit_code, stdout="", stderr="boom")

    def ops(self):
        """The state-patch operations, leaving out any seed-state.sh call."""
        return [c.argv[c.argv.index("--log") + 2:] for c in self.calls if "--log" in c.argv]

    def seeds(self):
        return [c for c in self.calls if c.argv[1].endswith("seed-state.sh")]


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


    def test_an_open_pl0_is_closed_before_the_stage_is_claimed(self):
        write_ledger(self.arm, tasks={"PL0": {"status": "in_progress"}})
        done = self.seed("DV")
        self.assertEqual(done, ["PL0 completed", "PL0 approved=auto", "DV0 created",
                                "DV0 in_progress"])
        self.assertEqual(self.runner.ops()[0], ["--task-status", "PL0", "completed"])


class SeedRun(unittest.TestCase):
    """The WITH arm's ledger is seeded by the production script, with explicit paths."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="seedrun-")
        self.arm = os.path.join(self.tmp, "with")
        os.makedirs(self.arm)
        self.runner = RecordingRunner()

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def seed(self, goal="build it"):
        return ledger_seed.seed_run(self.arm, "/plugin", "live-x", goal, runner=self.runner)

    def test_invokes_seed_state_with_explicit_paths_and_the_run_identity(self):
        self.assertEqual(self.seed(), "seeded")
        (call,) = self.runner.calls
        self.assertEqual(call.argv, [
            "bash", "/plugin/skills/worktask/scripts/seed-state.sh",
            "--worktask-id", "live-x", "--goal", "build it",
            "--context-dir", os.path.join(self.arm, ".context"),
            "--workspace-path", os.path.realpath(self.arm)])
        self.assertEqual(call.env["CONTEXT_DIR"], os.path.join(self.arm, ".context"))
        self.assertEqual(call.cwd, self.arm)

    def test_creates_the_context_folders_worktask_step_3_makes(self):
        self.seed()
        for sub in ("designs", "images", "errors", "logs"):
            self.assertTrue(os.path.isdir(os.path.join(self.arm, ".context", sub)), sub)

    def test_an_existing_ledger_is_accepted_not_reseeded(self):
        self.runner.exit_code = 3
        self.assertEqual(self.seed(), "exists")

    def test_any_other_exit_refuses_with_the_code_and_stderr(self):
        for rc in (1, 2, 4):
            self.runner.exit_code = rc
            with self.assertRaises(ledger_seed.LedgerSeedError) as ctx:
                self.seed()
            self.assertIn(f"rc={rc}", str(ctx.exception))
            self.assertIn("boom", str(ctx.exception))

    def test_an_empty_goal_is_refused_before_the_script_runs(self):
        with self.assertRaises(ledger_seed.LedgerSeedError):
            self.seed(goal="")
        self.assertEqual(self.runner.calls, [])


class GoalFromPrompt(unittest.TestCase):
    def test_takes_the_task_paragraph_on_one_line(self):
        text = ("You are the PL stage.\n\nTASK: Write a PRD for a small app\n"
                "with four screens.\n- Stack: Swift\nWrite the plan.\n")
        self.assertEqual(ledger_seed.goal_from_prompt(text),
                         "Write a PRD for a small app with four screens.")

    def test_without_a_task_marker_the_whole_paragraph_is_the_goal(self):
        self.assertEqual(ledger_seed.goal_from_prompt("[5] task body for pl\n"),
                         "[5] task body for pl")

    def test_the_real_pl_prompt_yields_its_task_sentence(self):
        path = os.path.join(_PLUGIN_ROOT, "benchmark", "live", "prompts", "pl.txt")
        with open(path, encoding="utf-8") as f:
            goal = ledger_seed.goal_from_prompt(f.read())
        self.assertTrue(goal.startswith("Write a PRD"), goal)
        self.assertNotIn("\n", goal)
        self.assertNotIn("- Stack", goal)


class DispatchSeedsWithArmOnly(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="seedd-")
        self.sb = make_live_sandbox(self.tmp)
        self.warnings = []

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _run(self, stages, runner=None, dispatcher=None, without_arm="real", selection=None):
        write_ledger(self.sb.arm_dir("with"))
        order = []
        runner = runner or RecordingRunner()

        class Dispatcher:
            def run(_self, argv, prompt_text):
                order.append(("run", "with" if "--agent" in argv else "without", len(runner.calls)))
                return json.dumps({"type": "result", "usage": {"input_tokens": 1, "output_tokens": 1},
                                   "total_cost_usd": 0.01})

        dispatch(workdir=self.sb.run_id, budget=100.0, record_path=self.sb.record_path,
                 benchmark_dir=self.sb.benchmark_dir, workdir_root=self.sb.workdir_root,
                 dispatcher=dispatcher or Dispatcher(), env={"ANTHROPIC_API_KEY": "k"},
                 estimate_runner=fake_estimate_runner(0.001), stages=stages,
                 git_sha_runner=stub_git_sha, without_arm=without_arm, selection=selection,
                 stderr=self.warnings.append, seed_runner=runner)
        return order, runner

    def test_the_run_is_seeded_once_before_any_dispatch_then_dv_is_seeded(self):
        order, runner = self._run(["DV"])
        self.assertEqual(len(runner.seeds()), 1)
        self.assertEqual(len(runner.calls), 4)
        # seed-state.sh ran before WITHOUT's dispatch; the DV writes before WITH's.
        self.assertEqual(order, [("run", "without", 1), ("run", "with", 4)])

    def test_the_seed_names_the_with_arm_the_run_id_and_the_prompt_goal(self):
        _, runner = self._run(["PL"])
        (seed,) = runner.seeds()
        self.assertEqual(os.path.realpath(seed.cwd), os.path.realpath(self.sb.arm_dir("with")))
        self.assertEqual(seed.argv[seed.argv.index("--worktask-id") + 1], self.sb.run_id)
        self.assertEqual(seed.argv[seed.argv.index("--goal") + 1], "[5] task body for pl")

    def test_a_stage_outside_the_seeded_set_seeds_the_run_only(self):
        _, runner = self._run(["PL"])
        self.assertEqual(len(runner.calls), 1)
        self.assertEqual(runner.ops(), [])

    def test_the_without_arm_never_gets_a_ledger(self):
        _, runner = self._run(["PL", "DV"])
        without = os.path.realpath(self.sb.arm_dir("without"))
        self.assertNotIn(without, [os.path.realpath(c.cwd) for c in runner.calls])

    def test_a_without_only_run_seeds_nothing(self):
        from benchmarklive import baseline
        selection = baseline.resolve_arm_selection("without", None, None)
        _, runner = self._run(["PL"], selection=selection, without_arm=None)
        self.assertEqual(runner.calls, [])

    def test_a_failed_seed_refuses_the_run_before_any_dispatch(self):
        from _helpers import TripwireDispatcher
        runner = RecordingRunner(exit_code=1)
        rc = None
        write_ledger(self.sb.arm_dir("with"))
        rc = dispatch(workdir=self.sb.run_id, budget=100.0, record_path=self.sb.record_path,
                      benchmark_dir=self.sb.benchmark_dir, workdir_root=self.sb.workdir_root,
                      dispatcher=TripwireDispatcher(), env={"ANTHROPIC_API_KEY": "k"},
                      estimate_runner=fake_estimate_runner(0.001), stages=["PL"],
                      git_sha_runner=stub_git_sha, without_arm="real",
                      stderr=self.warnings.append, seed_runner=runner)
        self.assertEqual(rc, 1)
        self.assertTrue(any("live run refused" in w and "rc=1" in w for w in self.warnings))
        self.assertFalse(os.path.exists(self.sb.record_path))


@unittest.skipUnless(shutil.which("jq"), "seed-state.sh and state-patch.sh need jq")
class RealSeed(unittest.TestCase):
    """Drives the real scripts: the ledger a stage agent sees after seeding."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="seedr-")
        self.arm = os.path.realpath(self.tmp)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def read(self):
        with open(os.path.join(self.arm, ".context", "state.json"), encoding="utf-8") as f:
            return json.load(f)

    def test_seed_run_writes_the_production_ledger_and_is_idempotent(self):
        self.assertEqual(ledger_seed.seed_run(
            self.arm, _PLUGIN_ROOT, "live-x", "  Build\ta game\t"), "seeded")
        ledger = self.read()
        self.assertEqual(ledger["worktask_id"], "live-x")
        self.assertEqual(ledger["facts"]["goal"], "Build a game")
        self.assertEqual(ledger["metadata"]["workspace_path"], self.arm)
        self.assertEqual(ledger["tasks"], {"PL0": {"status": "in_progress"}})
        before = open(os.path.join(self.arm, ".context", "state.json"), "rb").read()
        self.assertEqual(ledger_seed.seed_run(self.arm, _PLUGIN_ROOT, "live-x", "g"), "exists")
        self.assertEqual(open(os.path.join(self.arm, ".context", "state.json"), "rb").read(),
                         before)

    def test_a_seed_the_script_refuses_raises(self):
        with self.assertRaises(ledger_seed.LedgerSeedError) as ctx:
            ledger_seed.seed_run(self.arm, _PLUGIN_ROOT, "bad id!", "g")
        self.assertIn("rc=2", str(ctx.exception))

    def test_seeded_ledger_passes_task_create_and_the_gate_reads_one_in_progress(self):
        ledger_seed.seed_run(self.arm, _PLUGIN_ROOT, "live-x", "g")
        warnings = []
        done = ledger_seed.seed_stage("DV", self.arm, _PLUGIN_ROOT, warnings.append)
        self.assertEqual((done, warnings), (
            ["PL0 completed", "PL0 approved=auto", "DV0 created", "DV0 in_progress"], []))
        tasks = self.read()["tasks"]
        self.assertEqual(tasks["PL0"]["status"], "completed")
        self.assertEqual(tasks["PL0"]["metadata"]["approved"], "auto")
        self.assertEqual(tasks["DV0"]["status"], "in_progress")
        self.assertEqual(tasks["DV0"]["metadata"]["workspace_path"], self.arm)
        self.assertEqual([t for t, row in tasks.items() if row["status"] == "in_progress"],
                         ["DV0"])
        # A second seed is a no-op.
        self.assertEqual(ledger_seed.seed_stage("DV", self.arm, _PLUGIN_ROOT, warnings.append), [])


if __name__ == "__main__":
    unittest.main()
