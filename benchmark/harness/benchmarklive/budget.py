"""Budget enforcement for live dispatch.

Two gates: (a) PRE-FLIGHT projection > budget → decline before any dispatch (rc=2);
(b) RUNNING-TALLY abort before each stage → partial record written before rc=4 (D6).
Neither fabricates spend — the tally only accumulates REAL per-stage costs (None adds
nothing). SR stays in PIPELINE_STAGES (AR delta D3).
"""

from __future__ import annotations

import json
from typing import Callable, Optional

from benchmarkkit.genlib import Subprocess

PER_STAGE_EXPECTED_TOKENS = 40_000

PIPELINE_STAGES = ["PL", "AR", "TL", "DV", "DR", "SR", "QA", "DC", "FN", "ST"]


class BudgetExceeded(Exception):
    pass


def estimate_stage_cost(estimate_calc_path: str, tokens: int = PER_STAGE_EXPECTED_TOKENS,
                        model: str = "opus", retry_complexity: str = "high",
                        runner: Optional[Callable[[list], str]] = None) -> float:
    """Project one stage's USD cost via the REAL estimate-calc.py ai_cost chain.

    Any parse/exec failure returns 0.0 defensively — a failed estimate must never
    block a run on its own.
    """
    argv = ["python3", estimate_calc_path, "--tokens", str(tokens),
            "--model", model, "--retry-complexity", retry_complexity]
    if runner is not None:
        try:
            stdout = runner(argv)
        except Exception:
            return 0.0
    else:
        r = Subprocess.run(argv)
        if r.exit_code != 0:
            return 0.0
        stdout = r.stdout
    try:
        usd = (json.loads(stdout).get("ai_cost") or {}).get("usd")
    except (ValueError, TypeError, AttributeError):
        return 0.0
    return usd if isinstance(usd, (int, float)) else 0.0


def preflight_projection(stage_count: int, estimate_calc_path: str,
                         runner: Optional[Callable[[list], str]] = None) -> float:
    return estimate_stage_cost(estimate_calc_path, runner=runner) * stage_count


def assert_preflight_within_budget(budget: float, stage_count: int, estimate_calc_path: str,
                                   runner: Optional[Callable[[list], str]] = None) -> float:
    """Gate (a). Raise BudgetExceeded if the projection exceeds budget; else return it."""
    projection = preflight_projection(stage_count, estimate_calc_path, runner=runner)
    if projection > budget:
        raise BudgetExceeded(
            f"pre-flight projection ${projection:.4f} exceeds budget ${budget:.4f} "
            f"for {stage_count} stages; dispatching nothing"
        )
    return projection


class RunningTally:
    """Gate (b). Accumulates REAL per-stage spend; decides if the next stage fits."""

    def __init__(self, budget: float) -> None:
        self.budget = budget
        self.spent_usd = 0.0

    def can_afford(self, next_stage_estimate: float) -> bool:
        return self.spent_usd + next_stage_estimate <= self.budget

    def add(self, real_cost: Optional[float]) -> None:
        if real_cost is not None:
            self.spent_usd += real_cost
