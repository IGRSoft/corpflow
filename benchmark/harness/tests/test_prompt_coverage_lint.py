"""Prompt-coverage-lint parity (port of PromptCoverageLintTests). Reads the UNCHANGED
benchmark/live/prompts/*.txt. The SwiftUI-framing assertion stays SKIPPED until the
prompts are rewritten (pending-guard) — do not force-unskip. Also pins the WITHOUT
baseline prompt: it must exist, stay free of plugin vocabulary (it is sent verbatim,
with no cache-prefix preamble), and still name the same TTT spec scope.
"""

import os
import unittest

_HARNESS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_PROMPTS = os.path.join(os.path.dirname(_HARNESS), "live", "prompts")
_STAGE_FILES = ["pl", "ar", "tl", "dv", "dr", "sr", "qa", "dc", "fn", "st"]
_PLUGIN_VOCAB = ["igrsoft", "worktask", ".context", "stage", "<<<"]
_SPEC_SCOPE_WORDS = ["SwiftUI", "Tic-Tac-Toe", "minimax", "Swift Testing"]


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

    def test_without_prompt_exists_and_is_plugin_free(self):
        text = _read("without")
        low = text.lower()
        for token in _PLUGIN_VOCAB:
            self.assertNotIn(token, low, f"without.txt leaks plugin vocabulary: {token!r}")

    def test_without_prompt_names_the_spec_scope(self):
        text = _read("without")
        for word in _SPEC_SCOPE_WORDS:
            self.assertIn(word, text, f"without.txt missing spec-scope word: {word!r}")


if __name__ == "__main__":
    unittest.main()
