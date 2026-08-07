"""Deterministic dual-path orchestration.

Builds BOTH real TTT apps, records REAL metrics, writes a full-schema comparison
BenchmarkRecord (mode=deterministic), rotates per-mode latest-3 history + a per-run
detail file. No network, no live.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Callable, Optional

from . import generators, oracle, rotation
from .metrics import BenchmarkRecord, make_record, write_record


@dataclass
class Result:
    record: BenchmarkRecord
    exit_code: int  # 0 pass, 1 if a generated app's tests failed


def iso(ts: str) -> str:
    """YYYYmmddTHHMMSSZ -> YYYY-mm-ddTHH:MM:SSZ."""
    if len(ts) < 15:
        return ts
    return f"{ts[0:4]}-{ts[4:6]}-{ts[6:8]}T{ts[9:11]}:{ts[11:13]}:{ts[13:15]}Z"


def run(workdir: str, run_id: str, timestamp: str, git_sha: str, record_path: str,
        history: str, runs_dir: str, template_dir: str, plugin_root: str,
        estimate_calc_path: str,
        estimate_runner: Optional[Callable[[list], str]] = None,
        oracle_grader: Optional[Callable] = None) -> Result:
    grader = oracle.grade if oracle_grader is None else oracle_grader
    with_pm = generators.generate_with_plugin(
        workdir=workdir, template_dir=template_dir, plugin_root=plugin_root,
        estimate_calc_path=estimate_calc_path, estimate_runner=estimate_runner,
        oracle_grader=grader)
    without_pm = generators.generate_without_plugin(
        workdir=workdir, template_dir=template_dir, plugin_root=plugin_root,
        oracle_grader=grader)

    record = make_record(
        run_id=run_id, timestamp_utc=iso(timestamp), mode="deterministic",
        git_sha=git_sha, budget_usd=None, with_pm=with_pm, without_pm=without_pm)

    record_dir = os.path.dirname(record_path)
    if record_dir:
        os.makedirs(record_dir, exist_ok=True)
    write_record(record, record_path)
    rotation.rotate(history, record.to_dict())
    rotation.rotate_detail(runs_dir, run_id, record.to_dict())

    all_pass = with_pm.pass_fail == "pass" and without_pm.pass_fail == "pass"
    return Result(record=record, exit_code=0 if all_pass else 1)
