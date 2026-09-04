#!/usr/bin/env bash
# anchor-preflight — PostToolUse (Write|Edit) anchor lint for worktask
# artifacts. Runs cache-lint.sh --anchor-lint on a path matching the canonical
# .context/<stage>-N.md regex, so a bad H2 anchor surfaces at the producing
# write rather than at the DR gate.
#
# Reads tool_input.file_path from the hook stdin JSON, falling back to
# CLAUDE_TOOL_INPUT_FILE_PATH without jq. A non-zero exit shows the agent the
# diagnostic; continueOnBlock keeps a non-artifact write unblocked.
#
# Plugin root is env-first ($CLAUDE_PLUGIN_ROOT), else self-located from $0.
# --self-test asserts the gating regex.
set -eu

SELF_TEST=0
[ "${1:-}" = "--self-test" ] && SELF_TEST=1

# Canonical artifact basenames (mirrors handoff-protocol.md#stage-artifact-map).
# development alone carries an optional kebab -<stream> suffix: under TL fan-out
# each DV sub-agent writes development-N-<stream>.md before the entry agent
# merges the canonical development-N.md.
ARTIFACT_RE='\.context/((planning|architecture|coordination|developer-review|security-review|testing|documentation|release|complete-summary|retrospective|incident|ethics-review)-[0-9]+|development-[0-9]+(-[a-z0-9]+)*)\.md$'

if [ "$SELF_TEST" -eq 1 ]; then
  ok=0
  for p in \
    ".context/development-0.md" \
    ".context/development-0-swift-app.md" \
    ".context/development-2-backend.md" \
    ".context/developer-review-12.md" \
    "/abs/path/.context/planning-3.md"; do
    printf '%s' "$p" | grep -qE "$ARTIFACT_RE" || { echo "anchor-preflight: self-test FAIL (should match: $p)"; exit 1; }
  done
  for p in \
    "skills/worktask/SKILL.md" \
    ".context/state.json" \
    ".context/development.md" \
    ".context/development-0-.md" \
    ".context/development-0-Stream.md" \
    ".context/planning-0-stream.md" \
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

# An explicitly set env var always wins; otherwise derive the root from the shared
# resolver, which validates the .claude-plugin/plugin.json marker.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [ -z "$PLUGIN_ROOT" ]; then
  # A TRUNCATED library is worse than an absent one: a syntax error in a sourced file is
  # fatal under `set -e` and `||` does not rescue it. Drop -e across the source and probe
  # for the symbol afterwards, so an unusable library degrades this preflight to a no-op
  # instead of turning it into a hard block on every artifact write.
  _LIB="$(dirname -- "$0")/lib/corpflow-base.sh"
  _cf_opts=$-
  set +e
  # shellcheck source=hooks/lib/corpflow-base.sh
  [ -f "$_LIB" ] && . "$_LIB"
  case "$_cf_opts" in *e*) set -e ;; esac
  if command -v corpflow_plugin_root > /dev/null 2>&1; then
    PLUGIN_ROOT="$(corpflow_plugin_root)" || PLUGIN_ROOT=""
  fi
fi
LINT="${PLUGIN_ROOT:-.}/skills/worktask/scripts/cache-lint.sh"
[ -x "$LINT" ] || [ -f "$LINT" ] || exit 0

# Non-zero exit propagates the diagnostic to the producing agent.
exec bash "$LINT" --anchor-lint "$FILE_PATH"
