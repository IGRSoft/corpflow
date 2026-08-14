"""Black-box conformance grading of a generated arm's `tictactoe` executable.

The arm writes its own implementation AND its own tests, so its `swift test`
result grades nothing an evaluator controls. This module drives the arm's binary
through the scripted CLI contract published in the shared stage prompts and
scores it against goldens captured from `ttt-template`, the reference
implementation — a signal the arm cannot author.

Grades behaviour only: an arm may name its types anything as long as
`tictactoe --moves …` conforms. Pure, offline, stdlib-only, `benchmarkkit`-local
so `bench-deterministic` can link it without reaching the live world (AC-8).

Cases carry a tier, and the two answer different questions. `specified` cases
restate what the prompt enumerates, so every arm should clear them and the verdict
hangs on them alone. `implied` cases follow from the contract's rules without being
listed — a competent arm derives them, which is what makes them the tier that
actually separates arms. Scoring them is not a conformance claim, so they are
reported next to the verdict rather than folded into it.
"""

from __future__ import annotations

import hashlib
import json
import os
import shutil
from dataclasses import dataclass, field
from typing import Callable, Optional

from .genlib import Subprocess

# Cosmetic case keys, excluded from the case-set digest. An exclude-list rather than
# an include-list: a newly added scoring key is covered by default, and only a
# deliberate edit here can drop something out of the hash. Rewording a description
# must not manufacture a comparability refusal — a gate that fires on cosmetics is a
# gate that gets bypassed.
DIGEST_EXCLUDED_CASE_KEYS = frozenset({"description"})

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
class TierScore:
    total: int
    passed: int

    @property
    def pass_rate(self) -> float:
        return 0.0 if self.total == 0 else round(self.passed / self.total, 4)

    def to_dict(self) -> dict:
        return {"total": self.total, "passed": self.passed, "pass_rate": self.pass_rate}


def oracle_cases_digest(cases: list) -> str:
    """Identity of the case set a grade was produced against, as ``sha256:<64 hex>``.

    Takes the cases as an argument and never reads the default file, so the digest is
    always the identity of the set actually applied.
    """
    canonical = sorted(
        ({k: v for k, v in case.items() if k not in DIGEST_EXCLUDED_CASE_KEYS}
         for case in cases),
        key=lambda case: case.get("id") or "",
    )
    payload = json.dumps(canonical, sort_keys=True, separators=(",", ":"))
    return "sha256:" + hashlib.sha256(payload.encode("utf-8")).hexdigest()


@dataclass
class OracleResult:
    built: bool
    cases_total: int
    cases_passed: int
    failures: list = field(default_factory=list)
    tiers: dict = field(default_factory=dict)
    cases_digest: Optional[str] = None

    @property
    def pass_rate(self) -> float:
        if self.cases_total == 0:
            return 0.0
        return round(self.cases_passed / self.cases_total, 4)

    def tier_rate(self, tier: str) -> Optional[float]:
        score = self.tiers.get(tier)
        return None if score is None else score.pass_rate

    def to_dict(self) -> dict:
        out = {
            "built": self.built,
            "cases_total": self.cases_total,
            "cases_passed": self.cases_passed,
            "pass_rate": self.pass_rate,
        }
        # Omitted rather than empty when the case file carries no tiers, so a
        # record written against an untiered set keeps its previous shape.
        if self.tiers:
            out["tiers"] = {name: score.to_dict() for name, score in sorted(self.tiers.items())}
        # Emitted last and only when set, so hand-built results keep their byte shape.
        if self.cases_digest is not None:
            out["cases_digest"] = self.cases_digest
        return out


def load_cases(path: Optional[str] = None) -> list:
    with open(path or _DEFAULT_CASES, encoding="utf-8") as f:
        return json.load(f)["cases"]


def tier_scores(cases: list, failed_ids: set) -> dict:
    """Split ``cases`` into per-tier ``TierScore``s; untiered cases count nowhere."""
    tallies: dict = {}
    for case in cases:
        tier = case.get("tier")
        if tier is None:
            continue
        total, passed = tallies.get(tier, (0, 0))
        tallies[tier] = (total + 1, passed + (case["id"] not in failed_ids))
    return {name: TierScore(total=t, passed=p) for name, (t, p) in tallies.items()}


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
    # Stamped from the case list before it is known whether the arm built, so a
    # non-building arm still carries the identity of what it was graded against.
    digest = oracle_cases_digest(cases)
    try:
        built, binary = build_arm(app_dir, runner=runner)
        if not built:
            if warn is not None:
                warn(f"oracle: {app_dir} did not build a `tictactoe` product")
            return OracleResult(built=False, cases_total=len(cases), cases_passed=0,
                                tiers=tier_scores(cases, {c["id"] for c in cases}),
                                cases_digest=digest)
        passed, failures = run_cases(binary, cases, runner=runner)
        return OracleResult(built=True, cases_total=len(cases), cases_passed=passed,
                            failures=failures,
                            tiers=tier_scores(cases, {f.case_id for f in failures}),
                            cases_digest=digest)
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
        out = {
            "id": case["id"],
            "description": case["description"],
            "args": list(case["args"]),
            "expect": {"exit_code": observed.exit_code, "stdout": observed.stdout},
        }
        if case.get("tier") is not None:
            out["tier"] = case["tier"]
        captured.append(out)
    return captured
