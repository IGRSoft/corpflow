#!/usr/bin/env bash
# PostToolUse → anchor-lint pre-flight (igrsoft worktask plugin, v3.23.3+).
#
# Managed plugin hook (registered in .claude-plugin/plugin.json). Fires on
# Write|Edit. Gates on the canonical worktask-artifact filename regex
# (.context/<stage>-N.md per handoff-protocol.md#stage-artifact-map); for a
# matching artifact it runs `cache-lint.sh --anchor-lint <artifact>` so a
# missing/extra H2 anchor surfaces at the PRODUCING Write/Edit instead of
# post-hoc at the DR gate.
#
# Shift-left rationale + cost: handoff-protocol.md#anchor-allow-list
#   § Anchor Pre-Flight (PostToolUse hook).
#
# Reads the CC hook stdin JSON (tool_input.file_path); falls back to the
# CLAUDE_TOOL_INPUT_FILE_PATH env var when jq/stdin are unavailable. A
# non-zero exit shows the producing agent the diagnostic so it self-amends;
# registered with continueOnBlock so a non-artifact write is never blocked.
#
# Self-test: pass --self-test to assert the gating regex.
set -eu

SELF_TEST=0
[ "${1:-}" = "--self-test" ] && SELF_TEST=1

# Canonical artifact basenames (mirrors handoff-protocol.md#stage-artifact-map).
ARTIFACT_RE='\.context/(planning|analyzing|coordination|development|developer-review|security-review|testing|documentation|release|complete-summary|retrospective|incident|ethics-review)-[0-9]+\.md$'

if [ "$SELF_TEST" -eq 1 ]; then
  ok=0
  for p in \
    ".context/development-0.md" \
    ".context/developer-review-12.md" \
    "/abs/path/.context/planning-3.md"; do
    printf '%s' "$p" | grep -qE "$ARTIFACT_RE" || { echo "anchor-preflight: self-test FAIL (should match: $p)"; exit 1; }
  done
  for p in \
    "skills/worktask/SKILL.md" \
    ".context/state.json" \
    ".context/development.md" \
    ".context/worktask-comms.md"; do
    printf '%s' "$p" | grep -qE "$ARTIFACT_RE" && { echo "anchor-preflight: self-test FAIL (should NOT match: $p)"; exit 1; }
    ok=$((ok + 1))
  done
  echo "anchor-preflight: self-test OK"
  exit 0
fi

# Resolve the written file path: prefer hook stdin JSON, fall back to env.
FILE_PATH=""
if command -v jq >/dev/null 2>&1; then
  PAYLOAD=$(cat 2>/dev/null || true)
  if [ -n "$PAYLOAD" ]; then
    FILE_PATH=$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null || true)
  fi
fi
[ -z "$FILE_PATH" ] && FILE_PATH="${CLAUDE_TOOL_INPUT_FILE_PATH:-}"

# Not a worktask artifact write → no-op (success).
[ -n "$FILE_PATH" ] || exit 0
printf '%s' "$FILE_PATH" | grep -qE "$ARTIFACT_RE" || exit 0
[ -f "$FILE_PATH" ] || exit 0

LINT="${CLAUDE_PLUGIN_ROOT:-.}/skills/worktask/scripts/cache-lint.sh"
[ -x "$LINT" ] || [ -f "$LINT" ] || exit 0

# Delegate to the canonical anchor-lint mode. Non-zero exit propagates the
# diagnostic to the producing agent (continueOnBlock in plugin.json).
exec bash "$LINT" --anchor-lint "$FILE_PATH"
