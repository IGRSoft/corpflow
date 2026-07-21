"""In-process loader for the hyphenated skill scripts + a thin CLI-smoke helper.

The scripts (estimate-calc.py / layout-calc.py) are not importable by normal module
syntax (hyphens), so we load them via importlib.util.spec_from_file_location. Loading
is import-safe: each script runs ``main()`` only under ``if __name__ == "__main__"``.
In-process access lets tests assert the true contracts the Swift subprocess port
could only approximate (unknown-model → sonnet fallback; unknown-layout → ValueError);
``run_cli`` covers the argparse guards the in-process path bypasses.
"""

from __future__ import annotations

import importlib.util
import os
import subprocess
import sys

_THIS = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(_THIS, "..", ".."))

ESTIMATE_CALC = os.path.join(
    REPO_ROOT, "skills", "estimation-methodology", "scripts", "estimate-calc.py"
)
LAYOUT_CALC = os.path.join(
    REPO_ROOT, "skills", "appstore-screenshots", "scripts", "layout-calc.py"
)


def load_module(path: str, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    # Register before exec so dataclass __module__ resolution (Py 3.14) can find it.
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def run_cli(script_path: str, args: list) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, script_path, *args],
        capture_output=True,
        text=True,
    )
