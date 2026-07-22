"""WITHOUT-arm policy + measurement helpers. Imports ``genlib`` ONLY — never
``.dispatch``, never ``benchmarkkit.metrics`` (AC-8; keeps this module usable
by both the live dispatcher and any future offline caller without pulling in
the record schema or the dispatch table).
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Optional

from benchmarkkit import genlib

WITHOUT_MODEL = "claude-opus-4-8"
WITHOUT_EFFORT = "high"
ARM_REAL = "real"
ARM_SKIP = "skip"
PROMPT_FILENAME = "without.txt"

_CAPTURE_STREAM_JSON = "stream-json"


def resolve_arm_mode(explicit: Optional[str], stages_subset: Optional[list]) -> str:
    """D2 policy: explicit flag wins; else real on a full run, skip on a `--stages` subset."""
    if explicit is not None:
        return explicit
    return ARM_SKIP if stages_subset else ARM_REAL


def build_without_argv(capture_mode: str) -> list:
    """Frozen baseline argv (D3): no `--agent`, opus/high, `--verbose` only on stream-json."""
    argv = ["claude", "-p", "--model", WITHOUT_MODEL, "--effort", WITHOUT_EFFORT,
            "--permission-mode", "default", "--output-format", capture_mode]
    if capture_mode == _CAPTURE_STREAM_JSON:
        argv.append("--verbose")
    return argv


def load_without_prompt(prompts_dir: str) -> str:
    """Read the WITHOUT prompt verbatim (no cache-prefix preamble). Missing file is a hard error."""
    with open(os.path.join(prompts_dir, PROMPT_FILENAME), encoding="utf-8") as f:
        return f.read()


@dataclass
class AppMeasure:
    loc_produced: int
    test_count: int
    pass_fail: str
    app_path: str


def measure_app(app_dir: str, plugin_root: str, exclude_dirs: Optional[set] = None) -> Optional[AppMeasure]:
    """Real LOC/test measurement when the arm produced a Swift package, else None (D4)."""
    if not os.path.exists(os.path.join(app_dir, "Package.swift")):
        return None
    test_count, pass_fail = genlib.run_app_tests(app_dir)
    loc = genlib.count_loc(app_dir, exclude_dirs=exclude_dirs)
    return AppMeasure(loc_produced=loc, test_count=test_count, pass_fail=pass_fail,
                      app_path=genlib.relative_path(app_dir, plugin_root))
