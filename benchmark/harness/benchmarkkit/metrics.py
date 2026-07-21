"""Frozen BenchmarkRecord schema — byte-compatible with the on-disk history.json.

The existing history.json was written by ``json.dumps(obj, indent=2)`` with native
numeric types and no trailing newline, so this port serializes the same way: dict
insertion order is the key order, ints emit without a decimal, floats via Python's
shortest round-trip repr. No custom serializer is needed (the Swift port's
JSONValue/JSONParser existed only to emulate this).

AR deltas: D1 — Tokens always emits all 5 keys (value-or-null). D2 — StageAttribution
appends an optional ``coverage`` object after ``cost_usd`` only when present. D4 —
PathMetrics carries a trailing nullable ``app_path``. D-NUMTYPES — deltas keep native
type: int metrics yield int deltas, float metrics yield float deltas (no Swift-style
whole-float→int coercion). ``live_partial`` omit-when-false; ``stages`` omit-when-empty.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from typing import Optional, Union

Number = Union[int, float]

MODES = ["deterministic", "live"]

# Numeric comparison metrics present in both modes (order is on-disk order).
DETERMINISTIC_COMPARISON_KEYS = [
    "loc_produced",
    "test_count",
    "coverage_pct",
    "wall_clock_s",
    "estimate_complexity_score",
    "stage_count",
]


def _num_or(d: dict, key: str, default: Number) -> Number:
    v = d.get(key)
    return default if v is None else v


@dataclass
class Tokens:
    input: Optional[int] = None          # JSON "in"
    output: Optional[int] = None         # JSON "out"
    total: Optional[int] = None          # fresh in + out; cache tracked separately
    cache_read: Optional[int] = None
    cache_creation: Optional[int] = None

    def to_dict(self) -> dict:
        # D1: all 5 keys, fixed order, value-or-null.
        return {
            "in": self.input,
            "out": self.output,
            "total": self.total,
            "cache_read": self.cache_read,
            "cache_creation": self.cache_creation,
        }

    @classmethod
    def from_dict(cls, d: Optional[dict]) -> "Tokens":
        # Legacy records lacking cache keys decode to None — never fabricated.
        if not d:
            return cls()
        return cls(
            input=d.get("in"),
            output=d.get("out"),
            total=d.get("total"),
            cache_read=d.get("cache_read"),
            cache_creation=d.get("cache_creation"),
        )


@dataclass
class StageCoverage:
    agents: list
    skills: list
    commands: list
    tool_calls: int

    def to_dict(self) -> dict:
        return {
            "agents": list(self.agents),
            "skills": list(self.skills),
            "commands": list(self.commands),
            "tool_calls": self.tool_calls,
        }

    @classmethod
    def from_dict(cls, d) -> Optional["StageCoverage"]:
        if not isinstance(d, dict):
            return None
        return cls(
            agents=[x for x in d.get("agents", []) if isinstance(x, str)],
            skills=[x for x in d.get("skills", []) if isinstance(x, str)],
            commands=[x for x in d.get("commands", []) if isinstance(x, str)],
            tool_calls=d.get("tool_calls") or 0,
        )


@dataclass
class StageAttribution:
    stage: str
    fresh_in: Optional[int]
    cache_creation: Optional[int]
    cache_read: Optional[int]
    out: Optional[int]
    cost_usd: Optional[float]
    coverage: Optional[StageCoverage] = None  # D2: encoded only when present

    def to_dict(self) -> dict:
        d = {
            "stage": self.stage,
            "fresh_in": self.fresh_in,
            "cache_creation": self.cache_creation,
            "cache_read": self.cache_read,
            "out": self.out,
            "cost_usd": self.cost_usd,
        }
        if self.coverage is not None:
            d["coverage"] = self.coverage.to_dict()
        return d

    @classmethod
    def from_dict(cls, d: dict) -> "StageAttribution":
        return cls(
            stage=d.get("stage") or "",
            fresh_in=d.get("fresh_in"),
            cache_creation=d.get("cache_creation"),
            cache_read=d.get("cache_read"),
            out=d.get("out"),
            cost_usd=d.get("cost_usd"),
            coverage=StageCoverage.from_dict(d.get("coverage")),
        )


@dataclass
class PathMetrics:
    tokens: Tokens
    cost_usd: Optional[float]
    wall_clock_s: float
    loc_produced: int
    test_count: int
    coverage_pct: float
    estimate_complexity_score: int
    stage_count: int
    pass_fail: str          # "pass" | "fail"
    app_path: Optional[str] = None  # D4: repo-relative; null for live/no-app

    def to_dict(self) -> dict:
        return {
            "tokens": self.tokens.to_dict(),
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
    def from_dict(cls, d: dict) -> "PathMetrics":
        return cls(
            tokens=Tokens.from_dict(d.get("tokens")),
            cost_usd=d.get("cost_usd"),
            wall_clock_s=_num_or(d, "wall_clock_s", 0.0),
            loc_produced=_num_or(d, "loc_produced", 0),
            test_count=_num_or(d, "test_count", 0),
            coverage_pct=_num_or(d, "coverage_pct", 0.0),
            estimate_complexity_score=_num_or(d, "estimate_complexity_score", 0),
            stage_count=_num_or(d, "stage_count", 0),
            pass_fail=d.get("pass_fail") or "",
            app_path=d.get("app_path"),
        )


@dataclass
class MetricDelta:
    with_: Optional[Number]   # JSON "with"
    without: Optional[Number]
    delta: Optional[Number]

    def to_dict(self) -> dict:
        # D-NUMTYPES: no coercion — native int/float flows straight through.
        return {"with": self.with_, "without": self.without, "delta": self.delta}

    @classmethod
    def from_dict(cls, d: dict) -> "MetricDelta":
        return cls(with_=d.get("with"), without=d.get("without"), delta=d.get("delta"))

    @classmethod
    def of(cls, with_v: Optional[Number], without_v: Optional[Number]) -> "MetricDelta":
        if with_v is None or without_v is None:
            return cls(with_=with_v, without=without_v, delta=None)
        return cls(with_=with_v, without=without_v, delta=with_v - without_v)


@dataclass
class BenchmarkRecord:
    run_id: str
    timestamp_utc: str
    mode: str
    git_sha: str
    budget_usd: Optional[float]
    paths: list            # ordered [("with", PathMetrics), ("without", PathMetrics)]
    comparison: list       # ordered [(key, MetricDelta), ...]
    live_partial: bool = False
    stages: list = field(default_factory=list)

    def to_dict(self) -> dict:
        d = {
            "run_id": self.run_id,
            "timestamp_utc": self.timestamp_utc,
            "mode": self.mode,
            "git_sha": self.git_sha,
            "budget_usd": self.budget_usd,
            "paths": {name: pm.to_dict() for name, pm in self.paths},
            "comparison": {key: md.to_dict() for key, md in self.comparison},
        }
        if self.live_partial:
            d["live_partial"] = True
        if self.stages:
            d["stages"] = [s.to_dict() for s in self.stages]
        return d

    @classmethod
    def from_dict(cls, d: dict) -> "BenchmarkRecord":
        paths = [(k, PathMetrics.from_dict(v)) for k, v in (d.get("paths") or {}).items()]
        comparison = [
            (k, MetricDelta.from_dict(v)) for k, v in (d.get("comparison") or {}).items()
        ]
        stages = [StageAttribution.from_dict(s) for s in (d.get("stages") or [])]
        return cls(
            run_id=d.get("run_id") or "",
            timestamp_utc=d.get("timestamp_utc") or "",
            mode=d.get("mode") or "deterministic",
            git_sha=d.get("git_sha") or "",
            budget_usd=d.get("budget_usd"),
            paths=paths,
            comparison=comparison,
            live_partial=bool(d.get("live_partial") or False),
            stages=stages,
        )

    @property
    def path_with(self) -> Optional[PathMetrics]:
        for name, pm in self.paths:
            if name == "with":
                return pm
        return None

    @property
    def path_without(self) -> Optional[PathMetrics]:
        for name, pm in self.paths:
            if name == "without":
                return pm
        return None


def build_comparison(with_pm: PathMetrics, without_pm: PathMetrics, mode: str) -> list:
    def metric(key: str, p: PathMetrics) -> Number:
        return {
            "loc_produced": p.loc_produced,
            "test_count": p.test_count,
            "coverage_pct": p.coverage_pct,
            "wall_clock_s": p.wall_clock_s,
            "estimate_complexity_score": p.estimate_complexity_score,
            "stage_count": p.stage_count,
        }[key]

    comp = [
        (key, MetricDelta.of(metric(key, with_pm), metric(key, without_pm)))
        for key in DETERMINISTIC_COMPARISON_KEYS
    ]
    if mode == "live":
        comp.append(
            ("tokens_total", MetricDelta.of(with_pm.tokens.total, without_pm.tokens.total))
        )
        comp.append(("cost_usd", MetricDelta.of(with_pm.cost_usd, without_pm.cost_usd)))
    return comp


def make_record(
    run_id: str,
    timestamp_utc: str,
    mode: str,
    git_sha: str,
    budget_usd: Optional[float],
    with_pm: PathMetrics,
    without_pm: PathMetrics,
    live_partial: bool = False,
    stages: Optional[list] = None,
) -> BenchmarkRecord:
    return BenchmarkRecord(
        run_id=run_id,
        timestamp_utc=timestamp_utc,
        mode=mode,
        git_sha=git_sha,
        budget_usd=budget_usd,
        paths=[("with", with_pm), ("without", without_pm)],
        comparison=build_comparison(with_pm, without_pm, mode),
        live_partial=live_partial,
        stages=stages or [],
    )


def dumps(record: BenchmarkRecord, indent: int = 2) -> str:
    return json.dumps(record.to_dict(), indent=indent)


def loads(text: str) -> BenchmarkRecord:
    return BenchmarkRecord.from_dict(json.loads(text))


def write_record(record: BenchmarkRecord, path: str) -> None:
    with open(path, "w", encoding="utf-8") as f:
        f.write(dumps(record))


def read_record(path: str) -> BenchmarkRecord:
    with open(path, encoding="utf-8") as f:
        return loads(f.read())
