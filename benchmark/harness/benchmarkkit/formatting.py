"""Display formatters shared by the HTML (``report``) and Markdown (``analysis``)
benchmark reports, so a dollar amount renders identically in both.
"""

from __future__ import annotations


def group_int(i: int) -> str:
    neg = i < 0
    return ("-" if neg else "") + f"{abs(i):,}"


def format_cost(v, none_text: str = "—") -> str:
    """USD at fixed 2dp, thousands-grouped; ``none_text`` for anything unmeasured.

    Fixed rather than trimmed: a money column whose decimal count varies per row
    is unreadable as money. Callers pass the placeholder their format needs.
    """
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        return none_text
    q = f"{float(v):.2f}"
    neg = q.startswith("-")
    if neg:
        q = q[1:]
    whole, _, frac = q.partition(".")
    # A value rounding to zero from below would otherwise render "-0.00".
    sign = "-" if (neg and (int(whole) or int(frac))) else ""
    return f"{sign}{group_int(int(whole))}.{frac}"


def format_cost_delta(with_v, without_v, none_text: str = "—") -> str:
    """Signed 2dp difference, or ``none_text`` when either side is unmeasured."""
    if isinstance(with_v, bool) or isinstance(without_v, bool):
        return none_text
    if not isinstance(with_v, (int, float)) or not isinstance(without_v, (int, float)):
        return none_text
    d = float(with_v) - float(without_v)
    rendered = format_cost(d, none_text)
    return f"+{rendered}" if d > 0 else rendered
