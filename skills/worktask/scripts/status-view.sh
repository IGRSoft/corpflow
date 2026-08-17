#!/usr/bin/env bash
# @description status-view.sh — read-only status table over the worktask ledgers.
#
#   Answers "what is every task doing right now" in one table. Two ledgers feed it
#   and they have different shapes, so both are normalised to a single row
#   (task, stage, status, agent, blocked_by, source) before anything is printed:
#
#     .context/state.json        `tasks{}`   — object keyed by ledger id (DV0, QA0)
#     .worktrees/*/orchestrator.json `issues[]` — array keyed by GitHub issue number
#
#   An orchestrator issue carries no stage of its own, so the stage column for a
#   megatask row is read from that issue's OWN nested ledger
#   (`.worktrees/<group>/<issue#>/.context/state.json`) — the per-issue worktask
#   writes it exactly like a plain run does.
#
#   STRICTLY READ-ONLY. It opens no file for writing — not state.json, not an
#   orchestrator.json, not a log, not an audit row. `--watch` re-reads the same
#   files on a timer and is equally read-only.
#
#   `state-patch.sh` writes state.json concurrently, so a `--watch` poll WILL
#   eventually land mid-rename. Every read is therefore best-effort: an unreadable
#   or half-written ledger degrades to a `(not readable right now)` notice and the
#   other source still renders. A view that crashes on a transient read is worse
#   than one that admits it looked at the wrong instant.
#
#   Polled, never pushed: nothing in the worktask system broadcasts state changes.
#   `--watch` therefore always prints its refresh time and interval, so a frozen
#   view is distinguishable from a quiet one.
#
# @arg --state <path>    state.json path (default: <context>/state.json).
# @arg --context <dir>   .context dir (default: .context).
# @arg --root <dir>      Repo root to scan for .worktrees/ (default: .).
# @arg --no-worktrees    Skip the megatask merge; show the local ledger only.
# @arg --json            Emit the rows as one JSON object instead of a table.
# @arg --watch <N>       Redraw every N seconds until interrupted (N >= 1).
# @arg -h | --help       Show this header.
#
# Exit codes:
#   0  rendered (including "nothing in flight" — an empty board is a valid answer)
#   2  usage error, or a --watch interval that is not a positive integer

set -euo pipefail

CONTEXT_DIR=".context"
STATE_PATH=""
ROOT_DIR="."
OUT_FORMAT="text"
WATCH_SECONDS=""
SCAN_WORKTREES=1

usage() { awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "$0"; }

die_usage() {
  printf 'status-view: %s\n' "$1" >&2
  usage >&2
  exit 2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --state)        STATE_PATH="${2:-}"; shift 2 ;;
    --context)      CONTEXT_DIR="${2:-}"; shift 2 ;;
    --root)         ROOT_DIR="${2:-}"; shift 2 ;;
    --no-worktrees) SCAN_WORKTREES=0; shift ;;
    --json)         OUT_FORMAT="json"; shift ;;
    --watch)        WATCH_SECONDS="${2:-}"; shift 2 ;;
    -h|--help)      usage; exit 0 ;;
    *)              die_usage "unknown argument: $1" ;;
  esac
done

[ -n "$STATE_PATH" ] || STATE_PATH="$CONTEXT_DIR/state.json"

if [ -n "$WATCH_SECONDS" ]; then
  case "$WATCH_SECONDS" in
    ''|*[!0-9]*) die_usage "--watch needs a positive integer, got: $WATCH_SECONDS" ;;
  esac
  [ "$WATCH_SECONDS" -ge 1 ] || die_usage "--watch needs a positive integer, got: $WATCH_SECONDS"
  [ "$OUT_FORMAT" = "json" ] && die_usage "--watch and --json are mutually exclusive"
fi

# One frame. Kept as a function so --watch and the single-shot path render through
# exactly the same code — a watch-only rendering bug could not survive a plain run.
render_frame() {
  python3 - "$STATE_PATH" "$ROOT_DIR" "$OUT_FORMAT" "$SCAN_WORKTREES" "${WATCH_SECONDS:-0}" <<'PYEOF'
import json, os, sys, time

state_path, root_dir, out_format, scan_worktrees, watch_seconds = sys.argv[1:6]
scan_worktrees = scan_worktrees == "1"
watch_seconds = int(watch_seconds)

# Pipeline order, used only to pick the furthest-along completed stage when a
# megatask issue has no in_progress task. Codes match state-patch.sh's stage map.
STAGE_ORDER = ["PL", "AR", "TL", "DV", "DR", "SR", "QA", "DC", "RE", "FN", "ST", "IR", "ET"]
DASH = "—"

notices = []


def load_json(path):
    """(obj, note). A note instead of an exception: state-patch.sh writes
    concurrently, so an unparseable read is an expected transient, not a fault."""
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh), None
    except FileNotFoundError:
        return None, "absent"
    except (OSError, ValueError):
        return None, "unreadable"


def as_dict(value):
    return value if isinstance(value, dict) else {}


def display_agent(agent):
    """Strip the default namespace so the column stays narrow; a sibling plugin's
    prefix is load-bearing and kept."""
    if not agent:
        return None
    return agent[len("corpflow:"):] if agent.startswith("corpflow:") else agent


def join_blockers(values, prefix=""):
    items = [f"{prefix}{v}" for v in values if v not in (None, "")]
    return ",".join(items) if items else None


def row(task, stage, status, agent, blocked_by, source):
    return {
        "task": task,
        "stage": stage,
        "status": status,
        "agent": agent,
        "blocked_by": blocked_by,
        "source": source,
    }


def stage_of_ledger(state):
    """(stage, agent) for a ledger as a whole: what it is working on now, else the
    furthest stage it finished. Returns (None, None) for an empty tasks{}."""
    tasks = as_dict(state.get("tasks"))
    running = sorted(
        (tid, t) for tid, t in tasks.items()
        if isinstance(t, dict) and t.get("status") == "in_progress"
    )
    if running:
        tid, task = running[0]
        meta = as_dict(task.get("metadata"))
        return meta.get("stage") or tid[:2], display_agent(meta.get("agent"))
    done = [
        (tid, t) for tid, t in tasks.items()
        if isinstance(t, dict) and t.get("status") == "completed"
    ]
    if done:
        def rank(pair):
            tid, task = pair
            code = as_dict(task.get("metadata")).get("stage") or tid[:2]
            return (STAGE_ORDER.index(code) if code in STAGE_ORDER else -1, tid)
        tid, task = max(done, key=rank)
        return as_dict(task.get("metadata")).get("stage") or tid[:2], None
    return None, None


# --- local ledger: tasks{} ---------------------------------------------------
rows = []
state, note = load_json(state_path)
if note == "unreadable":
    notices.append(f"{state_path} not readable right now (being written?) — local rows omitted")
elif state is not None:
    tasks = as_dict(state.get("tasks")) if isinstance(state, dict) else {}
    if not isinstance(state, dict) or not isinstance(state.get("tasks"), dict):
        notices.append(f"{state_path} has no usable tasks{{}} map — local rows omitted")
    # Iterate tasks{} wholesale: no filter on stage/status/agent, so a task missing
    # any optional field still gets a row rather than vanishing from the board.
    for task_id in sorted(tasks):
        task = tasks[task_id]
        if not isinstance(task, dict):
            rows.append(row(task_id, None, "(malformed)", None, None, "state"))
            continue
        meta = as_dict(task.get("metadata"))
        blocked = task.get("blocked_by")
        rows.append(row(
            task_id,
            meta.get("stage") or task_id[:2],
            task.get("status") or "(unset)",
            display_agent(meta.get("agent")),
            join_blockers(blocked if isinstance(blocked, list) else []),
            "state",
        ))

local_state_present = state is not None or note == "unreadable"

# --- megatask groups: .worktrees/*/orchestrator.json -------------------------
groups_seen = 0
if scan_worktrees:
    worktrees = os.path.join(root_dir, ".worktrees")
    try:
        entries = sorted(os.listdir(worktrees))
    except OSError:
        entries = []  # absent .worktrees/ is the common single-worktask case, not an error
    for group in entries:
        group_dir = os.path.join(worktrees, group)
        orch_path = os.path.join(group_dir, "orchestrator.json")
        if not os.path.isfile(orch_path):
            continue
        groups_seen += 1
        orch, onote = load_json(orch_path)
        if onote == "unreadable" or not isinstance(orch, dict):
            notices.append(f"{orch_path} not readable right now — group '{group}' omitted")
            continue
        issues = orch.get("issues")
        if not isinstance(issues, list):
            notices.append(f"{orch_path} has no usable issues[] array — group '{group}' omitted")
            continue
        for issue in issues:
            if not isinstance(issue, dict):
                continue
            number = issue.get("number")
            nested, _ = load_json(
                os.path.join(group_dir, str(number), ".context", "state.json")
            )
            stage, agent = stage_of_ledger(nested) if isinstance(nested, dict) else (None, None)
            blocked = issue.get("blocked_by")
            rows.append(row(
                f"#{number}" if number is not None else "#?",
                stage,
                issue.get("status") or "(unset)",
                agent,
                join_blockers(blocked if isinstance(blocked, list) else [], prefix="#"),
                group,
            ))

payload = {
    "state_path": state_path,
    "worktask_id": as_dict(state).get("worktask_id") if isinstance(state, dict) else None,
    "groups": groups_seen,
    "rows": rows,
    "notices": notices,
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "poll_seconds": watch_seconds or None,
}

if out_format == "json":
    print(json.dumps(payload, indent=2))
    sys.exit(0)

if not rows:
    if not local_state_present and groups_seen == 0:
        print(f"status-view: no ledger at {state_path} and no megatask groups — "
              "no active worktask here.")
    else:
        print(f"status-view: {state_path} — no tasks recorded yet.")
    for n in notices:
        print(f"  note: {n}")
    sys.exit(0)

COLUMNS = [
    ("task", "TASK"),
    ("stage", "STAGE"),
    ("status", "STATUS"),
    ("agent", "AGENT"),
    ("blocked_by", "BLOCKED BY"),
    ("source", "SOURCE"),
]
cells = [[str(r[key]) if r[key] else DASH for key, _ in COLUMNS] for r in rows]
widths = [
    max(len(head), *(len(c[i]) for c in cells))
    for i, (_, head) in enumerate(COLUMNS)
]


def line(values):
    return "  ".join(v.ljust(widths[i]) for i, v in enumerate(values)).rstrip()


wt = payload["worktask_id"] or "(unnamed)"
print(f"status-view: {state_path} — worktask {wt}"
      + (f"   megatask groups: {groups_seen}" if groups_seen else ""))
print()
print(line([head for _, head in COLUMNS]))
print("-" * len(line([head for _, head in COLUMNS])))
for c in cells:
    print(line(c))
print()
if watch_seconds:
    # Staleness must be visible, not inferred: without these two numbers a wedged
    # redraw loop looks exactly like a board where nothing is happening.
    print(f"refreshed {payload['generated_at']} · polling every {watch_seconds}s · Ctrl-C to exit")
else:
    print(f"read {payload['generated_at']} · point-in-time snapshot, not live")
for n in notices:
    print(f"note: {n}")
sys.exit(0)
PYEOF
}

if [ -z "$WATCH_SECONDS" ]; then
  render_frame
  exit 0
fi

# --watch: redraw in place on a TTY, append frames otherwise (so piping to a file
# or a log stays readable instead of accumulating escape sequences).
IS_TTY=0
[ -t 1 ] && IS_TTY=1

restore_terminal() {
  [ "$IS_TTY" -eq 1 ] && printf '\033[?25h' || true
}
# Ctrl-C must leave a usable prompt: restore the cursor, emit the newline the
# redraw loop owes, and exit 0 — an interrupted view is not a failed view.
on_interrupt() {
  restore_terminal
  printf '\n'
  exit 0
}
trap on_interrupt INT TERM
trap restore_terminal EXIT

[ "$IS_TTY" -eq 1 ] && printf '\033[?25l'
while :; do
  # \033[3J clears scrollback too, so a shrinking table cannot leave stale rows
  # from a previous frame visible above the new one.
  [ "$IS_TTY" -eq 1 ] && printf '\033[H\033[2J\033[3J'
  render_frame
  sleep "$WATCH_SECONDS"
done
