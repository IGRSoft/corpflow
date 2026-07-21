"""Per-mode latest-3 atomic history rotation.

history.json shape: ``{"deterministic": [r...], "live": [r...]}`` — newest LAST, max 3
per mode. Adding a 4th record of a mode drops that mode's oldest; the other mode's
bucket is carried through as the raw parsed dict, so its bytes are preserved exactly.
Records rotate as plain dicts (never re-encoded through the schema) — that is what
keeps the untouched bucket byte-identical.
"""

from __future__ import annotations

import json
import os
import random
from typing import Optional

MODES = ["deterministic", "live"]


def atomic_write(obj, path: str, indent: int = 2) -> None:
    """Write ``obj`` to ``path`` atomically: tmp -> fsync -> rename, no trailing newline."""
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)
    tmp = f"{path}.{os.getpid()}.{random.randint(0, 99999)}.tmp"
    text = json.dumps(obj, indent=indent)
    try:
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o644)
        try:
            os.write(fd, text.encode("utf-8"))
            os.fsync(fd)
        finally:
            os.close(fd)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)


def _read_or_init(history_path: str) -> dict:
    parsed = {}
    try:
        with open(history_path, encoding="utf-8") as f:
            parsed = json.load(f)
    except (OSError, ValueError):
        parsed = {}
    if not isinstance(parsed, dict):
        parsed = {}
    # Canonical order first (deterministic, live), then any extra buckets preserved.
    result: dict = {}
    for m in MODES:
        result[m] = parsed.get(m, [])
    for k, v in parsed.items():
        if k not in result:
            result[k] = v
    return result


def _timestamp(record: dict) -> str:
    return record.get("timestamp_utc") or ""


def rotate(history_path: str, record: dict, max_per_mode: int = 3) -> dict:
    """Append ``record`` to its mode bucket, keep newest ``max_per_mode``, atomic-write.

    The record's ``mode`` selects the bucket; the other mode bucket is left
    byte-identical (carried through as the raw parsed dict).
    """
    mode = record.get("mode") or "deterministic"
    buckets = _read_or_init(history_path)
    lst = buckets.setdefault(mode, [])
    lst.append(record)
    lst.sort(key=_timestamp)
    if max_per_mode >= 0 and len(lst) > max_per_mode:
        del lst[: len(lst) - max_per_mode]
    atomic_write(buckets, history_path)
    return buckets


def rotate_detail(runs_dir: str, run_id: str, record: dict, max_per_mode: int = 3) -> str:
    """Write ``runs_dir/<mode>/<run_id>.json`` and prune that mode's dir to newest 3.

    Pruning sorts by embedded ``timestamp_utc`` (mtime fallback sorts after real ISO
    timestamps). The other mode's dir is untouched.
    """
    mode = record.get("mode") or "deterministic"
    mode_dir = os.path.join(runs_dir, mode)
    os.makedirs(mode_dir, exist_ok=True)
    detail_path = os.path.join(mode_dir, f"{run_id}.json")
    atomic_write(record, detail_path)

    entries = []  # (sort_key, path)
    for name in os.listdir(mode_dir):
        if not name.endswith(".json"):
            continue
        p = os.path.join(mode_dir, name)
        ts = ""
        try:
            with open(p, encoding="utf-8") as f:
                ts = (json.load(f) or {}).get("timestamp_utc") or ""
        except (OSError, ValueError):
            ts = ""
        if not ts:
            ts = f"~{os.path.getmtime(p)}"  # mtime fallback sorts after real ISO ts
        entries.append((ts, p))
    entries.sort(key=lambda e: e[0])
    if len(entries) > max_per_mode:
        for _, p in entries[: len(entries) - max_per_mode]:
            try:
                os.remove(p)
            except OSError:
                pass
    return detail_path
