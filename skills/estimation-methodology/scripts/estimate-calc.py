#!/usr/bin/env python3
"""Estimation calculator — fixed arithmetic chain for the estimation-methodology skill.

Implements exactly:
  1. SP × multiplier  → base hours min/max
  2. × 0.15 buffer    → total hours min/max
  3. × rate           → budget min/max          (optional)
  4. phase weeks/%    → per-phase distribution  (optional)
  5. AI cost product  → (in × in_rate + out × out_rate) × (1+retry) × complexity_mult  (optional)
  6. 5-factor sum     → factor score + band LOW/MEDIUM/HIGH (JSON key `complexity`)

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

# USD per million tokens. The owner is skills/shared/model-selection.md § Cost Tiers;
# tests/python/test_estimate_calc.py fails when this copy and that table disagree.
MODEL_RATES_PER_M: dict[str, dict[str, float]] = {
    "haiku": {"input": 1.0, "output": 5.0},
    "sonnet": {"input": 2.0, "output": 10.0},
    "opus": {"input": 4.0, "output": 20.0},
    "fable": {"input": 10.0, "output": 50.0},
}

# Input share of Base Tokens when the caller does not supply both sides
# (cost-optimization/SKILL.md § Cost Estimation Formula, "Default split").
DEFAULT_INPUT_SHARE: float = 0.8

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


def split_tokens(
    base_tokens: int | None = None,
    input_tokens: int | None = None,
    output_tokens: int | None = None,
) -> tuple[int, int, bool]:
    """Resolve (input, output, supplied) from whichever counts the caller has.

    ``supplied`` is True only when both sides came from the caller. A missing side
    is derived from the total when there is one, else from DEFAULT_INPUT_SHARE.
    Raises ValueError on negative counts or a total that contradicts its parts.
    """
    for label, n in (("base", base_tokens), ("input", input_tokens), ("output", output_tokens)):
        if n is not None and n < 0:
            raise ValueError(f"{label} tokens must be >= 0, got {n}")
    share = DEFAULT_INPUT_SHARE
    if input_tokens is not None and output_tokens is not None:
        if base_tokens is not None and base_tokens != input_tokens + output_tokens:
            raise ValueError(
                f"tokens {base_tokens} != input {input_tokens} + output {output_tokens}")
        return input_tokens, output_tokens, True
    if base_tokens is not None:
        if input_tokens is not None:
            if input_tokens > base_tokens:
                raise ValueError(f"input tokens {input_tokens} exceed tokens {base_tokens}")
            return input_tokens, base_tokens - input_tokens, False
        if output_tokens is not None:
            if output_tokens > base_tokens:
                raise ValueError(f"output tokens {output_tokens} exceed tokens {base_tokens}")
            return base_tokens - output_tokens, output_tokens, False
        inp = round(base_tokens * share)
        return inp, base_tokens - inp, False
    if input_tokens is not None:
        return input_tokens, round(input_tokens * (1 - share) / share), False
    if output_tokens is not None:
        return round(output_tokens * share / (1 - share)), output_tokens, False
    raise ValueError("no token counts given")


def ai_cost(
    base_tokens: int | None,
    model: str,
    retry_complexity: str = "medium",
    codebase_type: str = "standard",
    input_tokens: int | None = None,
    output_tokens: int | None = None,
) -> float:
    """AI cost in USD using cost-optimization/SKILL.md § Cost Estimation Formula.

    An unknown model prices at the sonnet rate; the CLI rejects it before this point.
    """
    rates = MODEL_RATES_PER_M.get(model.lower(), MODEL_RATES_PER_M["sonnet"])
    retry_f = RETRY_FACTORS.get(retry_complexity.lower(), RETRY_FACTORS["medium"])
    cx_mult = CODEBASE_MULTIPLIERS.get(codebase_type.lower(), CODEBASE_MULTIPLIERS["standard"])
    inp, out, _ = split_tokens(base_tokens, input_tokens, output_tokens)
    token_usd = (inp * rates["input"] + out * rates["output"]) / 1_000_000
    return token_usd * (1 + retry_f) * cx_mult


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
                   help="Base token count (input + output) for AI cost estimate; "
                        "split 80:20 input:output unless a side is given")
    p.add_argument("--input-tokens", type=int, default=None, metavar="N",
                   help="Input token count; with --output-tokens replaces the default split")
    p.add_argument("--output-tokens", type=int, default=None, metavar="N",
                   help="Output token count; with --input-tokens replaces the default split")
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
    if args.tokens is not None or args.input_tokens is not None or args.output_tokens is not None:
        inp, out, supplied = split_tokens(args.tokens, args.input_tokens, args.output_tokens)
        cost = ai_cost(None, args.model, args.retry_complexity, args.codebase_type,
                       input_tokens=inp, output_tokens=out)
        rates = MODEL_RATES_PER_M[args.model]
        result["ai_cost"] = {
            "base_tokens": inp + out,
            "model": args.model,
            "retry_complexity": args.retry_complexity,
            "codebase_type": args.codebase_type,
            "usd": round(cost, 6),
            "input_tokens": inp,
            "output_tokens": out,
            "split": "supplied" if supplied else "default",
            "rates_per_m": {"input": rates["input"], "output": rates["output"]},
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
    # default split 80k in / 20k out: (0.08 * 2 + 0.02 * 10) * 1.2 * 1.0 = 0.432
    cost = ai_cost(100_000, "sonnet", "medium", "standard")
    check("ai_cost sonnet 100k", round(cost, 6), 0.432)

    # --- ai_cost edge: haiku, high retry, novel domain ---
    # 40k in / 10k out: (0.04 * 1 + 0.01 * 5) * 1.5 * 2.0 = 0.27
    cost2 = ai_cost(50_000, "haiku", "high", "novel")
    check("ai_cost haiku 50k high novel", round(cost2, 6), 0.27)

    # --- ai_cost: opus prices at the Opus 5.5 rates ---
    # 80k in / 20k out: (0.08 * 4 + 0.02 * 20) * 1.2 = 0.864
    check("ai_cost opus 100k", round(ai_cost(100_000, "opus"), 6), 0.864)

    # --- ai_cost: supplied split replaces the default ---
    # (0.09 * 2 + 0.01 * 10) * 1.1 = 0.308
    cost3 = ai_cost(None, "sonnet", "low", "standard", input_tokens=90_000, output_tokens=10_000)
    check("ai_cost sonnet supplied split", round(cost3, 6), 0.308)

    # --- split_tokens: one side plus the total, and one side alone ---
    check("split total+input", split_tokens(100_000, 70_000, None), (70_000, 30_000, False))
    check("split input only", split_tokens(None, 80_000, None), (80_000, 20_000, False))

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
    check("e2e ai usd", out["ai_cost"]["usd"], 0.432)
    check("e2e ai split", (out["ai_cost"]["input_tokens"], out["ai_cost"]["output_tokens"],
                           out["ai_cost"]["split"]), (80_000, 20_000, "default"))
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
    has_tokens = any(
        n is not None for n in (args.tokens, args.input_tokens, args.output_tokens))
    has_factors = args.factors is not None

    if not (has_sp or has_tokens or has_factors):
        parser.print_help(sys.stderr)
        sys.exit(1)

    try:
        result = _run(args)
    except ValueError as exc:
        parser.error(str(exc))
    print(json.dumps(result))


if __name__ == "__main__":
    main()
