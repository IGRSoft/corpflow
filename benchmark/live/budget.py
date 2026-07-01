"""benchmark/live/budget.py — budget enforcement for live dispatch (DV0e).

Two gates (mandate / AC-8):

  (a) PRE-FLIGHT estimate, before stage 1: project the whole-run cost via the REAL
      plugin script `skills/estimation-methodology/scripts/estimate-calc.py`. If the
      projection exceeds --budget, decline BEFORE any dispatch (dispatch nothing).

  (b) RUNNING-TALLY abort, before each stage: maintain spent_usd; before dispatching
      stage k, if spent_usd + next_stage_estimate > budget, abort (dispatch nothing
      further) and let the caller write a partial record.

Neither gate ever fabricates spend — `spent_usd` only accumulates REAL per-stage
costs that the capture layers actually returned (a stage whose cost came back None
contributes 0 to the running tally but flags the record live_partial).
"""

from __future__ import annotations

import json
import subprocess
import sys

# Per-stage expected token budget used ONLY for cost ESTIMATION (not real usage).
# Conservative round numbers; the real spend is measured per stage by dispatch.py.
PER_STAGE_EXPECTED_TOKENS = 40_000

# The 10-stage full pipeline (PL -> ... -> ST) the live WITH-path runs.
PIPELINE_STAGES = ("PL", "AR", "TL", "DV", "DR", "SR", "QA", "DC", "FN", "ST")


class BudgetExceeded(RuntimeError):
    """Raised when the pre-flight projection alone exceeds the budget (no dispatch)."""


def estimate_stage_cost(
    *,
    tokens: int = PER_STAGE_EXPECTED_TOKENS,
    model: str = "opus",
    retry_complexity: str = "high",
    estimate_calc_path: str,
    runner=None,
) -> float:
    """Project one stage's USD cost via the REAL estimate-calc.py `ai_cost` chain.

    `runner` is an injectable callable(argv: list[str]) -> str returning stdout JSON;
    defaults to a subprocess call to the real script. Tests inject a fake to avoid a
    subprocess (and to exercise specific cost sequences). Returns the script's
    `ai_cost.usd` float. On any parse/exec failure, returns 0.0 defensively — a
    failed ESTIMATE must never block a run on its own (the running-tally gate uses
    REAL spend; the pre-flight gate treats an unparseable estimate as "unknown/0").
    """
    argv = [
        sys.executable,
        estimate_calc_path,
        "--tokens",
        str(tokens),
        "--model",
        model,
        "--retry-complexity",
        retry_complexity,
    ]
    try:
        if runner is not None:
            stdout = runner(argv)
        else:
            stdout = subprocess.run(
                argv, capture_output=True, text=True, check=True
            ).stdout
        data = json.loads(stdout)
        usd = data.get("ai_cost", {}).get("usd")
        return float(usd) if usd is not None else 0.0
    except (subprocess.SubprocessError, json.JSONDecodeError, ValueError, KeyError):
        return 0.0


def preflight_projection(
    *,
    stage_count: int,
    estimate_calc_path: str,
    runner=None,
) -> float:
    """Project the whole run cost = per-stage estimate * number of stages."""
    per_stage = estimate_stage_cost(
        estimate_calc_path=estimate_calc_path, runner=runner
    )
    return per_stage * stage_count


def assert_preflight_within_budget(
    *,
    budget: float,
    stage_count: int,
    estimate_calc_path: str,
    runner=None,
) -> float:
    """Gate (a). Raise BudgetExceeded if the projection exceeds budget; else return it.

    Dispatch NOTHING on failure — the caller catches and exits non-zero before any
    `claude agents run`.
    """
    projection = preflight_projection(
        stage_count=stage_count,
        estimate_calc_path=estimate_calc_path,
        runner=runner,
    )
    if projection > budget:
        raise BudgetExceeded(
            f"pre-flight projection ${projection:.4f} exceeds budget "
            f"${budget:.4f} for {stage_count} stages; dispatching nothing"
        )
    return projection


class RunningTally:
    """Gate (b). Accumulates REAL per-stage spend and decides if the next stage fits.

    Usage per stage:
        if not tally.can_afford(next_stage_estimate):
            abort -> write partial record
        ... dispatch stage, get real cost ...
        tally.add(real_cost_or_None)
    """

    def __init__(self, budget: float) -> None:
        self.budget = budget
        self.spent_usd = 0.0

    def can_afford(self, next_stage_estimate: float) -> bool:
        """True iff dispatching the next stage would NOT breach the cap."""
        return (self.spent_usd + next_stage_estimate) <= self.budget

    def add(self, real_cost: float | None) -> None:
        """Add a stage's REAL measured cost. None (unmeasured) adds nothing.

        Never fabricates: an unmeasured stage contributes 0 to the tally; the record
        is independently flagged live_partial by the dispatcher.
        """
        if real_cost is not None:
            self.spent_usd += float(real_cost)


__all__ = [
    "PER_STAGE_EXPECTED_TOKENS",
    "PIPELINE_STAGES",
    "BudgetExceeded",
    "estimate_stage_cost",
    "preflight_projection",
    "assert_preflight_within_budget",
    "RunningTally",
]
