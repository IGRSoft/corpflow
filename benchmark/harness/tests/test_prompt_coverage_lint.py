"""Prompt-coverage-lint parity (port of PromptCoverageLintTests). Reads the UNCHANGED
benchmark/live/prompts/*.txt. The SwiftUI-framing assertion stays SKIPPED until the
prompts are rewritten (pending-guard) — do not force-unskip. Also pins the WITHOUT
baseline prompt: it must exist, stay free of plugin vocabulary (it is sent verbatim,
with no cache-prefix preamble), and still name the same TTT spec scope.
"""

import json
import os
import unittest

_HARNESS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_PROMPTS = os.path.join(os.path.dirname(_HARNESS), "live", "prompts")
_STAGE_FILES = ["pl", "ar", "tl", "dv", "dr", "sr", "qa", "dc", "fn", "st"]
_PLUGIN_VOCAB = ["corpflow", "worktask", ".context", "stage", "<<<"]
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


class ScriptedCLIContract(unittest.TestCase):
    """The oracle only grades fairly while both arms are asked for the same thing,
    so `_cli-contract.txt` is the SSOT and each prompt must embed it verbatim."""

    def setUp(self):
        with open(os.path.join(_PROMPTS, "_cli-contract.txt"), encoding="utf-8") as f:
            self.canonical = f.read().rstrip("\n")

    def test_both_arms_embed_the_canonical_contract_verbatim(self):
        for name in ("dv", "without"):
            self.assertIn(self.canonical, _read(name),
                          f"{name}.txt drifted from _cli-contract.txt")

    def test_contract_pins_every_graded_surface(self):
        for token in ("--moves", "result: ", "in_progress", "X_wins", "O_wins", "draw",
                      "---+---+---", "exit 0", "0..8"):
            self.assertIn(token, self.canonical,
                          f"contract missing graded surface: {token!r}")

    def test_contract_matches_the_goldens_it_grades(self):
        """Every terminal state the contract names must appear in the case set."""
        with open(os.path.join(os.path.dirname(_PROMPTS), "..", "oracle", "cases.json"),
                  encoding="utf-8") as f:
            cases = json.load(f)["cases"]
        rendered = "\n".join(c["expect"]["stdout"] for c in cases)
        for state in ("in_progress", "X_wins", "O_wins", "draw"):
            self.assertIn(f"result: {state}", rendered)


if __name__ == "__main__":
    unittest.main()
