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

ARM_WITH = "with"
ARM_WITHOUT = "without"
ARM_BOTH = "both"
ARM_FLAG_VALUES = (ARM_WITH, ARM_WITHOUT, ARM_BOTH)

SHAPE_PAIRED = "paired"
SHAPE_ARM = "arm"

# Mirrors dispatch.PERMISSION_MODE verbatim; parity is asserted by test, not imported,
# so this module keeps its genlib-only boundary.
PERMISSION_MODE = "bypassPermissions"


def stages_subset(stages: Optional[list], full_pipeline: list) -> Optional[list]:
    """Subset-ness is a property of the RESOLVED set, never of whether ``--stages`` was
    typed: a flag spelling out the whole pipeline, in any order, is still a full run.
    Callers pass the list they will dispatch, never the raw flag value.
    """
    if stages is None:
        return None
    return None if set(stages) == set(full_pipeline) else list(stages)


def resolve_arm_mode(explicit: Optional[str], stages_subset: Optional[list]) -> str:
    """D2 policy: explicit flag wins; else real on a full run, skip on a genuine subset
    (``stages_subset`` non-empty only when the resolved stages differ from the pipeline).
    """
    if explicit is not None:
        return explicit
    return ARM_SKIP if stages_subset else ARM_REAL


class ArmSelectionError(ValueError):
    """Contradictory or unknown arm flags. Raised before any dispatch, so a usage
    slip costs nothing."""


@dataclass(frozen=True)
class ArmSelection:
    """Which arms to dispatch and what shape to record them in."""

    dispatch: tuple        # arm names in dispatch order
    record_shape: str      # SHAPE_PAIRED | SHAPE_ARM
    arm: Optional[str]     # record discriminator; None when paired


# WITHOUT dispatches first so a later WITH breach still leaves a real arm on disk.
_PAIRED_BOTH = ArmSelection(dispatch=(ARM_WITHOUT, ARM_WITH), record_shape=SHAPE_PAIRED, arm=None)
_PAIRED_SKIP = ArmSelection(dispatch=(ARM_WITH,), record_shape=SHAPE_PAIRED, arm=None)


def resolve_arm_selection(arm_flag: Optional[str], without_arm_flag: Optional[str],
                          stages_subset: Optional[list]) -> ArmSelection:
    """Resolve ``--arm`` against ``--without-arm`` and the stage subset (``stages_subset()``
    output — a resolved list that differs from the full pipeline, else None).

    ``--arm`` unset is distinct from ``--arm both``: only the unset case defers to the
    legacy subset→skip policy, which is what keeps the pre-existing default byte-stable
    while still letting an explicit ``both`` contradict an explicit ``skip``.
    """
    if arm_flag is not None and arm_flag not in ARM_FLAG_VALUES:
        raise ArmSelectionError(
            f"--arm must be one of {', '.join(ARM_FLAG_VALUES)}, got {arm_flag!r}")
    if without_arm_flag is not None and without_arm_flag not in (ARM_REAL, ARM_SKIP):
        raise ArmSelectionError(
            f"--without-arm must be {ARM_REAL} or {ARM_SKIP}, got {without_arm_flag!r}")

    if arm_flag is None:
        mode = resolve_arm_mode(without_arm_flag, stages_subset)
        return _PAIRED_BOTH if mode == ARM_REAL else _PAIRED_SKIP

    if arm_flag == ARM_BOTH:
        if without_arm_flag == ARM_SKIP:
            raise ArmSelectionError(
                f"--arm {ARM_BOTH} contradicts --without-arm {ARM_SKIP}: "
                "one asks for both arms, the other for a placeholder")
        return _PAIRED_BOTH

    if without_arm_flag is not None:
        raise ArmSelectionError(
            f"--arm {arm_flag} contradicts --without-arm {without_arm_flag}: "
            "a single-arm run has no opposite arm to configure")
    return ArmSelection(dispatch=(arm_flag,), record_shape=SHAPE_ARM, arm=arm_flag)


@dataclass
class AppMeasure:
    loc_produced: int
    test_count: int
    pass_fail: str          # the arm's OWN suite — self-graded, never the quality verdict
    app_path: str
    oracle: Optional[dict] = None


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
