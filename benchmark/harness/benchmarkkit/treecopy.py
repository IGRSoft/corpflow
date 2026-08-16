"""Template tree materialization for the deterministic generators.

Copies benchmark/ttt-template/ into a per-side workdir either as one operation
(WITHOUT arm) or as N discrete staged operations (WITH arm) — the staged count is
the measured ``stage_count``, so the split points are part of the measurement, not
an implementation detail. Imports nothing from ``genlib``: the arms must be able to
materialize a template without dragging in the process-execution surface.
"""

from __future__ import annotations

import os
import shutil

_IGNORED_DIR_NAMES = {".build", ".swiftpm", "__pycache__"}


def _copy_tree(src: str, dest: str) -> None:
    os.makedirs(dest, exist_ok=True)
    for name in os.listdir(src):
        if name in _IGNORED_DIR_NAMES or name.endswith(".pyc"):
            continue
        s = os.path.join(src, name)
        d = os.path.join(dest, name)
        if os.path.isdir(s):
            _copy_tree(s, d)
        else:
            if os.path.exists(d):
                os.remove(d)
            shutil.copy2(s, d)


def copy_template_single_shot(template_dir: str, dest: str) -> int:
    """WITHOUT path: copy the whole template in one operation. Returns 1."""
    if os.path.exists(dest):
        shutil.rmtree(dest, ignore_errors=True)
    _copy_tree(template_dir, dest)
    return 1


def copy_template_staged(template_dir: str, dest: str) -> int:
    """WITH path: materialize the template as N discrete staged operations.

    One stage for Package.swift, one per Sources/TicTacToeKit/<subdir>, one for
    the executable target, one for Tests. Returns the staged-op count (>1).
    """
    if os.path.exists(dest):
        shutil.rmtree(dest, ignore_errors=True)
    os.makedirs(dest, exist_ok=True)
    stages = 0

    manifest = os.path.join(template_dir, "Package.swift")
    if os.path.exists(manifest):
        shutil.copy2(manifest, os.path.join(dest, "Package.swift"))
        stages += 1

    kit_src = os.path.join(template_dir, "Sources", "TicTacToeKit")
    kit_dst = os.path.join(dest, "Sources", "TicTacToeKit")
    if os.path.exists(kit_src):
        for sub in sorted(os.listdir(kit_src)):
            if sub in _IGNORED_DIR_NAMES:
                continue
            s = os.path.join(kit_src, sub)
            d = os.path.join(kit_dst, sub)
            if os.path.isdir(s):
                _copy_tree(s, d)
            else:
                os.makedirs(kit_dst, exist_ok=True)
                shutil.copy2(s, d)
            stages += 1

    exe_src = os.path.join(template_dir, "Sources", "tictactoe")
    if os.path.exists(exe_src):
        _copy_tree(exe_src, os.path.join(dest, "Sources", "tictactoe"))
        stages += 1

    tests_src = os.path.join(template_dir, "Tests")
    if os.path.exists(tests_src):
        _copy_tree(tests_src, os.path.join(dest, "Tests"))
        stages += 1

    return stages
