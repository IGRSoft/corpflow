"""Held-out oracle: scoring arithmetic and build/crash handling against a fake
runner, plus two Swift-gated proofs — the reference implementation scores a clean
sweep, and the committed goldens still match what it actually emits.
"""

import contextlib
import json
import os
import shutil
import subprocess
import tempfile
import unittest

from benchmarkkit import oracle
from benchmarkkit.genlib import Subprocess
from benchmarklive.baseline import AppMeasure
from benchmarklive.dispatch import _arm_verdict


@contextlib.contextmanager
def _tmpdir():
    tmp = tempfile.mkdtemp(prefix="oracle-")
    try:
        yield os.path.join(tmp, "app")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

_HARNESS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_TEMPLATE = os.path.join(os.path.dirname(_HARNESS), "ttt-template")
_CASES = os.path.join(os.path.dirname(_HARNESS), "oracle", "cases.json")


def _swift_toolchain_usable():
    if not shutil.which("swift"):
        return False
    try:
        return subprocess.run(["swift", "--version"], capture_output=True,
                              timeout=120).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


class FakeRunner:
    """Answers `swift build` and `--show-bin-path`, then replays per-case results."""

    def __init__(self, builds=True, results=None, bin_dir="/tmp/fake-bin"):
        self.builds = builds
        self.results = results or {}
        self.bin_dir = bin_dir
        self.calls = []

    def run(self, argv, cwd=None, input=None, env=None, timeout=None):
        self.calls.append(argv)
        if argv[0] == "swift":
            if not self.builds:
                return Subprocess(1, "", "build failed")
            if "--show-bin-path" in argv:
                return Subprocess(0, self.bin_dir + "\n", "")
            return Subprocess(0, "", "")
        moves = argv[argv.index("--moves") + 1] if "--moves" in argv else ""
        exit_code, stdout = self.results.get(moves, (0, ""))
        return Subprocess(exit_code, stdout, "")


def _case(case_id, moves, exit_code, stdout):
    return {"id": case_id, "description": case_id, "args": ["--moves", moves],
            "expect": {"exit_code": exit_code, "stdout": stdout}}


class Scoring(unittest.TestCase):
    def setUp(self):
        self.cases = [_case("a", "0", 0, "board-a\n"), _case("b", "1", 0, "board-b\n"),
                      _case("c", "9", 1, "")]

    def _grade(self, runner, tmp):
        """Materializes the package + product files `build_arm` probes for on disk."""
        os.makedirs(tmp, exist_ok=True)
        open(os.path.join(tmp, "Package.swift"), "w").close()
        bin_dir = os.path.join(tmp, "bin")
        os.makedirs(bin_dir, exist_ok=True)
        open(os.path.join(bin_dir, "tictactoe"), "w").close()
        runner.bin_dir = bin_dir
        return oracle.grade(tmp, cases=self.cases, runner=runner)

    def test_full_conformance(self):
        runner = FakeRunner(results={"0": (0, "board-a\n"), "1": (0, "board-b\n"), "9": (1, "")})
        with _tmpdir() as tmp:
            r = self._grade(runner, tmp)
        self.assertTrue(r.built)
        self.assertEqual((r.cases_passed, r.cases_total, r.pass_rate), (3, 3, 1.0))
        self.assertEqual(r.failures, [])

    def test_wrong_stdout_is_a_failure_naming_the_case(self):
        runner = FakeRunner(results={"0": (0, "WRONG\n"), "1": (0, "board-b\n"), "9": (1, "")})
        with _tmpdir() as tmp:
            r = self._grade(runner, tmp)
        self.assertEqual(r.cases_passed, 2)
        self.assertEqual([(f.case_id, f.reason) for f in r.failures], [("a", "stdout")])

    def test_wrong_exit_code_is_a_failure(self):
        runner = FakeRunner(results={"0": (0, "board-a\n"), "1": (0, "board-b\n"), "9": (0, "")})
        with _tmpdir() as tmp:
            r = self._grade(runner, tmp)
        self.assertEqual([(f.case_id, f.reason) for f in r.failures], [("c", "exit_code")])

    def test_crash_exit_code_is_a_failure_not_a_skip(self):
        runner = FakeRunner(results={"0": (139, ""), "1": (0, "board-b\n"), "9": (1, "")})
        with _tmpdir() as tmp:
            r = self._grade(runner, tmp)
        self.assertEqual(r.cases_passed, 2)
        self.assertEqual(r.cases_total, 3)

    def test_non_building_arm_scores_zero_and_is_not_built(self):
        with _tmpdir() as tmp:
            r = self._grade(FakeRunner(builds=False), tmp)
        self.assertFalse(r.built)
        self.assertEqual((r.cases_passed, r.pass_rate), (0, 0.0))
        self.assertEqual(r.cases_total, 3)  # total survives so the score stays comparable

    def test_missing_package_never_shells_out(self):
        with _tmpdir() as tmp:
            runner = FakeRunner()
            r = oracle.grade(tmp, cases=self.cases, runner=runner)
        self.assertFalse(r.built)
        self.assertEqual(runner.calls, [])


class CasesFile(unittest.TestCase):
    def test_covers_every_terminal_state_and_exit_code(self):
        cases = oracle.load_cases(_CASES)
        self.assertGreaterEqual(len(cases), 20)
        self.assertEqual(len({c["id"] for c in cases}), len(cases))

        results = {line.split("result: ")[1]
                   for c in cases for line in c["expect"]["stdout"].splitlines()
                   if line.startswith("result: ")}
        self.assertEqual(results, {"in_progress", "X_wins", "O_wins", "draw"})
        self.assertEqual({c["expect"]["exit_code"] for c in cases}, {0, 1, 2})


@unittest.skipUnless(_swift_toolchain_usable(), "working swift toolchain required (measurement instrument)")
class AgainstReferenceImplementation(unittest.TestCase):
    def test_reference_sweeps_its_own_goldens(self):
        r = oracle.grade(_TEMPLATE, cases=oracle.load_cases(_CASES))
        self.assertTrue(r.built)
        self.assertEqual(r.cases_passed, r.cases_total, [f.to_dict() for f in r.failures])

    def test_committed_goldens_match_regenerated_ones(self):
        cases = oracle.load_cases(_CASES)
        built, binary = oracle.build_arm(_TEMPLATE)
        self.assertTrue(built)
        try:
            regenerated = oracle.capture_goldens(binary, cases)
        finally:
            shutil.rmtree(os.path.join(_TEMPLATE, ".build"), ignore_errors=True)
        self.assertEqual(json.dumps(regenerated, sort_keys=True),
                         json.dumps(cases, sort_keys=True))


class ArmVerdict(unittest.TestCase):
    """The oracle, not the arm's self-written suite, decides pass_fail."""

    def _measure(self, self_graded, oracle_block):
        return AppMeasure(loc_produced=100, test_count=67, pass_fail=self_graded,
                          app_path="with", oracle=oracle_block)

    def _oracle(self, passed, total=20, built=True):
        return {"built": built, "cases_total": total, "cases_passed": passed,
                "pass_rate": round(passed / total, 4)}

    def test_oracle_overrides_a_passing_self_graded_suite(self):
        app = self._measure("pass", self._oracle(passed=17))
        self.assertEqual(_arm_verdict(app, partial=False)[0], "fail")

    def test_full_oracle_sweep_passes(self):
        app = self._measure("pass", self._oracle(passed=20))
        self.assertEqual(_arm_verdict(app, partial=False)[0], "pass")

    def test_non_building_arm_fails_even_with_green_self_tests(self):
        app = self._measure("pass", self._oracle(passed=0, built=False))
        self.assertEqual(_arm_verdict(app, partial=False)[0], "fail")

    def test_partial_run_fails_regardless_of_oracle(self):
        app = self._measure("pass", self._oracle(passed=20))
        self.assertEqual(_arm_verdict(app, partial=True)[0], "fail")

    def test_unmeasured_arm_is_never_green(self):
        verdict, loc, tests, path, oracle_block = _arm_verdict(None, partial=False)
        self.assertEqual(verdict, "fail")
        self.assertEqual((loc, tests, path, oracle_block), (0, 0, None, None))

    def test_records_without_an_oracle_keep_the_self_graded_verdict(self):
        app = self._measure("pass", None)
        self.assertEqual(_arm_verdict(app, partial=False)[0], "pass")


if __name__ == "__main__":
    unittest.main()
