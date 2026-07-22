"""U2 generated-project surfacing: the analysis Markdown AND the HTML report each
render a per-arm "Generated project" section (Swift file tree, per-file LOC, total
LOC, arm folder path) from a fixture tree — zero spend, no build.
"""

import os
import shutil
import tempfile
import unittest

from benchmarkkit import analysis, report
from benchmarkkit.metrics import PathMetrics, Tokens, make_record


def _seed_arm(root: str, run_id: str, arm: str, files: dict) -> None:
    d = os.path.join(root, "workdirs", run_id, arm, "Sources")
    os.makedirs(d, exist_ok=True)
    for name, n in files.items():
        with open(os.path.join(d, name), "w", encoding="utf-8") as f:
            f.write("\n".join(f"let v{i} = {i}" for i in range(n)) + "\n")


def _record(run_id: str) -> dict:
    with_pm = PathMetrics(Tokens(1000, 500, 1500), 0.2, 10.0, 4, 1, 0.0, 0, 1, "pass",
                          f"workdirs/{run_id}/with")
    without_pm = PathMetrics(Tokens(400, 200, 600), 0.1, 5.0, 7, 1, 0.0, 0, 1, "pass",
                             f"workdirs/{run_id}/without")
    return make_record(run_id, "2026-07-22T00:00:00Z", "live", "sha", None,
                       with_pm, without_pm).to_dict()


class GeneratedProjectSection(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="gen-")
        self.run_id = "run-x"
        _seed_arm(self.tmp, self.run_id, "with", {"Board.swift": 3, "AI.swift": 5})
        _seed_arm(self.tmp, self.run_id, "without", {"Board.swift": 4})

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_markdown_renders_per_arm_section(self):
        rec = _record(self.run_id)
        result = analysis.analyze(rec, workdirs_root=os.path.join(self.tmp, "workdirs"))
        md = analysis.render_markdown(result)
        self.assertIn("## generated-project", md)
        self.assertIn("### with arm", md)
        self.assertIn("### without arm", md)
        self.assertIn("Sources/AI.swift", md)
        self.assertIn("total LOC: 8", md)   # with: Board(3)+AI(5)
        self.assertIn("total LOC: 4", md)   # without: Board(4)

    def test_absent_root_omits_section(self):
        md = analysis.render_markdown(analysis.analyze(_record(self.run_id)))
        self.assertNotIn("## generated-project", md)

    def test_html_report_renders_section(self):
        history = {"live": [_record(self.run_id)]}
        html = report.render_html(history, plugin_root=self.tmp)
        self.assertIn("generated project (with)", html)
        self.assertIn("generated project (without)", html)
        self.assertIn("Sources/AI.swift", html)
        self.assertIn("total LOC 8", html)


if __name__ == "__main__":
    unittest.main()
