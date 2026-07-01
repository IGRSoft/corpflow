"""benchmark/lib/metrics.py — frozen metric schema (DV0d, sole owner).

Stdlib-only (Python 3.14). Dataclasses per .context/analyzing-0.md#metrics with a
small keyword-collision JSON shim:

  - Tokens.input/output  <-> JSON "in"/"out"   ("in" is a Python keyword)
  - MetricDelta.with_     <-> JSON "with"       ("with" is a Python keyword)

Live-only fields (tokens.*, cost_usd, budget_usd) are None/null in deterministic
mode and populated in live mode. wall_clock_s / loc_produced / test_count /
coverage_pct / estimate_complexity_score / stage_count / pass_fail are REAL in
both modes (measured from the generated apps).

On-disk JSON shape (AC-6):
  {
    "run_id", "timestamp_utc", "mode", "git_sha", "budget_usd",
    "paths": {
      "with":    {"tokens": {"in", "out", "total"}, "cost_usd", "wall_clock_s",
                  "loc_produced", "test_count", "coverage_pct",
                  "estimate_complexity_score", "stage_count", "pass_fail"},
      "without": { ... same ... }
    },
    "comparison": {"<metric>": {"with", "without", "delta"}, ...},
    "live_partial"?: bool        # only present/true when a live run is partial
  }
"""

from __future__ import annotations

import json
from dataclasses import dataclass, asdict, field, fields
from typing import Any, Literal

Mode = Literal["deterministic", "live"]

# Numeric metrics that always get a comparison entry (REAL in both modes).
_DETERMINISTIC_COMPARISON_KEYS = (
    "loc_produced",
    "test_count",
    "coverage_pct",
    "wall_clock_s",
    "estimate_complexity_score",
    "stage_count",
)
# Additional comparison keys that are meaningful only in live mode.
_LIVE_ONLY_COMPARISON_KEYS = (
    "tokens_total",
    "cost_usd",
)


@dataclass(frozen=True)
class Tokens:
    input: int | None = None            # JSON key "in"  (fresh / uncached input)
    output: int | None = None           # JSON key "out"
    total: int | None = None            # JSON key "total" (= fresh in + out; cache is separate)
    # NEW additive cache-attribution fields (appended strictly AFTER total so the
    # positional Tokens(None, None, None) call at test_rotation_per_mode.py:31 keeps
    # resolving). Both default None; cache figures are additive siblings, NEVER summed
    # into `total`.
    cache_read: int | None = None       # JSON key "cache_read"     (cache-hit input)
    cache_creation: int | None = None   # JSON key "cache_creation" (cache-write input)

    def to_json(self) -> dict[str, Any]:
        # in/out/total emitted first, in the same order and values as before (byte-stable
        # shim); the two cache keys are ALWAYS emitted (value or null) for a uniform schema.
        return {
            "in": self.input,
            "out": self.output,
            "total": self.total,
            "cache_read": self.cache_read,
            "cache_creation": self.cache_creation,
        }

    @classmethod
    def from_json(cls, d: dict[str, Any] | None) -> "Tokens":
        d = d or {}
        return cls(
            input=d.get("in"),
            output=d.get("out"),
            total=d.get("total"),
            cache_read=d.get("cache_read"),        # legacy dicts lack this -> None
            cache_creation=d.get("cache_creation"),
        )


@dataclass(frozen=True)
class StageAttribution:
    """Per-stage token attribution for a live pipeline run (q1 -> top-level record.stages).

    All token fields are int | None (None = "no real data", never fabricated). The stage
    name is the pipeline stage code ("PL", "AR", ...) or the ab-sample label
    ("estimate"/"create"/"test").
    """

    stage: str
    fresh_in: int | None            # usage.input_tokens (fresh / uncached)
    cache_creation: int | None      # usage.cache_creation_input_tokens
    cache_read: int | None          # usage.cache_read_input_tokens
    out: int | None                 # usage.output_tokens
    cost_usd: float | None

    def to_json(self) -> dict[str, Any]:
        return {
            "stage": self.stage,
            "fresh_in": self.fresh_in,
            "cache_creation": self.cache_creation,
            "cache_read": self.cache_read,
            "out": self.out,
            "cost_usd": self.cost_usd,
        }

    @classmethod
    def from_json(cls, d: dict[str, Any]) -> "StageAttribution":
        return cls(
            stage=d["stage"],
            fresh_in=d.get("fresh_in"),
            cache_creation=d.get("cache_creation"),
            cache_read=d.get("cache_read"),
            out=d.get("out"),
            cost_usd=d.get("cost_usd"),
        )


@dataclass(frozen=True)
class PathMetrics:
    tokens: Tokens
    cost_usd: float | None
    wall_clock_s: float
    loc_produced: int
    test_count: int
    coverage_pct: float
    estimate_complexity_score: int
    stage_count: int
    pass_fail: Literal["pass", "fail"]
    app_path: str | None = None      # filesystem path to the generated app (None for live / no-app)

    def to_json(self) -> dict[str, Any]:
        return {
            "tokens": self.tokens.to_json(),
            "cost_usd": self.cost_usd,
            "wall_clock_s": self.wall_clock_s,
            "loc_produced": self.loc_produced,
            "test_count": self.test_count,
            "coverage_pct": self.coverage_pct,
            "estimate_complexity_score": self.estimate_complexity_score,
            "stage_count": self.stage_count,
            "pass_fail": self.pass_fail,
            "app_path": self.app_path,
        }

    @classmethod
    def from_json(cls, d: dict[str, Any]) -> "PathMetrics":
        return cls(
            tokens=Tokens.from_json(d.get("tokens")),
            cost_usd=d.get("cost_usd"),
            wall_clock_s=d["wall_clock_s"],
            loc_produced=d["loc_produced"],
            test_count=d["test_count"],
            coverage_pct=d["coverage_pct"],
            estimate_complexity_score=d["estimate_complexity_score"],
            stage_count=d["stage_count"],
            pass_fail=d["pass_fail"],
            app_path=d.get("app_path"),
        )


@dataclass(frozen=True)
class MetricDelta:
    with_: float | int | None     # JSON key "with"
    without: float | int | None
    delta: float | int | None     # with - without; None when either side is None

    def to_json(self) -> dict[str, Any]:
        return {"with": self.with_, "without": self.without, "delta": self.delta}

    @classmethod
    def from_json(cls, d: dict[str, Any]) -> "MetricDelta":
        return cls(with_=d.get("with"), without=d.get("without"), delta=d.get("delta"))

    @classmethod
    def of(cls, with_v: float | int | None, without_v: float | int | None) -> "MetricDelta":
        if with_v is None or without_v is None:
            return cls(with_=with_v, without=without_v, delta=None)
        return cls(with_=with_v, without=without_v, delta=with_v - without_v)


@dataclass(frozen=True)
class BenchmarkRecord:
    run_id: str
    timestamp_utc: str            # ISO-8601 Z
    mode: Mode
    git_sha: str
    budget_usd: float | None      # live only; null in deterministic
    paths: dict[str, PathMetrics]            # {"with": ..., "without": ...}
    comparison: dict[str, MetricDelta]       # {"<metric>": MetricDelta, ...}
    live_partial: bool = False    # set True when a live run aborts/degrades
    # NEW optional per-stage attribution (q1). Top-level, NOT nested under paths.with.
    # to_json OMITS the key when empty so deterministic + legacy records stay byte-identical.
    stages: list["StageAttribution"] = field(default_factory=list)

    def to_json(self) -> dict[str, Any]:
        out: dict[str, Any] = {
            "run_id": self.run_id,
            "timestamp_utc": self.timestamp_utc,
            "mode": self.mode,
            "git_sha": self.git_sha,
            "budget_usd": self.budget_usd,
            "paths": {k: v.to_json() for k, v in self.paths.items()},
            "comparison": {k: v.to_json() for k, v in self.comparison.items()},
        }
        # Only surface live_partial when meaningful (keeps deterministic records clean).
        if self.live_partial:
            out["live_partial"] = True
        # Omit-when-empty: deterministic/legacy records carry no "stages" key (byte-stable).
        if self.stages:
            out["stages"] = [s.to_json() for s in self.stages]
        return out

    @classmethod
    def from_json(cls, d: dict[str, Any]) -> "BenchmarkRecord":
        return cls(
            run_id=d["run_id"],
            timestamp_utc=d["timestamp_utc"],
            mode=d["mode"],
            git_sha=d["git_sha"],
            budget_usd=d.get("budget_usd"),
            paths={k: PathMetrics.from_json(v) for k, v in d["paths"].items()},
            comparison={k: MetricDelta.from_json(v) for k, v in d["comparison"].items()},
            live_partial=bool(d.get("live_partial", False)),
            stages=[StageAttribution.from_json(s) for s in d.get("stages", [])],
        )


def build_comparison(
    with_p: PathMetrics, without_p: PathMetrics, mode: Mode
) -> dict[str, MetricDelta]:
    """Compute the WITH-vs-WITHOUT comparison block for every numeric metric."""
    comp: dict[str, MetricDelta] = {}
    for key in _DETERMINISTIC_COMPARISON_KEYS:
        comp[key] = MetricDelta.of(getattr(with_p, key), getattr(without_p, key))
    if mode == "live":
        comp["tokens_total"] = MetricDelta.of(with_p.tokens.total, without_p.tokens.total)
        comp["cost_usd"] = MetricDelta.of(with_p.cost_usd, without_p.cost_usd)
    return comp


def make_record(
    *,
    run_id: str,
    timestamp_utc: str,
    mode: Mode,
    git_sha: str,
    budget_usd: float | None,
    with_p: PathMetrics,
    without_p: PathMetrics,
    live_partial: bool = False,
    stages: list[StageAttribution] | None = None,
) -> BenchmarkRecord:
    """Assemble a BenchmarkRecord with a computed comparison block."""
    return BenchmarkRecord(
        run_id=run_id,
        timestamp_utc=timestamp_utc,
        mode=mode,
        git_sha=git_sha,
        budget_usd=budget_usd,
        paths={"with": with_p, "without": without_p},
        comparison=build_comparison(with_p, without_p, mode),
        live_partial=live_partial,
        stages=list(stages) if stages else [],
    )


# ---- JSON I/O ---------------------------------------------------------------

def dumps(record: BenchmarkRecord, *, indent: int = 2) -> str:
    return json.dumps(record.to_json(), indent=indent, sort_keys=False)


def loads(text: str) -> BenchmarkRecord:
    return BenchmarkRecord.from_json(json.loads(text))


def write_record(record: BenchmarkRecord, path: str) -> None:
    with open(path, "w", encoding="utf-8") as f:
        f.write(dumps(record))


def read_record(path: str) -> BenchmarkRecord:
    with open(path, "r", encoding="utf-8") as f:
        return loads(f.read())


__all__ = [
    "Mode",
    "Tokens",
    "StageAttribution",
    "PathMetrics",
    "MetricDelta",
    "BenchmarkRecord",
    "build_comparison",
    "make_record",
    "dumps",
    "loads",
    "write_record",
    "read_record",
]
