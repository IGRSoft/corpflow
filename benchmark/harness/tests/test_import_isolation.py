"""Import isolation (AC-8; port of PackageGraphTests + LiveGate static/import halves).

The deterministic path must never reach benchmarklive: importing benchmarkkit must
not pull benchmarklive into sys.modules, benchmarkkit/*.py must not import it, and
the deterministic entrypoints (bin/bench-deterministic, bin/bench-report) must not
either. bin/bench-live is the ONLY entrypoint allowed to import benchmarklive.
"""

import importlib
import os
import re
import sys
import unittest

_HARNESS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_LIVE_IMPORT = re.compile(r"^\s*(import\s+benchmarklive|from\s+benchmarklive)", re.MULTILINE)


def _reads(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


class ImportIsolation(unittest.TestCase):
    def test_importing_benchmarkkit_does_not_load_benchmarklive(self):
        for m in [k for k in list(sys.modules) if k.startswith("benchmarklive")]:
            del sys.modules[m]
        importlib.import_module("benchmarkkit")
        importlib.import_module("benchmarkkit.deterministic_run")
        self.assertNotIn("benchmarklive", sys.modules)

    def test_benchmarkkit_sources_never_import_benchmarklive(self):
        kit_dir = os.path.join(_HARNESS, "benchmarkkit")
        for name in os.listdir(kit_dir):
            if name.endswith(".py"):
                self.assertIsNone(
                    _LIVE_IMPORT.search(_reads(os.path.join(kit_dir, name))),
                    f"{name} imports benchmarklive",
                )

    def test_deterministic_entrypoints_never_import_benchmarklive(self):
        for entry in ("bench-deterministic", "bench-report", "bench-pair"):
            p = os.path.join(_HARNESS, "bin", entry)
            if os.path.exists(p):  # entrypoints land in Phase 5
                self.assertIsNone(_LIVE_IMPORT.search(_reads(p)), f"{entry} imports benchmarklive")

    def test_join_is_pure_analysis_and_never_reaches_dispatch(self):
        # R11/AC-9: the join is analysis, so it sits behind the same boundary as the
        # analyzer and the reporter — importing it must not pull in the live world.
        for m in [k for k in list(sys.modules) if k.startswith("benchmarklive")]:
            del sys.modules[m]
        importlib.import_module("benchmarkkit.pairing")
        self.assertNotIn("benchmarklive", sys.modules)
        for path in (os.path.join(_HARNESS, "benchmarkkit", "pairing.py"),
                     os.path.join(_HARNESS, "bin", "bench-pair")):
            self.assertIsNone(_LIVE_IMPORT.search(_reads(path)),
                              f"{os.path.basename(path)} imports benchmarklive")

    def test_bench_live_is_the_only_live_importer(self):
        p = os.path.join(_HARNESS, "bin", "bench-live")
        if os.path.exists(p):
            self.assertIsNotNone(_LIVE_IMPORT.search(_reads(p)), "bench-live must import benchmarklive")


if __name__ == "__main__":
    unittest.main()
