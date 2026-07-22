"""Arm policy + measurement helpers. Imports ``genlib`` ONLY — never ``.dispatch``,
never ``benchmarkkit.metrics`` (keeps this module usable by the live dispatcher and
any offline caller without pulling in the record schema or the dispatch table).
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Optional

from benchmarkkit import genlib

ARM_REAL = "real"
ARM_SKIP = "skip"

# Mirrors dispatch.PERMISSION_MODE verbatim; parity is asserted by test, not imported,
# so this module keeps its genlib-only boundary.
PERMISSION_MODE = "bypassPermissions"


def resolve_arm_mode(explicit: Optional[str], stages_subset: Optional[list]) -> str:
    """D2 policy: explicit flag wins; else real on a full run, skip on a `--stages` subset."""
    if explicit is not None:
        return explicit
    return ARM_SKIP if stages_subset else ARM_REAL


@dataclass
class AppMeasure:
    loc_produced: int
    test_count: int
    pass_fail: str
    app_path: str


def measure_app(app_dir: str, plugin_root: str, exclude_dirs: Optional[set] = None) -> Optional[AppMeasure]:
    """Real LOC/test measurement when the arm produced a Swift package, else None (D4).

    ``exclude_dirs`` is retained for callers that measure a shared root; the paired
    runner measures each arm's own folder so it never needs the sibling-prune hack.
    """
    if not os.path.exists(os.path.join(app_dir, "Package.swift")):
        return None
    test_count, pass_fail = genlib.run_app_tests(app_dir)
    loc = genlib.count_loc(app_dir, exclude_dirs=exclude_dirs)
    return AppMeasure(loc_produced=loc, test_count=test_count, pass_fail=pass_fail,
                      app_path=genlib.relative_path(app_dir, plugin_root))
