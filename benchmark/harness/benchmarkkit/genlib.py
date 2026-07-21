"""Shared helpers for the two deterministic generators.

Locates the template, copies it into per-side workdirs (staged or single-shot),
runs the generated app's Swift Testing suite (REAL ``swift test`` — the retained
measurement instrument), counts REAL loc_produced (*.swift), and builds a
PathMetrics from measured values. Never imports benchmarklive.

OI-1: the nested ``swift test`` materializes a heavy ``.build/`` inside the app
dir; a ``finally`` sweeps exactly ``<app_dir>/.build`` on every exit path, scoped
so the caller's app copy / --workdir survive (R3).
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import time
from dataclasses import dataclass
from typing import Optional

from .metrics import PathMetrics, Tokens

_IGNORED_DIR_NAMES = {".build", ".swiftpm", "__pycache__"}


class Timer:
    """Monotonic wall-clock timer; ``elapsed`` is seconds since ``start()``."""

    def __init__(self) -> None:
        self._t0 = 0.0

    def start(self) -> None:
        self._t0 = time.monotonic()

    @property
    def elapsed(self) -> float:
        return time.monotonic() - self._t0


@dataclass
class Subprocess:
    exit_code: int
    stdout: str
    stderr: str

    @staticmethod
    def run(argv: list, cwd: Optional[str] = None, input: Optional[str] = None,
            env: Optional[dict] = None) -> "Subprocess":
        try:
            # No input → stdin is /dev/null (never inherit the caller's stdin; a
            # nested/headless child can block forever on an inherited tty).
            r = subprocess.run(
                argv,
                cwd=cwd,
                env=env,
                input=input,
                stdin=None if input is not None else subprocess.DEVNULL,
                capture_output=True,
                text=True,
            )
        except (OSError, ValueError) as exc:
            return Subprocess(127, "", f"spawn failed: {exc}")
        return Subprocess(r.returncode, r.stdout, r.stderr)


def plugin_root(benchmark_dir: str) -> str:
    return os.path.dirname(benchmark_dir)


def _copy_tree(src: str, dest: str) -> None:
    os.makedirs(dest, exist_ok=True)
    for name in os.listdir(src):
        if name in _IGNORED_DIR_NAMES or name.endswith(".pyc"):
            continue
        s = os.path.join(src, name)
        d = os.path.join(dest, name)
        if os.path.isdir(s):
            _copy_tree(s, d)
        else:
            if os.path.exists(d):
                os.remove(d)
            shutil.copy2(s, d)


def copy_template_single_shot(template_dir: str, dest: str) -> int:
    """WITHOUT path: copy the whole template in one operation. Returns 1."""
    if os.path.exists(dest):
        shutil.rmtree(dest, ignore_errors=True)
    _copy_tree(template_dir, dest)
    return 1


def copy_template_staged(template_dir: str, dest: str) -> int:
    """WITH path: materialize the template as N discrete staged operations.

    One stage for Package.swift, one per Sources/TicTacToeKit/<subdir>, one for
    the executable target, one for Tests. Returns the staged-op count (>1).
    """
    if os.path.exists(dest):
        shutil.rmtree(dest, ignore_errors=True)
    os.makedirs(dest, exist_ok=True)
    stages = 0

    manifest = os.path.join(template_dir, "Package.swift")
    if os.path.exists(manifest):
        shutil.copy2(manifest, os.path.join(dest, "Package.swift"))
        stages += 1

    kit_src = os.path.join(template_dir, "Sources", "TicTacToeKit")
    kit_dst = os.path.join(dest, "Sources", "TicTacToeKit")
    if os.path.exists(kit_src):
        for sub in sorted(os.listdir(kit_src)):
            if sub in _IGNORED_DIR_NAMES:
                continue
            s = os.path.join(kit_src, sub)
            d = os.path.join(kit_dst, sub)
            if os.path.isdir(s):
                _copy_tree(s, d)
            else:
                os.makedirs(kit_dst, exist_ok=True)
                shutil.copy2(s, d)
            stages += 1

    exe_src = os.path.join(template_dir, "Sources", "tictactoe")
    if os.path.exists(exe_src):
        _copy_tree(exe_src, os.path.join(dest, "Sources", "tictactoe"))
        stages += 1

    tests_src = os.path.join(template_dir, "Tests")
    if os.path.exists(tests_src):
        _copy_tree(tests_src, os.path.join(dest, "Tests"))
        stages += 1

    return stages


def count_loc(app_dir: str) -> int:
    """REAL loc_produced: non-blank, non-pure-comment lines across generated *.swift."""
    total = 0
    for root, dirs, files in os.walk(app_dir):
        dirs[:] = [d for d in dirs if d not in (".build", ".swiftpm")]
        for name in files:
            if not name.endswith(".swift"):
                continue
            try:
                with open(os.path.join(root, name), encoding="utf-8") as f:
                    text = f.read()
            except OSError:
                continue
            for line in text.split("\n"):
                s = line.strip()
                if s and not s.startswith("//"):
                    total += 1
    return total


def parse_test_count(log: str) -> int:
    """Swift Testing 'Test run with N test(s)'; XCTest 'Executed N tests' fallback."""
    m = re.search(r"Test run with (\d+) test", log)
    if m:
        return int(m.group(1))
    m = re.search(r"Executed (\d+) test", log)
    if m:
        return int(m.group(1))
    return 0


def run_app_tests(app_dir: str) -> tuple:
    """Run the generated app's suite. Returns (test_count, pass_fail).

    pass_fail from the EXIT CODE only; test_count from the summary regex. OI-1:
    ``<app_dir>/.build`` swept in ``finally`` on every path.
    """
    build_dir = os.path.join(app_dir, ".build")
    try:
        r = Subprocess.run(["swift", "test", "--package-path", app_dir], cwd=app_dir)
        combined = r.stdout + r.stderr
        return parse_test_count(combined), ("pass" if r.exit_code == 0 else "fail")
    finally:
        shutil.rmtree(build_dir, ignore_errors=True)


def relative_path(path: str, base: str) -> str:
    p = os.path.normpath(path)
    b = os.path.normpath(base)
    if p.startswith(b + os.sep):
        return p[len(b) + 1:]
    return p


def build_path_metrics(app_dir: str, plugin_root_dir: str, stage_count: int,
                       estimate_complexity_score: int, cost_usd: Optional[float],
                       wall_clock_s: float) -> PathMetrics:
    test_count, pass_fail = run_app_tests(app_dir)
    loc = count_loc(app_dir)
    return PathMetrics(
        tokens=Tokens(input=None, output=None, total=None),
        cost_usd=cost_usd,
        wall_clock_s=round(wall_clock_s * 10000) / 10000,
        loc_produced=loc,
        test_count=test_count,
        coverage_pct=0.0,
        estimate_complexity_score=estimate_complexity_score,
        stage_count=stage_count,
        pass_fail=pass_fail,
        app_path=relative_path(app_dir, plugin_root_dir),
    )
