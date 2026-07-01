"""benchmark/lib/rotation.py — per-mode latest-3 atomic rotation (DV0d).

history.json shape: {"deterministic": [r1,r2,r3], "live": [r1,r2,r3]} — newest
LAST, max length 3 PER MODE. Adding a 4th record of a mode drops that mode's
oldest; the OTHER mode is untouched.

Atomic write reuses the state-patch.sh tmp -> fsync -> os.replace pattern
(R6 mitigation; canonical lines state-patch.sh atomic_merge()).

Records are plain dicts (the JSON form of a metrics.BenchmarkRecord). Ordering is
stabilized by ISO-8601 `timestamp_utc`.
"""

from __future__ import annotations

import json
import os
import random
from typing import Any

_MODES = ("deterministic", "live")


def _read_or_init(history_path: str) -> dict[str, list[dict[str, Any]]]:
    """Read history.json, or return an empty per-mode skeleton if absent/empty."""
    try:
        with open(history_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        data = {}
    if not isinstance(data, dict):
        data = {}
    for m in _MODES:
        data.setdefault(m, [])
    return data


def _atomic_write(path: str, data: Any) -> None:
    """tmp -> fsync -> os.replace (state-patch.sh atomic pattern)."""
    d = os.path.dirname(os.path.abspath(path)) or "."
    os.makedirs(d, exist_ok=True)
    tmp = f"{path}.{os.getpid()}.{random.randint(0, 99999)}.tmp"
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)  # atomic rename on POSIX
    finally:
        if os.path.exists(tmp):
            try:
                os.remove(tmp)
            except OSError:
                pass


def rotate(
    history_path: str, record: dict[str, Any], max_per_mode: int = 3
) -> dict[str, list[dict[str, Any]]]:
    """Append `record` to its mode bucket, keep newest `max_per_mode`, atomic-write.

    Returns the updated in-memory history dict. The record's "mode" key selects
    the bucket; the other mode bucket is left byte-identical.
    """
    mode = record["mode"]
    data = _read_or_init(history_path)
    bucket = data.setdefault(mode, [])
    bucket.append(record)
    # Order-stable by ISO-8601 timestamp (lexicographic == chronological for Z form).
    bucket.sort(key=lambda r: r.get("timestamp_utc", ""))
    if max_per_mode >= 0:
        del bucket[: max(0, len(bucket) - max_per_mode)]
    _atomic_write(history_path, data)
    return data


def rotate_detail(
    runs_dir: str, run_id: str, record: dict[str, Any], max_per_mode: int = 3
) -> str:
    """Write a per-run detail file under runs_dir/<mode>/<run_id>.json and prune
    that mode's dir to the newest `max_per_mode` by timestamp embedded in record.

    Returns the path of the written detail file. The OTHER mode's dir is untouched.
    """
    mode = record["mode"]
    mode_dir = os.path.join(runs_dir, mode)
    os.makedirs(mode_dir, exist_ok=True)
    detail_path = os.path.join(mode_dir, f"{run_id}.json")
    _atomic_write(detail_path, record)

    # Prune: keep newest max_per_mode .json files in this mode dir by their
    # embedded timestamp_utc (fall back to mtime if unreadable).
    entries: list[tuple[str, str]] = []
    for name in os.listdir(mode_dir):
        if not name.endswith(".json"):
            continue
        p = os.path.join(mode_dir, name)
        ts = ""
        try:
            with open(p, "r", encoding="utf-8") as f:
                ts = json.load(f).get("timestamp_utc", "")
        except (OSError, json.JSONDecodeError):
            ts = ""
        if not ts:
            ts = f"~{os.path.getmtime(p)}"  # mtime fallback sorts after real ISO ts
        entries.append((ts, p))
    entries.sort(key=lambda e: e[0])
    for _, p in entries[: max(0, len(entries) - max_per_mode)]:
        try:
            os.remove(p)
        except OSError:
            pass
    return detail_path


__all__ = ["rotate", "rotate_detail"]
