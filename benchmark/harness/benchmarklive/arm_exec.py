"""Arm identity, the dispatch seam, and per-arm token aggregation.

``Dispatching`` is the seam tests inject fakes through, so no real LLM call happens
under test; ``SubprocessDispatcher`` is the only implementation that shells out.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Optional, Protocol

from benchmarkkit.genlib import Subprocess

from . import baseline as baseline_mod

# Production dispatcher per-stage ceiling (D5); a hung child never blocks a run forever.
STAGE_TIMEOUT_S = 3600.0


@dataclass
class ArmSpec:
    """The sole legitimate A/B difference: ``bind_agent`` (→ --agent) and ``cwd``.
    Everything else (prompts, budget, capture shape) is shared by construction."""

    name: str            # "with" | "without"
    bind_agent: bool
    cwd: str
    audit_path: str


@dataclass
class ArmResult:
    name: str
    usages: list = field(default_factory=list)   # [(stage, StageUsage)]
    dispatched: int = 0
    partial: bool = False
    dv_gated: bool = False
    app: Optional[baseline_mod.AppMeasure] = None


class Dispatching(Protocol):
    def run(self, argv: list, prompt_text: str) -> str:
        ...


class DispatchFailure(Exception):
    pass


class SubprocessDispatcher:
    """Production dispatcher: shell out to headless `claude -p`, prompt on stdin."""

    def __init__(self, workdir: Optional[str] = None, timeout: Optional[float] = STAGE_TIMEOUT_S) -> None:
        self.workdir = workdir
        self.timeout = timeout

    def run(self, argv: list, prompt_text: str) -> str:
        r = Subprocess.run(argv, cwd=self.workdir, input=prompt_text, timeout=self.timeout)
        if r.exit_code != 0:
            snippet = r.stderr.strip()[:400]
            # Under --output-format json the CLI reports API failures on stdout, not
            # stderr; without this the diagnostic is recoverable only from CLI transcripts.
            out_snippet = r.stdout.strip()[:400]
            raise DispatchFailure(
                f"claude -p failed (rc={r.exit_code}) for argv {argv[:6]}…"
                + (f" stderr: {snippet}" if snippet else "")
                + (f" stdout: {out_snippet}" if out_snippet else "")
            )
        return r.stdout


def _sum_opt(values: list):
    real = [v for v in values if v is not None]
    return sum(real) if real else None


def _tok_total(input_tokens: Optional[int], output_tokens: Optional[int]) -> Optional[int]:
    if input_tokens is None and output_tokens is None:
        return None
    return (input_tokens or 0) + (output_tokens or 0)


def _arm_tokens(usages: list) -> tuple:
    su = [u for _, u in usages]
    in_total = _sum_opt([u.input_tokens for u in su])
    out_total = _sum_opt([u.output_tokens for u in su])
    tok_total = None if (in_total is None and out_total is None) else (in_total or 0) + (out_total or 0)
    cost_total = _sum_opt([u.cost_usd for u in su])
    cr_total = _sum_opt([u.cache_read for u in su])
    cc_total = _sum_opt([u.cache_creation for u in su])
    wall = round(sum(u.duration_s for u in su) * 10000) / 10000
    return in_total, out_total, tok_total, cost_total, cr_total, cc_total, wall
