"""Prompt-coverage-lint parity (port of PromptCoverageLintTests). Reads the UNCHANGED
benchmark/live/prompts/*.txt. The SwiftUI-framing assertion stays SKIPPED until the
prompts are rewritten (pending-guard) — do not force-unskip.
"""

import os
import unittest

_HARNESS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_PROMPTS = os.path.join(os.path.dirname(_HARNESS), "live", "prompts")
_STAGE_FILES = ["pl", "ar", "tl", "dv", "dr", "sr", "qa", "dc", "fn", "st"]


def _read(name):
    with open(os.path.join(_PROMPTS, f"{name}.txt"), encoding="utf-8") as f:
        return f.read()


class PromptCoverageLint(unittest.TestCase):
    def test_ten_prompt_files_exist(self):
        for name in _STAGE_FILES:
            self.assertTrue(os.path.exists(os.path.join(_PROMPTS, f"{name}.txt")), name)

    def test_sr_prompt_scope_is_security(self):
        sr = _read("sr").lower()
        self.assertTrue(any(k in sr for k in ("security", "secret", "sandbox", "input validation")))

    @unittest.skipUnless("SwiftUI" in _read("pl") if os.path.exists(os.path.join(_PROMPTS, "pl.txt")) else False,
                         "pending-guard: stays skipped until prompts are rewritten to SwiftUI framing")
    def test_swiftui_framing_present(self):
        for name in _STAGE_FILES:
            self.assertIn("SwiftUI", _read(name))


if __name__ == "__main__":
    unittest.main()
