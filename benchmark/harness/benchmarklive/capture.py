"""Dual-mode capture parser (was Coverage.swift; renamed to avoid the coverage.py
tool clash).

stream-json: NDJSON, one object per line — collect the coverage manifest (Task
subagent_type → agents, Skill names → skills, slash-commands → commands, tool_use
count) and read usage from the terminal ``result`` line. json: today's single result
object with usage + total_cost_usd; coverage manifest = None. NEVER fabricate: any
field the output doesn't yield → None; the whole coverage object is None when no
event data exists.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Optional

from benchmarkkit.metrics import StageCoverage


class FieldPaths:
    TASK_TOOL_NAME = "Task"
    SUBAGENT_TYPE_KEY = "subagent_type"
    SKILL_TOOL_NAME = "Skill"
    SKILL_KEY = "skill"
    COMMAND_TOOL_NAME = "SlashCommand"
    COMMAND_KEY = "command"


@dataclass
class ParsedCapture:
    input_tokens: Optional[int] = None
    output_tokens: Optional[int] = None
    cache_read: Optional[int] = None
    cache_creation: Optional[int] = None
    cost_usd: Optional[float] = None
    coverage: Optional[StageCoverage] = None

    @property
    def has_usage(self) -> bool:
        return any(v is not None for v in (
            self.input_tokens, self.output_tokens, self.cache_read,
            self.cache_creation, self.cost_usd))

    @property
    def is_empty(self) -> bool:
        return not self.has_usage and self.coverage is None


def parse_single_object(text: str) -> Optional[ParsedCapture]:
    """Layer-1 single-object parse (today's --output-format json result)."""
    try:
        obj = json.loads(text)
    except (ValueError, TypeError):
        return None
    if not isinstance(obj, dict):
        return None
    usage = obj.get("usage")
    if not isinstance(usage, dict):
        return None
    in_tok = usage.get("input_tokens")
    out_tok = usage.get("output_tokens")
    cr = usage.get("cache_read_input_tokens")
    cc = usage.get("cache_creation_input_tokens")
    cost = obj.get("total_cost_usd")
    if cost is None:
        cost = usage.get("total_cost_usd")
    if in_tok is None and out_tok is None and cost is None and cr is None and cc is None:
        return None
    return ParsedCapture(input_tokens=in_tok, output_tokens=out_tok,
                         cache_read=cr, cache_creation=cc, cost_usd=cost)


def collect_tool_uses(event: dict, agents: set, skills: set, commands: set,
                      tool_calls: int) -> int:
    """Walk one NDJSON event for tool_use blocks, accumulating manifest data."""
    contents = []
    msg = event.get("message")
    if isinstance(msg, dict) and isinstance(msg.get("content"), list):
        contents = msg["content"]
    elif isinstance(event.get("content"), list):
        contents = event["content"]
    for block in contents:
        if not isinstance(block, dict) or block.get("type") != "tool_use":
            continue
        tool_calls += 1
        name = block.get("name") or ""
        inp = block.get("input") or {}
        if name == FieldPaths.TASK_TOOL_NAME:
            sub = inp.get(FieldPaths.SUBAGENT_TYPE_KEY)
            if sub:
                agents.add(sub)
        elif name == FieldPaths.SKILL_TOOL_NAME:
            skill = inp.get(FieldPaths.SKILL_KEY)
            if skill:
                (commands if skill.startswith("/") else skills).add(skill)
        elif name == FieldPaths.COMMAND_TOOL_NAME:
            cmd = inp.get(FieldPaths.COMMAND_KEY)
            if cmd:
                commands.add(cmd)
    return tool_calls


def parse(stdout: str) -> Optional[ParsedCapture]:
    """Dual-mode: stream-json NDJSON first; single-object fallback. None when nothing real."""
    lines = [ln for ln in stdout.split("\n") if ln.strip()]
    if len(lines) <= 1:
        return parse_single_object(stdout)

    agents, skills, commands = set(), set(), set()
    tool_calls = 0
    usage = None
    saw_event = False
    for line in lines:
        try:
            event = json.loads(line)
        except (ValueError, TypeError):
            continue
        if not isinstance(event, dict):
            continue
        saw_event = True
        tool_calls = collect_tool_uses(event, agents, skills, commands, tool_calls)
        if event.get("type") == "result":
            u = parse_single_object(line)
            if u is not None:
                usage = u
    if not saw_event:
        return parse_single_object(stdout)

    coverage = None
    if tool_calls > 0 or agents or skills or commands:
        coverage = StageCoverage(agents=sorted(agents), skills=sorted(skills),
                                 commands=sorted(commands), tool_calls=tool_calls)
    result = usage or ParsedCapture()
    result.coverage = coverage
    return None if result.is_empty else result
