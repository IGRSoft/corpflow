"""benchmark/lib/genlib.py — shared helpers for the two deterministic generators.

Both with-plugin/generate.py and without-plugin/generate.py import this. It owns:
  - locating PLUGIN_ROOT / ttt-template
  - copying the template into a per-side workdir (staged or single-shot)
  - running the generated app's unittest suite and parsing REAL test_count/pass_fail
  - counting REAL loc_produced
  - measuring REAL per-app coverage_pct (best-effort; 0.0 when coverage.py absent)
  - building a metrics.PathMetrics from the measured values

Stdlib-only. No network. Never imports benchmark/live/.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import time

# benchmark/lib/ -> benchmark/ -> repo root
_LIB_DIR = os.path.dirname(os.path.abspath(__file__))
BENCHMARK_DIR = os.path.dirname(_LIB_DIR)
PLUGIN_ROOT = os.path.dirname(BENCHMARK_DIR)
TEMPLATE_DIR = os.path.join(BENCHMARK_DIR, "ttt-template")

sys.path.insert(0, _LIB_DIR)
import metrics  # noqa: E402  (sibling module)


# ---- template copy ----------------------------------------------------------

def _ignore_pycache(_dir, names):
    return [n for n in names if n == "__pycache__" or n.endswith(".pyc")]


def copy_template_single_shot(dest: str) -> int:
    """WITHOUT path: copy the whole template in ONE operation. Returns op count (1)."""
    if os.path.exists(dest):
        shutil.rmtree(dest)
    shutil.copytree(TEMPLATE_DIR, dest, ignore=_ignore_pycache)
    return 1


def copy_template_staged(dest: str) -> int:
    """WITH path: materialize the template as N discrete staged operations.

    Returns the number of staged operations (the process-overhead `stage_count`
    signal). Each package module + the tests dir is a separate stage.
    """
    if os.path.exists(dest):
        shutil.rmtree(dest)
    os.makedirs(dest, exist_ok=True)
    stages = 0

    # Stage 1: create the package dir + __init__.py
    pkg_src = os.path.join(TEMPLATE_DIR, "tictactoe")
    pkg_dst = os.path.join(dest, "tictactoe")
    os.makedirs(pkg_dst, exist_ok=True)
    shutil.copy2(os.path.join(pkg_src, "__init__.py"), os.path.join(pkg_dst, "__init__.py"))
    stages += 1

    # Stage 2..N: one stage per remaining package module (board, cli, tui, …)
    for name in sorted(os.listdir(pkg_src)):
        if name == "__init__.py" or not name.endswith(".py"):
            continue
        shutil.copy2(os.path.join(pkg_src, name), os.path.join(pkg_dst, name))
        stages += 1

    # Final stage: write the tests dir
    tests_src = os.path.join(TEMPLATE_DIR, "tests")
    tests_dst = os.path.join(dest, "tests")
    shutil.copytree(tests_src, tests_dst, ignore=_ignore_pycache)
    stages += 1

    return stages


# ---- measurement ------------------------------------------------------------

_RAN_RE = re.compile(r"^Ran (\d+) test", re.MULTILINE)


def run_app_tests(app_dir: str) -> tuple[int, str]:
    """Run the generated app's unittest suite. Returns (test_count, pass_fail).

    Parses unittest's "Ran N tests" + trailing OK/FAILED from stderr (unittest
    writes its summary to stderr).
    """
    proc = subprocess.run(
        [sys.executable, "-m", "unittest", "discover", "-s", "tests", "-p", "test_*.py", "-v"],
        cwd=app_dir,
        capture_output=True,
        text=True,
    )
    combined = proc.stdout + proc.stderr
    m = _RAN_RE.search(combined)
    test_count = int(m.group(1)) if m else 0
    pass_fail = "pass" if proc.returncode == 0 else "fail"
    return test_count, pass_fail


def count_loc(app_dir: str) -> int:
    """REAL loc_produced: non-blank, non-pure-comment lines across all generated .py."""
    total = 0
    for root, _dirs, files in os.walk(app_dir):
        if "__pycache__" in root:
            continue
        for fn in files:
            if not fn.endswith(".py"):
                continue
            with open(os.path.join(root, fn), "r", encoding="utf-8") as f:
                for line in f:
                    s = line.strip()
                    if s and not s.startswith("#"):
                        total += 1
    return total


def measure_coverage(app_dir: str) -> float:
    """Best-effort per-app coverage_pct. Uses coverage.py if importable; else 0.0.

    REAL when coverage.py is present; degrades to 0.0 (documented) when absent so
    deterministic mode never blocks on the optional tool.
    """
    try:
        import coverage  # noqa: F401
    except Exception:
        return 0.0
    try:
        subprocess.run(
            [sys.executable, "-m", "coverage", "run", "-m", "unittest",
             "discover", "-s", "tests", "-p", "test_*.py"],
            cwd=app_dir, capture_output=True, text=True, check=False,
        )
        rep = subprocess.run(
            [sys.executable, "-m", "coverage", "report"],
            cwd=app_dir, capture_output=True, text=True, check=False,
        )
        m = re.search(r"TOTAL\s+\d+\s+\d+\s+(\d+)%", rep.stdout)
        return float(m.group(1)) if m else 0.0
    except Exception:
        return 0.0


def build_path_metrics(
    *,
    app_dir: str,
    stage_count: int,
    estimate_complexity_score: int,
    cost_usd: float | None,
    wall_clock_s: float,
    measure_cov: bool = False,
) -> "metrics.PathMetrics":
    test_count, pass_fail = run_app_tests(app_dir)
    loc = count_loc(app_dir)
    cov = measure_coverage(app_dir) if measure_cov else 0.0
    return metrics.PathMetrics(
        tokens=metrics.Tokens(input=None, output=None, total=None),
        cost_usd=cost_usd,
        wall_clock_s=round(wall_clock_s, 4),
        loc_produced=loc,
        test_count=test_count,
        coverage_pct=cov,
        estimate_complexity_score=estimate_complexity_score,
        stage_count=stage_count,
        pass_fail=pass_fail,
        # Repo-relative so committed history.json never leaks an absolute local path.
        app_path=os.path.relpath(app_dir, PLUGIN_ROOT),
    )


class Timer:
    """Monotonic wall-clock timer (context manager)."""

    def __enter__(self) -> "Timer":
        self._t0 = time.monotonic()
        return self

    def __exit__(self, *exc) -> bool:
        self.elapsed = time.monotonic() - self._t0
        return False
