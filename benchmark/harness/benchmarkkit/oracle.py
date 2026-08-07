"""Black-box conformance grading of a generated arm's `tictactoe` executable.

The arm writes its own implementation AND its own tests, so its `swift test`
result grades nothing an evaluator controls. This module drives the arm's binary
through the scripted CLI contract published in the shared stage prompts and
scores it against goldens captured from `ttt-template`, the reference
implementation — a signal the arm cannot author.

Grades behaviour only: an arm may name its types anything as long as
`tictactoe --moves …` conforms. Pure, offline, stdlib-only, `benchmarkkit`-local
so `bench-deterministic` can link it without reaching the live world (AC-8).
"""

from __future__ import annotations

import json
import os
import shutil
from dataclasses import dataclass, field
from typing import Callable, Optional

from .genlib import Subprocess

# A conforming binary exits 0 (played), 1 (invalid move), or 2 (malformed argv).
# Anything else is a crash, and a crash is a failed case, never a skipped one.
BUILD_TIMEOUT_S = 600.0
CASE_TIMEOUT_S = 30.0

_DEFAULT_CASES = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "oracle", "cases.json")


@dataclass
class CaseFailure:
    case_id: str
    reason: str
    expected: str
    actual: str

    def to_dict(self) -> dict:
        return {"case_id": self.case_id, "reason": self.reason,
                "expected": self.expected, "actual": self.actual}


@dataclass
class OracleResult:
    built: bool
    cases_total: int
    cases_passed: int
    failures: list = field(default_factory=list)

    @property
    def pass_rate(self) -> float:
        if self.cases_total == 0:
            return 0.0
        return round(self.cases_passed / self.cases_total, 4)

    def to_dict(self) -> dict:
        return {
            "built": self.built,
            "cases_total": self.cases_total,
            "cases_passed": self.cases_passed,
            "pass_rate": self.pass_rate,
        }


def load_cases(path: Optional[str] = None) -> list:
    with open(path or _DEFAULT_CASES, encoding="utf-8") as f:
        return json.load(f)["cases"]


def build_arm(app_dir: str, runner=Subprocess) -> tuple:
    """Release-build the arm and locate its `tictactoe` product.

    Returns ``(built, binary_path)``; ``binary_path`` is None when the arm does
    not build or ships no such executable.
    """
    if not os.path.exists(os.path.join(app_dir, "Package.swift")):
        return False, None
    build = runner.run(["swift", "build", "-c", "release", "--package-path", app_dir],
                       cwd=app_dir, timeout=BUILD_TIMEOUT_S)
    if build.exit_code != 0:
        return False, None
    where = runner.run(["swift", "build", "-c", "release", "--package-path", app_dir,
                        "--show-bin-path"], cwd=app_dir, timeout=BUILD_TIMEOUT_S)
    if where.exit_code != 0:
        return False, None
    binary = os.path.join(where.stdout.strip(), "tictactoe")
    if not os.path.exists(binary):
        return False, None
    return True, binary


def _argv(binary: str, case: dict) -> list:
    return [binary] + list(case["args"])


def _compare(case: dict, observed: Subprocess) -> Optional[CaseFailure]:
    expected = case["expect"]
    if observed.exit_code != expected["exit_code"]:
        return CaseFailure(case["id"], "exit_code",
                           str(expected["exit_code"]), str(observed.exit_code))
    if observed.stdout != expected["stdout"]:
        return CaseFailure(case["id"], "stdout", expected["stdout"], observed.stdout)
    return None


def run_cases(binary: str, cases: list, runner=Subprocess) -> tuple:
    """Score ``binary`` against ``cases``. Returns ``(passed, failures)``."""
    passed = 0
    failures = []
    for case in cases:
        observed = runner.run(_argv(binary, case), timeout=CASE_TIMEOUT_S)
        failure = _compare(case, observed)
        if failure is None:
            passed += 1
        else:
            failures.append(failure)
    return passed, failures


def grade(app_dir: str, cases: Optional[list] = None, runner=Subprocess,
          warn: Optional[Callable] = None) -> OracleResult:
    """Build and score one arm. A non-building arm scores 0, never `built=True`.

    Sweeps ``<app_dir>/.build`` on every exit path (OI-1), so grading leaves the
    arm's inspectable source behind without its build tree.
    """
    cases = cases if cases is not None else load_cases()
    try:
        built, binary = build_arm(app_dir, runner=runner)
        if not built:
            if warn is not None:
                warn(f"oracle: {app_dir} did not build a `tictactoe` product")
            return OracleResult(built=False, cases_total=len(cases), cases_passed=0)
        passed, failures = run_cases(binary, cases, runner=runner)
        return OracleResult(built=True, cases_total=len(cases), cases_passed=passed,
                            failures=failures)
    finally:
        shutil.rmtree(os.path.join(app_dir, ".build"), ignore_errors=True)


def capture_goldens(binary: str, cases: list, runner=Subprocess) -> list:
    """Re-derive every case's `expect` by running the reference implementation.

    Goldens are only ever generated this way — a hand-written expectation would
    encode what someone believed the reference does rather than what it does.
    """
    captured = []
    for case in cases:
        observed = runner.run(_argv(binary, case), timeout=CASE_TIMEOUT_S)
        captured.append({
            "id": case["id"],
            "description": case["description"],
            "args": list(case["args"]),
            "expect": {"exit_code": observed.exit_code, "stdout": observed.stdout},
        })
    return captured
