#!/usr/bin/env python3
"""Estimation calculator — fixed arithmetic chain for the estimation-methodology skill.

Implements exactly:
  1. SP × multiplier  → base hours min/max
  2. × 0.15 buffer    → total hours min/max
  3. × rate           → budget min/max          (optional)
  4. phase weeks/%    → per-phase distribution  (optional)
  5. AI cost product  → token × model_rate × (1+retry) × complexity_mult  (optional)
  6. 5-factor sum     → complexity band LOW/MEDIUM/HIGH

Model judgment (T-shirt sizing, factor scoring) stays outside this script.
"""

from __future__ import annotations

import argparse
import json
import sys
from typing import Any

# ---------------------------------------------------------------------------
# Constants sourced from SKILL.md and cost-optimization/SKILL.md
# ---------------------------------------------------------------------------

MULTIPLIERS: dict[str, int] = {
    "junior": 10,
    "mid": 8,
    "senior": 6,  # default
    "expert": 4,
}

# Story-point ranges by T-shirt size (sp_min, sp_max)
TSHIRT_SP: dict[str, tuple[int, int]] = {
    "XS": (1, 1),
    "S": (2, 3),
    "M": (4, 5),
    "L": (6, 10),
    "XL": (13, 21),
}

BUFFER_RATE: float = 0.15
PHASE_MAX_HOURS: int = 160  # 4 weeks × 40 h/week
HOURS_PER_WEEK: int = 40

# Complexity bands (sum of 5 factors, each 1-5; max = 25)
COMPLEXITY_BANDS: list[tuple[int, int, str]] = [
    (0, 10, "LOW"),
    (11, 17, "MEDIUM"),
    (18, 25, "HIGH"),
]

# AI model per-token costs in USD/million tokens (cost-optimization/SKILL.md)
MODEL_RATES_PER_M: dict[str, float] = {
    "haiku": 0.25,
    "sonnet": 3.0,
    "opus": 15.0,
}

# Retry factors by complexity label (cost-optimization/SKILL.md)
RETRY_FACTORS: dict[str, float] = {
    "low": 0.1,
    "medium": 0.2,
    "high": 0.5,
}

# Complexity multipliers (cost-optimization/SKILL.md)
CODEBASE_MULTIPLIERS: dict[str, float] = {
    "standard": 1.0,
    "large": 1.5,
    "novel": 2.0,
}


# ---------------------------------------------------------------------------
# Core arithmetic — each function is pure and unit-testable
# ---------------------------------------------------------------------------


def hours_range(sp_min: int, sp_max: int, multiplier: int) -> tuple[float, float]:
    """Base hours from story points × multiplier."""
    return float(sp_min * multiplier), float(sp_max * multiplier)


def buffered_hours(
    base_min: float, base_max: float, buffer_rate: float = BUFFER_RATE
) -> tuple[float, float]:
    """Total hours after adding the buffer."""
    return base_min * (1 + buffer_rate), base_max * (1 + buffer_rate)


def budget(total_min: float, total_max: float, rate: float) -> tuple[float, float]:
    """Budget in currency units at the given hourly rate."""
    return total_min * rate, total_max * rate


def phase_weeks(hours_min: float, hours_max: float) -> tuple[float, float]:
    """Duration in weeks (hours ÷ 40)."""
    return hours_min / HOURS_PER_WEEK, hours_max / HOURS_PER_WEEK


def phase_pct(
    phase_min: float, phase_max: float, total_min: float, total_max: float
) -> tuple[float, float]:
    """Phase share of total hours as percentage."""
    pct_min = (phase_min / total_min * 100) if total_min else 0.0
    pct_max = (phase_max / total_max * 100) if total_max else 0.0
    return pct_min, pct_max


def ai_cost(
    base_tokens: int,
    model: str,
    retry_complexity: str = "medium",
    codebase_type: str = "standard",
) -> float:
    """AI cost in USD using cost-optimization/SKILL.md formula."""
    model_rate = MODEL_RATES_PER_M.get(model.lower(), MODEL_RATES_PER_M["sonnet"])
    retry_f = RETRY_FACTORS.get(retry_complexity.lower(), RETRY_FACTORS["medium"])
    cx_mult = CODEBASE_MULTIPLIERS.get(codebase_type.lower(), CODEBASE_MULTIPLIERS["standard"])
    return base_tokens / 1_000_000 * model_rate * (1 + retry_f) * cx_mult


def complexity_band(scores: list[int]) -> tuple[int, str]:
    """Sum 5 factor scores and return (total, band)."""
    total = sum(scores)
    for lo, hi, label in COMPLEXITY_BANDS:
        if lo <= total <= hi:
            return total, label
    # Out-of-range: clamp to nearest band
    if total < COMPLEXITY_BANDS[0][0]:
        return total, COMPLEXITY_BANDS[0][2]
    return total, COMPLEXITY_BANDS[-1][2]


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="Estimation calculator — emits compact JSON. "
        "T-shirt sizing and factor scoring are judgment; supply the integers.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    # Story points (direct) or T-shirt size
    sp_group = p.add_mutually_exclusive_group()
    sp_group.add_argument("--sp", nargs=2, metavar=("MIN", "MAX"), type=int,
                          help="Story-point range (e.g. --sp 4 5)")
    sp_group.add_argument("--size", choices=list(TSHIRT_SP), metavar="SIZE",
                          help="T-shirt size: XS S M L XL")

    p.add_argument("--multiplier", type=int, default=None,
                   metavar="H",
                   help="Hours-per-SP override (default: 6 for senior)")
    p.add_argument("--level", choices=list(MULTIPLIERS),
                   default="senior",
                   help="Developer level — sets multiplier (default: senior=6)")
    p.add_argument("--rate", type=float, default=None,
                   metavar="RATE",
                   help="Hourly dev rate for budget calculation (USD or any currency)")

    # Phase distribution
    p.add_argument("--phase-hours", nargs=2, metavar=("MIN", "MAX"), type=float,
                   help="Phase-specific hours (subset of total) for weeks/%% output")

    # 5-factor complexity
    p.add_argument("--factors", nargs=5, type=int, metavar="N",
                   help="Five complexity factor scores (1-5 each): "
                        "technical integration risk unknowns domain")

    # AI cost
    p.add_argument("--tokens", type=int, default=None,
                   metavar="N",
                   help="Base token count for AI cost estimate")
    p.add_argument("--model", choices=list(MODEL_RATES_PER_M), default="sonnet",
                   help="AI model for cost calculation (default: sonnet)")
    p.add_argument("--retry-complexity", choices=list(RETRY_FACTORS),
                   default="medium",
                   help="Retry-factor tier: low medium high (default: medium)")
    p.add_argument("--codebase-type", choices=list(CODEBASE_MULTIPLIERS),
                   default="standard",
                   help="Codebase complexity multiplier: standard large novel (default: standard)")

    p.add_argument("--self-test", action="store_true",
                   help="Run built-in self-tests and exit")

    return p


def _run(args: argparse.Namespace) -> dict[str, Any]:
    result: dict[str, Any] = {}

    # ------------------------------------------------------------------
    # 1. Resolve SP range
    # ------------------------------------------------------------------
    sp_min: int | None = None
    sp_max: int | None = None

    if args.sp:
        sp_min, sp_max = args.sp
    elif args.size:
        sp_min, sp_max = TSHIRT_SP[args.size]

    mult = args.multiplier if args.multiplier is not None else MULTIPLIERS[args.level]

    if sp_min is not None and sp_max is not None:
        base_min, base_max = hours_range(sp_min, sp_max, mult)
        tot_min, tot_max = buffered_hours(base_min, base_max)

        result["sp"] = {"min": sp_min, "max": sp_max}
        result["multiplier_h"] = mult
        result["base_hours"] = {"min": base_min, "max": base_max}
        result["buffer_pct"] = int(BUFFER_RATE * 100)
        result["total_hours"] = {"min": round(tot_min, 2), "max": round(tot_max, 2)}

        # ------------------------------------------------------------------
        # 2. Budget
        # ------------------------------------------------------------------
        if args.rate is not None:
            bud_min, bud_max = budget(tot_min, tot_max, args.rate)
            result["rate"] = args.rate
            result["budget"] = {"min": round(bud_min, 2), "max": round(bud_max, 2)}

        # ------------------------------------------------------------------
        # 3. Phase distribution (uses total hours if --phase-hours not given)
        # ------------------------------------------------------------------
        ph_min = args.phase_hours[0] if args.phase_hours else tot_min
        ph_max = args.phase_hours[1] if args.phase_hours else tot_max

        wk_min, wk_max = phase_weeks(ph_min, ph_max)
        pct_min, pct_max = phase_pct(ph_min, ph_max, tot_min, tot_max)

        result["phase"] = {
            "hours": {"min": round(ph_min, 2), "max": round(ph_max, 2)},
            "weeks": {"min": round(wk_min, 2), "max": round(wk_max, 2)},
            "pct_of_total": {"min": round(pct_min, 1), "max": round(pct_max, 1)},
            "exceeds_4w_max": ph_max > PHASE_MAX_HOURS,
        }

    # ------------------------------------------------------------------
    # 4. AI cost
    # ------------------------------------------------------------------
    if args.tokens is not None:
        cost = ai_cost(args.tokens, args.model, args.retry_complexity, args.codebase_type)
        result["ai_cost"] = {
            "base_tokens": args.tokens,
            "model": args.model,
            "retry_complexity": args.retry_complexity,
            "codebase_type": args.codebase_type,
            "usd": round(cost, 6),
        }

    # ------------------------------------------------------------------
    # 5. 5-factor complexity
    # ------------------------------------------------------------------
    if args.factors is not None:
        labels = ["technical", "integration", "risk", "unknowns", "domain"]
        total_score, band = complexity_band(args.factors)
        result["complexity"] = {
            "factors": dict(zip(labels, args.factors)),
            "total": total_score,
            "band": band,
        }

    return result


# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------


def _self_test() -> None:
    """Run assertions against hand-computed values; exit non-zero on failure."""
    failures: list[str] = []
    ran: list[str] = []

    def check(name: str, got: object, expected: object) -> None:
        ran.append(name)
        if got != expected:
            failures.append(f"FAIL {name}: got {got!r}, expected {expected!r}")

    # --- hours_range ---
    check("hours_range senior M min", hours_range(4, 5, 6)[0], 24.0)
    check("hours_range senior M max", hours_range(4, 5, 6)[1], 30.0)
    check("hours_range junior XS", hours_range(1, 1, 10), (10.0, 10.0))

    # --- buffered_hours ---
    b_min, b_max = buffered_hours(24.0, 30.0)
    check("buffer M min", round(b_min, 2), 27.6)
    check("buffer M max", round(b_max, 2), 34.5)

    # --- budget ---
    bud_min, bud_max = budget(27.6, 34.5, 150.0)
    check("budget M min", bud_min, 4140.0)
    check("budget M max", bud_max, 5175.0)

    # --- phase_weeks ---
    wk_min, wk_max = phase_weeks(27.6, 34.5)
    check("phase weeks min", round(wk_min, 3), round(27.6 / 40, 3))
    check("phase weeks max", round(wk_max, 3), round(34.5 / 40, 3))

    # --- phase_pct (phase == total → 100%) ---
    p_min, p_max = phase_pct(27.6, 34.5, 27.6, 34.5)
    check("phase pct full", (p_min, p_max), (100.0, 100.0))

    # --- ai_cost: 100k tokens, sonnet, medium retry, standard codebase ---
    # = 100000/1e6 * 3.0 * 1.2 * 1.0 = 0.1 * 3.0 * 1.2 = 0.36
    cost = ai_cost(100_000, "sonnet", "medium", "standard")
    check("ai_cost sonnet 100k", round(cost, 6), round(0.36, 6))

    # --- ai_cost edge: haiku, high retry, novel domain ---
    # = 50000/1e6 * 0.25 * (1+0.5) * 2.0
    # = 0.05 * 0.25 * 1.5 * 2.0 = 0.0375
    cost2 = ai_cost(50_000, "haiku", "high", "novel")
    check("ai_cost haiku 50k high novel", round(cost2, 6), round(0.0375, 6))

    # --- complexity_band ---
    check("band LOW", complexity_band([1, 2, 1, 1, 2]), (7, "LOW"))
    check("band MEDIUM", complexity_band([3, 3, 2, 2, 3]), (13, "MEDIUM"))
    check("band HIGH", complexity_band([4, 4, 4, 4, 4]), (20, "HIGH"))
    check("band boundary 10", complexity_band([2, 2, 2, 2, 2]), (10, "LOW"))
    check("band boundary 11", complexity_band([2, 2, 2, 2, 3]), (11, "MEDIUM"))
    check("band boundary 17", complexity_band([3, 4, 3, 4, 3]), (17, "MEDIUM"))
    check("band boundary 18", complexity_band([4, 4, 4, 3, 3]), (18, "HIGH"))

    # --- T-shirt SP lookup ---
    check("TSHIRT XS", TSHIRT_SP["XS"], (1, 1))
    check("TSHIRT L", TSHIRT_SP["L"], (6, 10))

    # --- End-to-end via _run: M senior, rate=150, 100k tokens sonnet medium standard ---
    parser = _build_parser()
    ns = parser.parse_args([
        "--size", "M",
        "--level", "senior",
        "--rate", "150",
        "--tokens", "100000",
        "--model", "sonnet",
        "--retry-complexity", "medium",
        "--codebase-type", "standard",
        "--factors", "3", "3", "2", "2", "3",
    ])
    out = _run(ns)

    check("e2e sp min", out["sp"]["min"], 4)
    check("e2e sp max", out["sp"]["max"], 5)
    check("e2e base min", out["base_hours"]["min"], 24.0)
    check("e2e base max", out["base_hours"]["max"], 30.0)
    check("e2e total min", out["total_hours"]["min"], 27.6)
    check("e2e total max", out["total_hours"]["max"], 34.5)
    check("e2e budget min", out["budget"]["min"], 4140.0)
    check("e2e budget max", out["budget"]["max"], 5175.0)
    check("e2e ai usd", out["ai_cost"]["usd"], round(0.36, 6))
    check("e2e complexity total", out["complexity"]["total"], 13)
    check("e2e complexity band", out["complexity"]["band"], "MEDIUM")
    check("e2e phase exceeds 4w", out["phase"]["exceeds_4w_max"], False)

    if failures:
        for f in failures:
            print(f, file=sys.stderr)
        sys.exit(1)

    print(json.dumps({"self_test": "ok", "checks": len(ran)}))


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main() -> None:
    parser = _build_parser()
    args = parser.parse_args()

    if args.self_test:
        _self_test()
        return

    # Require at least one meaningful input
    has_sp = args.sp is not None or args.size is not None
    has_tokens = args.tokens is not None
    has_factors = args.factors is not None

    if not (has_sp or has_tokens or has_factors):
        parser.print_help(sys.stderr)
        sys.exit(1)

    result = _run(args)
    print(json.dumps(result))


if __name__ == "__main__":
    main()
