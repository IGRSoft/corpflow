"""Per-stage dispatch contract and the era stamp that dates every record.

Bottom of the benchmarklive graph: the argv builder, the record builders and the
orchestrator all read the table from here, so nothing in this module may import back
up into them.
"""

from __future__ import annotations

import functools
import json
import os
import subprocess
from typing import Optional

# Per-stage dispatch table: stage -> (agent, model_id, effort).
STAGE_TABLE = {
    "PL": ("corpflow:product-manager", "claude-opus-5-5", "high"),
    "AR": ("corpflow:software-architector", "claude-opus-5-5", "high"),
    "TL": ("corpflow:team-lead", "claude-sonnet-5", "medium"),
    "DV": ("corpflow:developer", "claude-opus-5-5", "high"),
    "DR": ("corpflow:technical-lead", "claude-opus-5-5", "high"),
    "SR": ("corpflow:security-reviewer", "claude-opus-5-5", "xhigh"),
    "QA": ("corpflow:qa-engineer", "claude-sonnet-5", "medium"),
    "DC": ("corpflow:technical-writer", "claude-haiku-4-5", "low"),
    "FN": ("corpflow:project-manager", "claude-sonnet-5", "medium"),
    "ST": ("corpflow:stakeholder", "claude-sonnet-5", "low"),
}

CAPTURE_JSON = "json"
CAPTURE_STREAM_JSON = "stream-json"

# Bumped by hand whenever the graded task text changes; a workload change makes
# token and quality figures incomparable just as surely as a model repin does.
PROMPT_CONTRACT = "scripted-cli-v3"
HARNESS_GENERATION = "python-1"

# Pins the contract text this version names, so editing the contract without
# bumping above fails a test instead of stamping stale records. Re-pin and bump
# together, and re-audit oracle tiers: a rule the contract now states has moved
# from `implied` to `specified`.
CLI_CONTRACT_DIGEST = "sha256:3e4ef30ed12839248d4e3acce8cb73d41c610d141adddd41f3b201623187a415"


@functools.lru_cache(maxsize=1)
def _plugin_version() -> Optional[str]:
    """Version of the plugin tree under measurement, or None if unreadable."""
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    try:
        with open(os.path.join(root, ".claude-plugin", "plugin.json"), encoding="utf-8") as f:
            version = json.load(f).get("version")
    except (OSError, ValueError):
        return None
    return version if isinstance(version, str) else None


@functools.lru_cache(maxsize=1)
def _cli_version() -> Optional[str]:
    """`claude --version`, or None when it cannot be probed.

    Absent rather than guessed: the gate refuses on a None mismatch, whereas a
    placeholder would certify two different CLIs as the same era.
    """
    try:
        done = subprocess.run(["claude", "--version"], capture_output=True,
                              text=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return None
    return done.stdout.strip() or None if done.returncode == 0 else None


def build_era() -> dict:
    """Stamp what this run's numbers are comparable against.

    Model pins are the axis that silently invalidated the stored baselines at
    v3.37.1, so they travel with every record rather than living only in a README.
    The two version fields close the axis that had no stamp at all: a CLI or plugin
    upgrade changes the thing being measured without touching anything else here.
    """
    return {
        "harness": HARNESS_GENERATION,
        "prompt_contract": PROMPT_CONTRACT,
        "model_pins": {stage: model for stage, (_agent, model, _effort) in STAGE_TABLE.items()},
        "cli_version": _cli_version(),
        "plugin_version": _plugin_version(),
    }
