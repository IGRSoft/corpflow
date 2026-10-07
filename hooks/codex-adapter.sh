#!/usr/bin/env bash
# Codex hook boundary: normalize host paths and payloads before entering shared Claude-era hooks.
set -u

MODE=passthrough
TARGET=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --target) TARGET="${2:-}"; shift 2 ;;
    --) shift; break ;;
    *) printf >&2 'codex-adapter: unknown argument: %s\n' "$1"; exit 2 ;;
  esac
done

SELF_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P) || exit 0
# shellcheck source=hooks/lib/corpflow-base.sh
. "$SELF_DIR/lib/corpflow-base.sh" || exit 0

PAYLOAD_FILE=$(mktemp "${TMPDIR:-/tmp}/corpflow-codex-hook.XXXXXX") || exit 0
NORMALIZED_FILE=$(mktemp "${TMPDIR:-/tmp}/corpflow-codex-normalized.XXXXXX") || {
  rm -f "$PAYLOAD_FILE"
  exit 0
}
trap 'rm -f "$PAYLOAD_FILE" "$NORMALIZED_FILE" "${PATCH_FILE:-}"' EXIT
cat > "$PAYLOAD_FILE"

PAYLOAD_CWD=""
if command -v jq >/dev/null 2>&1; then
  PAYLOAD_CWD=$(jq -r '.cwd // empty | strings' "$PAYLOAD_FILE" 2>/dev/null) || PAYLOAD_CWD=""
fi
corpflow_init_base_paths "$PAYLOAD_CWD" || exit 0

# Legacy variables exist only at this adapter boundary while older shared hooks migrate to BASE_*.
CLAUDE_PLUGIN_ROOT="$BASE_PLUGIN_ROOT"
export CLAUDE_PLUGIN_ROOT
if [ -n "${BASE_PLUGIN_DATA:-}" ]; then
  CLAUDE_PLUGIN_DATA="$BASE_PLUGIN_DATA"
  export CLAUDE_PLUGIN_DATA
fi
if [ -n "${WORKSPACE_ROOT:-}" ]; then
  CLAUDE_PROJECT_DIR="$WORKSPACE_ROOT"
  export CLAUDE_PROJECT_DIR
fi

TARGET_PATH=$(corpflow_plugin_path "$TARGET") || exit 0
[ -f "$TARGET_PATH" ] || exit 0

normalize_tool() {
  command -v jq >/dev/null 2>&1 || { cp "$PAYLOAD_FILE" "$NORMALIZED_FILE"; return; }
  local first_path absolute_path=""
  first_path=$(patch_paths | head -n 1)
  if [ -n "$first_path" ]; then
    absolute_path=$(patch_absolute_path "$first_path") || absolute_path=""
  fi
  jq --arg patch_path "$absolute_path" '
    if .tool_name == "spawn_agent" then
      .tool_name = "Agent"
      | .tool_input = ((.tool_input // {}) as $i
          | {subagent_type: ($i.task_name // "codex-agent"), prompt: ($i.message // "")})
    elif .tool_name == "apply_patch" then
      .tool_name = "Write"
      | if $patch_path != "" then .tool_input = {file_path: $patch_path} else . end
    else . end
  ' "$PAYLOAD_FILE" > "$NORMALIZED_FILE" 2>/dev/null || cp "$PAYLOAD_FILE" "$NORMALIZED_FILE"
}

normalize_decision() {
  command -v jq >/dev/null 2>&1 || { cp "$PAYLOAD_FILE" "$NORMALIZED_FILE"; return; }
  jq '
    (.tool_input.questions // []) as $questions
    | ((.tool_response.answers? // {})
       | if type == "object" then . else {} end) as $answers
    | .tool_name = "AskUserQuestion"
    | .tool_response = ((.tool_response // {})
        | if type == "object" then . else {content: .} end
        | .answers = (reduce $questions[] as $q ({};
            .[$q.question] = ($answers[$q.id].answers // $answers[$q.id] // []))))
  ' "$PAYLOAD_FILE" > "$NORMALIZED_FILE" 2>/dev/null || cp "$PAYLOAD_FILE" "$NORMALIZED_FILE"
}

normalize_subagent() {
  command -v jq >/dev/null 2>&1 || { cp "$PAYLOAD_FILE" "$NORMALIZED_FILE"; return; }
  local state agent_id agent_type
  state="${WORKSPACE_ROOT:-}/.context/state.json"
  agent_id=$(jq -r '.agent_id // empty | strings' "$PAYLOAD_FILE" 2>/dev/null) || agent_id=""
  agent_type=""
  if [ -n "$agent_id" ] && [ -f "$state" ]; then
    agent_type=$(jq -r --arg aid "$agent_id" '[.facts.dispatched_agents[]? | select(.agent_id == $aid)][-1].subagent_type // empty' "$state" 2>/dev/null) || agent_type=""
  fi
  jq --arg at "$agent_type" '
    if $at != "" then .agent_type = $at else . end
  ' "$PAYLOAD_FILE" > "$NORMALIZED_FILE" 2>/dev/null || cp "$PAYLOAD_FILE" "$NORMALIZED_FILE"
}

# Resolve existing parents physically, including symlinks, while allowing new files and
# directories. Keep the raw patch spelling separately for patch_added_content's lookup.
patch_absolute_path() {
  local path="$1" depth="${2:-0}" root parent tail="" part resolved target
  [ "$depth" -lt 40 ] || return 1
  root=$(CDPATH='' cd -- "${WORKSPACE_ROOT:-${PAYLOAD_CWD:-.}}" && pwd -P) || return 1
  case "$path" in /*) ;; *) path="$root/$path" ;; esac
  case "$path" in */../* | */.. | *$'\t'* | *$'\r'*) return 1 ;; esac
  parent="$path"
  while [ ! -e "$parent" ] && [ ! -L "$parent" ]; do
    part="${parent##*/}"
    [ -z "$part" ] || [ "$part" = . ] || tail="/$part$tail"
    parent="${parent%/*}"
    [ -n "$parent" ] || parent=/
  done
  if [ -d "$parent" ]; then
    resolved=$(CDPATH='' cd -- "$parent" && pwd -P) || return 1
  else
    if [ -L "$parent" ]; then
      target=$(readlink "$parent") || return 1
      case "$target" in /*) ;; *) target="$(dirname -- "$parent")/$target" ;; esac
      patch_absolute_path "$target$tail" "$((depth + 1))"
      return $?
    fi
    resolved=$(CDPATH='' cd -- "$(dirname -- "$parent")" && pwd -P) || return 1
    resolved="$resolved/$(basename -- "$parent")"
  fi
  resolved="${resolved%/}$tail"
  case "$resolved" in "${root%/}"/*) printf '%s' "$resolved" ;; *) return 1 ;; esac
}

patch_paths() {
  local path
  command -v jq >/dev/null 2>&1 || return 0
  jq -r '.tool_input.patch // .tool_input.command // .tool_input.input // empty | strings' "$PAYLOAD_FILE" 2>/dev/null \
    | awk '/^\*\*\* (Add|Update|Delete) File: / { sub(/^\*\*\* (Add|Update|Delete) File: /, ""); print }' \
    | awk 'NF && !seen[$0]++' \
    | while IFS= read -r path; do
        patch_absolute_path "$path" > /dev/null && printf '%s\n' "$path"
      done
}

patch_added_content() {
  local wanted="$1"
  command -v jq >/dev/null 2>&1 || return 0
  jq -r '.tool_input.patch // .tool_input.command // .tool_input.input // empty | strings' "$PAYLOAD_FILE" 2>/dev/null \
    | awk -v wanted="$wanted" '
        /^\*\*\* (Add|Update|Delete) File: / {
          path = $0
          sub(/^\*\*\* (Add|Update|Delete) File: /, "", path)
          active = (path == wanted)
          next
        }
        /^\*\*\* / { active = 0; next }
        active && /^\+/ && !/^\+\+\+/ { print substr($0, 2) }
      '
}

run_patch_mode() {
  local event="$1" path absolute added rc=0 one_rc output=""
  PATCH_FILE=$(mktemp "${TMPDIR:-/tmp}/corpflow-codex-paths.XXXXXX") || return 0
  patch_paths > "$PATCH_FILE"
  [ -s "$PATCH_FILE" ] || return 0
  while IFS= read -r path || [ -n "$path" ]; do
    absolute=$(patch_absolute_path "$path") || continue
    if [ "$event" = pre ]; then
      added=$(patch_added_content "$path")
      jq --arg p "$absolute" --arg content "$added" '
        .tool_name = "Write"
        | .tool_input = {file_path: $p, content: $content}
      ' "$PAYLOAD_FILE" > "$NORMALIZED_FILE" 2>/dev/null || continue
    else
      jq --arg p "$absolute" '.tool_name = "Write" | .tool_input = {file_path: $p}' \
        "$PAYLOAD_FILE" > "$NORMALIZED_FILE" 2>/dev/null || continue
    fi
    one_rc=0
    output=$(bash "$TARGET_PATH" "$@" < "$NORMALIZED_FILE") || one_rc=$?
    if [ -n "$output" ]; then printf '%s\n' "$output"; return "$one_rc"; fi
    [ "$one_rc" -eq 0 ] || rc="$one_rc"
  done < "$PATCH_FILE"
  return "$rc"
}

case "$MODE" in
  passthrough) cp "$PAYLOAD_FILE" "$NORMALIZED_FILE" ;;
  tool) normalize_tool ;;
  decision) normalize_decision ;;
  subagent) normalize_subagent ;;
  patch-pre) run_patch_mode pre "$@"; exit $? ;;
  patch-post) run_patch_mode post "$@"; exit $? ;;
  *) exit 0 ;;
esac

exec bash "$TARGET_PATH" "$@" < "$NORMALIZED_FILE"
