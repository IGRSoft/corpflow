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
from benchmarklive.dispatch import _arm_verdict, build_live_record


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


def _case(case_id, moves, exit_code, stdout, tier=None):
    case = {"id": case_id, "description": case_id, "args": ["--moves", moves],
            "expect": {"exit_code": exit_code, "stdout": stdout}}
    if tier is not None:
        case["tier"] = tier
    return case


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


class Tiers(unittest.TestCase):
    def setUp(self):
        self.cases = [_case("s1", "0", 0, "a\n", tier="specified"),
                      _case("s2", "1", 0, "b\n", tier="specified"),
                      _case("i1", "9", 1, "", tier="implied")]

    def _grade(self, runner, tmp):
        os.makedirs(tmp, exist_ok=True)
        open(os.path.join(tmp, "Package.swift"), "w").close()
        bin_dir = os.path.join(tmp, "bin")
        os.makedirs(bin_dir, exist_ok=True)
        open(os.path.join(bin_dir, "tictactoe"), "w").close()
        runner.bin_dir = bin_dir
        return oracle.grade(tmp, cases=self.cases, runner=runner)

    def test_tiers_are_scored_separately(self):
        # Conforms to everything it was told; misses the case it had to derive.
        runner = FakeRunner(results={"0": (0, "a\n"), "1": (0, "b\n"), "9": (0, "")})
        with _tmpdir() as tmp:
            r = self._grade(runner, tmp)
        self.assertEqual(r.tier_rate("specified"), 1.0)
        self.assertEqual(r.tier_rate("implied"), 0.0)
        self.assertEqual(r.to_dict()["tiers"]["implied"], {"total": 1, "passed": 0,
                                                           "pass_rate": 0.0})

    def test_non_building_arm_scores_zero_in_every_tier(self):
        with _tmpdir() as tmp:
            r = self._grade(FakeRunner(builds=False), tmp)
        self.assertEqual(r.tier_rate("specified"), 0.0)
        self.assertEqual(r.tier_rate("implied"), 0.0)

    def test_untiered_cases_emit_no_breakdown(self):
        self.cases = [_case("a", "0", 0, "a\n")]
        runner = FakeRunner(results={"0": (0, "a\n")})
        with _tmpdir() as tmp:
            r = self._grade(runner, tmp)
        self.assertNotIn("tiers", r.to_dict())


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

    def test_every_case_is_tiered_and_both_tiers_are_populated(self):
        # An untiered case would silently vanish from the breakdown the verdict reads.
        cases = oracle.load_cases(_CASES)
        tiers = [c.get("tier") for c in cases]
        self.assertNotIn(None, tiers)
        self.assertGreaterEqual(tiers.count("specified"), 20)
        self.assertGreaterEqual(tiers.count("implied"), 5)


@unittest.skipUnless(_swift_toolchain_usable(), "working swift toolchain required (measurement instrument)")
class AgainstReferenceImplementation(unittest.TestCase):
    def test_reference_sweeps_its_own_goldens(self):
        r = oracle.grade(_TEMPLATE, cases=oracle.load_cases(_CASES))
        self.assertTrue(r.built)
        self.assertEqual(r.cases_passed, r.cases_total, [f.to_dict() for f in r.failures])

    def test_implied_tier_separates_a_plausible_wrong_implementation(self):
        """The point of the implied tier: catch what full contract conformance misses.

        The mutant validates every listed move before honouring the early stop —
        a reading no line of the contract rules out. It clears the specified tier
        outright, so a set graded only on enumerated behaviour would call it
        perfect.
        """
        anchor = """    var state = board.state()
    for m in moves {
        if state != .inProgress {
            break
        }
        state = try board.play(m)
    }"""
        mutation = """    var state = board.state()
    for m in moves {
        if m < 0 || m >= Board.size {
            throw InvalidMove.outOfRange(m)
        }
        if try board.cell(m) != nil {
            throw InvalidMove.occupied(m)
        }
        if state != .inProgress {
            break
        }
        state = try board.play(m)
    }"""
        tmp = tempfile.mkdtemp(prefix="oracle-mutant-")
        try:
            app = os.path.join(tmp, "app")
            shutil.copytree(_TEMPLATE, app, ignore=shutil.ignore_patterns(".build"))
            main = os.path.join(app, "Sources", "tictactoe", "main.swift")
            with open(main, encoding="utf-8") as f:
                src = f.read()
            self.assertEqual(src.count(anchor), 1, "template drifted; re-derive the mutation")
            with open(main, "w", encoding="utf-8") as f:
                f.write(src.replace(anchor, mutation))
            r = oracle.grade(app, cases=oracle.load_cases(_CASES))
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

        self.assertTrue(r.built)
        self.assertEqual(r.tier_rate("specified"), 1.0,
                         [f.to_dict() for f in r.failures])
        self.assertLess(r.tier_rate("implied"), 1.0)

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

    def _tiered(self, specified, implied, spec_total=24, imp_total=6):
        total, passed = spec_total + imp_total, specified + implied
        block = self._oracle(passed=passed, total=total)
        block["tiers"] = {
            "specified": {"total": spec_total, "passed": specified,
                          "pass_rate": round(specified / spec_total, 4)},
            "implied": {"total": imp_total, "passed": implied,
                        "pass_rate": round(implied / imp_total, 4)},
        }
        return block

    def test_a_missed_implied_case_does_not_fail_the_arm(self):
        # The arm was never told this behaviour; it is measured, not enforced.
        app = self._measure("pass", self._tiered(specified=24, implied=3))
        self.assertEqual(_arm_verdict(app, partial=False)[0], "pass")

    def test_a_missed_specified_case_fails_the_arm(self):
        app = self._measure("pass", self._tiered(specified=23, implied=6))
        self.assertEqual(_arm_verdict(app, partial=False)[0], "fail")

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


class PairedVerdictSymmetry(unittest.TestCase):
    """Each arm is judged by its own degradation, never by the other arm's."""

    def _app(self):
        return AppMeasure(loc_produced=10, test_count=5, pass_fail="pass", app_path="x",
                          oracle={"built": True, "cases_total": 2, "cases_passed": 2,
                                  "pass_rate": 1.0})

    def _record(self, with_partial, without_partial):
        return build_live_record(
            "r", "t", "s", 1.0, [], 10, live_partial=with_partial or without_partial,
            with_app=self._app(), without_app=self._app(), without_usages=[],
            without_dispatched=10, without_partial=without_partial,
            with_partial=with_partial).to_dict()

    def test_without_breach_leaves_a_complete_with_arm_green(self):
        rec = self._record(with_partial=False, without_partial=True)
        self.assertEqual(rec["paths"]["with"]["pass_fail"], "pass")
        self.assertEqual(rec["paths"]["without"]["pass_fail"], "fail")

    def test_with_breach_leaves_a_complete_without_arm_green(self):
        rec = self._record(with_partial=True, without_partial=False)
        self.assertEqual(rec["paths"]["with"]["pass_fail"], "fail")
        self.assertEqual(rec["paths"]["without"]["pass_fail"], "pass")

    def test_omitted_with_partial_falls_back_to_the_record_flag(self):
        rec = build_live_record(
            "r", "t", "s", 1.0, [], 10, live_partial=True,
            with_app=self._app(), without_app=self._app(), without_usages=[],
            without_dispatched=10).to_dict()
        self.assertEqual(rec["paths"]["with"]["pass_fail"], "fail")


if __name__ == "__main__":
    unittest.main()
