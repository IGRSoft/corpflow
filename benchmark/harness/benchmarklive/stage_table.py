"""Per-stage dispatch contract and the era stamp that dates every record.

Bottom of the benchmarklive graph: the argv builder, the record builders and the
orchestrator all read the table from here, so nothing in this module may import back
up into them.
"""

from __future__ import annotations

# Per-stage dispatch table: stage -> (agent, model_id, effort).
STAGE_TABLE = {
    "PL": ("corpflow:product-manager", "claude-opus-5", "high"),
    "AR": ("corpflow:software-architector", "claude-opus-5", "high"),
    "TL": ("corpflow:team-lead", "claude-sonnet-5", "medium"),
    "DV": ("corpflow:developer", "claude-opus-5", "high"),
    "DR": ("corpflow:technical-lead", "claude-opus-5", "high"),
    "SR": ("corpflow:security-reviewer", "claude-opus-5", "xhigh"),
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


def build_era() -> dict:
    """Stamp what this run's numbers are comparable against.

    Model pins are the axis that silently invalidated the stored baselines at
    v3.37.1, so they travel with every record rather than living only in a README.
    """
    return {
        "harness": HARNESS_GENERATION,
        "prompt_contract": PROMPT_CONTRACT,
        "model_pins": {stage: model for stage, (_agent, model, _effort) in STAGE_TABLE.items()},
    }
