#!/usr/bin/env bash
# build-context-set.sh — produce the used-in-context file-path set for this worktask.
#
# Inputs (env vars, all optional):
#   TASK_LIST_JSON   Path to a JSON dump of TaskList (array of tasks with metadata).
#                    When absent, falls back to scanning .context/*.md for agent trailers.
#   CONTEXT_DIR      Defaults to ".context"
#   BASELINE_SHA     If present, scan `git log $BASELINE_SHA..HEAD` for `Agent:` trailers.
#
# Output to stdout: newline-delimited, deduped, sorted list of file paths present on disk.
# Paths follow these patterns:
#   agents/<name>.md
#   skills/<path>/SKILL.md
#   commands/<name>.md
#
# Any path that does not exist on disk is dropped.

set -euo pipefail

CONTEXT_DIR="${CONTEXT_DIR:-.context}"

# Collect raw qualified agent / command names into a temp buffer.
raw="$(mktemp)"
trap 'rm -f "$raw"' EXIT

# Source 1 — Task List JSON (preferred).
if [ -n "${TASK_LIST_JSON:-}" ] && [ -f "$TASK_LIST_JSON" ]; then
  # Extract metadata.agent and metadata.embedded_commands from completed tasks.
  # Tolerates jq absence by using python as fallback.
  if command -v jq >/dev/null 2>&1; then
    jq -r '
      .[] | select(.status == "completed") |
      .metadata // {} |
      (.agent // empty), (.embedded_commands // empty | split(",") | .[])
    ' "$TASK_LIST_JSON" 2>/dev/null >> "$raw" || true
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$TASK_LIST_JSON" >> "$raw" <<'PY' || true
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
for task in data:
    if task.get("status") != "completed":
        continue
    meta = task.get("metadata") or {}
    if meta.get("agent"):
        print(meta["agent"])
    for cmd in (meta.get("embedded_commands") or "").split(","):
        cmd = cmd.strip()
        if cmd:
            print(cmd)
PY
  fi
fi

# Source 2 — .context/*.md metadata trailers.
if [ -d "$CONTEXT_DIR" ]; then
  # Parse YAML-ish metadata blocks (`agent: <value>` lines)
  grep -rhE '^\s*agent:\s*' "$CONTEXT_DIR" 2>/dev/null \
    | sed -E 's/^\s*agent:\s*//; s/\s+$//; s/^["'\'']//; s/["'\'']$//' \
    >> "$raw" || true

  grep -rhE '^\s*embedded_commands:\s*' "$CONTEXT_DIR" 2>/dev/null \
    | sed -E 's/^\s*embedded_commands:\s*//; s/\s+$//' \
    | tr ',' '\n' \
    | sed -E 's/^\s+//; s/\s+$//' \
    >> "$raw" || true
fi

# Source 3 — git log `Agent:` trailers since BASELINE_SHA.
if [ -n "${BASELINE_SHA:-}" ]; then
  git log "${BASELINE_SHA}..HEAD" --format='%B' 2>/dev/null \
    | grep -E '^Agent:\s*' \
    | sed -E 's/^Agent:\s*//' \
    >> "$raw" || true
fi

# Normalize qualified names → file paths.
# Rules:
#   igrsoft:<name>              → agents/<name>.md
#   apple-developer:<name>      → (cross-plugin) — kept as raw ref; mapper drops if non-local
#   bare <name>                 → agents/<name>.md  (back-compat shim)
#   <name>:<sub> as command     → commands/<name>.md  (best-effort)
#
# The normalizer only emits LOCAL paths that exist in this repo.
normalize() {
  awk -F: '
    NF == 1 {
      # bare → igrsoft agent
      print "agents/" $1 ".md"
      next
    }
    $1 == "igrsoft" && NF == 2 {
      print "agents/" $2 ".md"
      # also try as command
      print "commands/" $2 ".md"
      # also try as skill
      print "skills/" $2 "/SKILL.md"
      next
    }
    {
      # cross-plugin agent (e.g., apple-developer:ios-developer) — not editable locally
      # Emit a sentinel line that the caller filters out.
      print "CROSS_PLUGIN:" $0
    }
  '
}

normalize < "$raw" \
  | awk '!seen[$0]++' \
  | while read -r path; do
      case "$path" in
        CROSS_PLUGIN:*) continue ;;
        *) [ -f "$path" ] && echo "$path" ;;
      esac
    done \
  | sort -u
