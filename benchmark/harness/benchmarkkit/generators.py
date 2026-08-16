"""Deterministic WITH/WITHOUT generators.

WITH: drives the REAL estimate-calc.py (subprocess) for the complexity score, then
materializes ttt-template as N staged ops (stage_count >1). WITHOUT: single-shot
copy, stage_count == 1, score 0. Both copy benchmark/ttt-template/ into the workdir.
Deterministic only — no network, no LLM, never imports benchmarklive.
"""

from __future__ import annotations

import contextlib
import json
import os
import shutil
import tempfile
from typing import Callable, Optional

from . import genlib, treecopy
from .genlib import Subprocess, Timer
from .metrics import PathMetrics

FACTORS = ["3", "3", "3", "3", "3"]
EXPECTED_TOKENS = "100000"


@contextlib.contextmanager
def with_ephemeral_workdir(prefix: str = "ttt_gen_"):
    """Yield a freshly-created workdir removed on EVERY exit path (OI-1/R3).

    Scoped to the dir this helper owns; a persistent --workdir is never touched.
    """
    workdir = tempfile.mkdtemp(prefix=prefix)
    try:
        yield workdir
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


def run_estimate(estimate_calc_path: str,
                 runner: Optional[Callable[[list], str]] = None) -> tuple:
    """Drive the REAL estimate-calc.py. Returns (score, cost_usd|None).

    Any failure degrades cost to None (never fabricated); score falls back to 0.
    """
    argv = [
        "python3", estimate_calc_path,
        "--size", "M", "--level", "senior",
        "--factors", *FACTORS,
        "--tokens", EXPECTED_TOKENS, "--model", "sonnet",
    ]
    if runner is not None:
        stdout = runner(argv)
    else:
        r = Subprocess.run(argv)
        if r.exit_code != 0:
            return 0, None
        stdout = r.stdout
    try:
        parsed = json.loads(stdout)
    except (ValueError, TypeError):
        return 0, None
    score = (parsed.get("complexity") or {}).get("total") or 0
    cost = (parsed.get("ai_cost") or {}).get("usd")
    return score, cost


def _grade(app_dir: str, grader: Optional[Callable]) -> Optional[dict]:
    """Score the generated app; ``None`` grader leaves the record's oracle absent."""
    return None if grader is None else grader(app_dir).to_dict()


def generate_with_plugin(workdir: str, template_dir: str, plugin_root: str,
                         estimate_calc_path: str,
                         estimate_runner: Optional[Callable[[list], str]] = None,
                         oracle_grader: Optional[Callable] = None) -> PathMetrics:
    app_dir = os.path.join(workdir, "with")
    timer = Timer()
    timer.start()
    score, _ = run_estimate(estimate_calc_path, runner=estimate_runner)
    stage_count = treecopy.copy_template_staged(template_dir, app_dir)
    elapsed = timer.elapsed
    # Deterministic mode records cost as null (estimate is not real spend).
    return genlib.build_path_metrics(
        app_dir=app_dir, plugin_root_dir=plugin_root, stage_count=stage_count,
        estimate_complexity_score=score, cost_usd=None, wall_clock_s=elapsed,
        oracle_result=_grade(app_dir, oracle_grader),
    )


def generate_without_plugin(workdir: str, template_dir: str, plugin_root: str,
                            oracle_grader: Optional[Callable] = None) -> PathMetrics:
    app_dir = os.path.join(workdir, "without")
    timer = Timer()
    timer.start()
    stage_count = treecopy.copy_template_single_shot(template_dir, app_dir)
    elapsed = timer.elapsed
    return genlib.build_path_metrics(
        app_dir=app_dir, plugin_root_dir=plugin_root, stage_count=stage_count,
        estimate_complexity_score=0, cost_usd=None, wall_clock_s=elapsed,
        oracle_result=_grade(app_dir, oracle_grader),
    )
