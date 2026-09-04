#!/usr/bin/env bash
# build-context-set.sh — produce the used-in-context file-path set for this worktask.
#
# Inputs (env vars, all optional):
#   LEDGER_JSON      Path to a state.json (or a bare tasks{} object) to read stage metadata from.
#                    When absent, falls back to scanning .context/*.md for agent trailers.
#   CONTEXT_DIR      Defaults to ".context"
#   BASELINE_SHA     If present, scan `git log $BASELINE_SHA..HEAD` for `Agent:` trailers.
#   AUDIT_LOG        Audit log scanned for hook/script participation.
#                    Defaults to "$CONTEXT_DIR/logs/audit.jsonl".
#   CLAUDE_PLUGIN_ROOT
#                    Plugin root candidates are resolved against. Auto-discovered when
#                    unset (skills/shared/plugin-root-resolution.md).
#
# Output to stdout: newline-delimited, deduped, sorted list of PLUGIN-ROOT-relative file
# paths that exist on disk. Paths follow these patterns:
#   agents/<name>.md
#   skills/<path>/SKILL.md
#   commands/<name>.md
#   hooks/<name>.sh
#   skills/<path>/scripts/<name>.sh
#
# Existence is tested against the plugin root, NOT the process cwd. Every corpflow asset
# lives under the plugin root while this script runs from the worktask's repo, so a
# cwd-relative test dropped every candidate and returned the empty set — which
# SKILL.md § Step 5b calls indistinguishable from "the user made no edits".

set -euo pipefail

CONTEXT_DIR="${CONTEXT_DIR:-.context}"
AUDIT_LOG="${AUDIT_LOG:-$CONTEXT_DIR/logs/audit.jsonl}"

# Rungs 1 and 3 of skills/shared/plugin-root-resolution.md. Rung 2 (the skill base
# directory) is not available to a script — it is announced to the model, not exported —
# and rung 4 (the Claude Code cache) is deliberately omitted: this script always ships
# INSIDE the root it is looking for, so walking up from its own location cannot miss a
# root that exists, and guessing at a cache entry could silently profile a DIFFERENT
# installed version than the one being edited. Every candidate is validated.
find_plugin_root() {
  local candidate
  for candidate in \
    "${CLAUDE_PLUGIN_ROOT:-}" \
    "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." 2>/dev/null && pwd)" \
    "$PWD"; do
    [ -n "$candidate" ] || continue
    if [ -f "$candidate/.claude-plugin/plugin.json" ]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  # Unresolvable: fall back to cwd, which reproduces the previous behaviour rather than
  # aborting the retrospective. Reported so an empty set is never mistaken for "no edits".
  printf >&2 'build-context-set: plugin root unresolved — falling back to cwd (%s)\n' "$PWD"
  printf '%s' "$PWD"
}
PLUGIN_ROOT="$(find_plugin_root)"

# Collect raw qualified agent / command names into a temp buffer.
raw="$(mktemp)"
# Source 4 emits FILE PATHS, not `<plugin>:<name>` refs, so it bypasses normalize() —
# which would classify a path with no colon as CROSS_PLUGIN and discard it.
rawpaths="$(mktemp)"
trap 'rm -f "$raw" "$rawpaths"' EXIT

# Source 1 — the state ledger (preferred).
if [ -n "${LEDGER_JSON:-}" ] && [ -f "$LEDGER_JSON" ]; then
  # Extract metadata.agent and metadata.embedded_commands from completed tasks.
  # Tolerates jq absence by using python as fallback.
  if command -v jq >/dev/null 2>&1; then
    jq -r '
      (.tasks // .) | to_entries[] | .value |
      select(.status == "completed") |
      .metadata // {} |
      (.agent // empty), (.embedded_commands // empty | split(",") | .[])
    ' "$LEDGER_JSON" 2>/dev/null >> "$raw" || true
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$LEDGER_JSON" >> "$raw" <<'PY' || true
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
for task in (data.get("tasks", data) or {}).values():
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
  # POSIX classes, not `\s`: BSD/macOS sed and grep read `\s` as a literal `s`,
  # which leaves the extracted value with its leading space. `awk -F:` then sees
  # " corpflow" and the ref is discarded as cross-plugin.
  grep -rhE '^[[:space:]]*agent:[[:space:]]*' "$CONTEXT_DIR" 2>/dev/null \
    | sed -E 's/^[[:space:]]*agent:[[:space:]]*//; s/[[:space:]]+$//; s/^["'\'']//; s/["'\'']$//' \
    >> "$raw" || true

  grep -rhE '^[[:space:]]*embedded_commands:[[:space:]]*' "$CONTEXT_DIR" 2>/dev/null \
    | sed -E 's/^[[:space:]]*embedded_commands:[[:space:]]*//; s/[[:space:]]+$//' \
    | tr ',' '\n' \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
    >> "$raw" || true
fi

# Source 3 — git log `Agent:` trailers since BASELINE_SHA.
if [ -n "${BASELINE_SHA:-}" ]; then
  git log "${BASELINE_SHA}..HEAD" --format='%B' 2>/dev/null \
    | grep -E '^Agent:[[:space:]]*' \
    | sed -E 's/^Agent:[[:space:]]*//' \
    >> "$raw" || true
fi

# Plugin names whose `<plugin>:<name>` refs address files in THIS repo.
# `igrsoft` is corpflow's pre-v3.39.0 name; classifying those trailers as
# cross-plugin empties the context set, which silently disables the pipeline.
# The manifest name is read so a future rename cannot reintroduce that.
local_plugin_names() {
  local current=""
  # Root-relative, like every other path here: read from cwd this returned empty in the
  # production invocation, silently dropping the manifest name from the local-plugin list.
  if [ -f "$PLUGIN_ROOT/.claude-plugin/plugin.json" ] && command -v jq >/dev/null 2>&1; then
    current="$(jq -r '.name // empty' "$PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null || true)"
  fi
  printf '%s %s %s' "${current:-corpflow}" corpflow igrsoft \
    | tr ' ' '\n' | awk 'NF && !seen[$0]++' | tr '\n' ' '
}

# Normalize qualified names → file paths.
# Rules:
#   <local-plugin>:<name>       → agents/<name>.md
#   apple-developer:<name>      → (cross-plugin) — kept as raw ref; mapper drops if non-local
#   <name>:<sub> as command     → commands/<name>.md  (best-effort)
#
# The normalizer only emits LOCAL paths that exist in this repo.
normalize() {
  awk -v plugins="$1" -F: '
    BEGIN { n = split(plugins, parts, " "); for (i = 1; i <= n; i++) local_plugin[parts[i]] = 1 }
    ($1 in local_plugin) && NF == 2 {
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

# Source 4 — the audit log. `tasks.*.metadata.agent` names AGENTS only, so every hook and
# every bundled script that participated is invisible to sources 1-3 no matter how much of
# the run it drove. Four row shapes carry that participation:
#   actor "hook:<n>" / "<plugin>:hook:<n>"  -> hooks/<n>.sh   (the plugin prefix is stripped;
#                                              a sibling plugin's hook has no local path, and
#                                              the existence test below drops it)
#   metadata.tool "<n>.sh"                  -> resolved by basename
#   metadata.via  "<n>.sh"                  -> same; this is the key the orchestrator's own
#                                              helper invocations actually use
#   subject on a metadata.kind == "tool" row -> a bare helper name, `.sh` implied
# Basenames are resolved rather than assumed: a helper's directory is not derivable from
# its name, and hardcoding one would silently stop finding it after any move.
resolve_script_path() {
  local base="$1" p
  case "$base" in */*|"") return 0 ;; esac   # already a path, or empty — nothing to resolve
  for p in "hooks/$base" "scripts/$base"; do
    [ -f "$PLUGIN_ROOT/$p" ] && { printf '%s\n' "$p"; return 0; }
  done
  # Bounded to the two nesting levels corpflow actually uses, so this never walks the tree.
  for p in "$PLUGIN_ROOT"/skills/*/scripts/"$base" "$PLUGIN_ROOT"/hooks/lib/"$base"; do
    [ -f "$p" ] && { printf '%s\n' "${p#"$PLUGIN_ROOT"/}"; return 0; }
  done
  return 0
}

if [ -f "$AUDIT_LOG" ] && command -v jq >/dev/null 2>&1; then
  # The tolerant read below drops malformed rows silently, so a corrupt log looks
  # identical to one with no matching rows. Name the drops on stderr; stdout keeps
  # carrying only the path set.
  _bcs_total=$(grep -c '[^[:space:]]' "$AUDIT_LOG" || true)
  _bcs_parsed=$(jq -ncR '[ inputs | select(length > 0) | fromjson? | objects ] | length' "$AUDIT_LOG" 2>/dev/null || echo 0)
  if [ "$_bcs_total" -gt "$_bcs_parsed" ]; then
    printf >&2 'warn: %s: %d unparseable audit row(s) skipped\n' "$AUDIT_LOG" "$((_bcs_total - _bcs_parsed))"
  fi
  # `fromjson? | objects` for the same reason branch-name.sh's already_named uses it: a
  # well-formed non-object line parses and then dies on `.metadata`, aborting the scan.
  jq -rs -R '
    [ split("\n")[] | fromjson? | objects ] | .[]
    | ( (.actor // "") | select(test("(^|:)hook:")) | sub(".*hook:"; "") | "HOOK\t" + . ),
      ( (.metadata.tool // "") | select(endswith(".sh")) | "SCRIPT\t" + . ),
      ( (.metadata.via // "") | select(endswith(".sh")) | "SCRIPT\t" + . ),
      ( select((.metadata.kind // "") == "tool") | (.subject // "")
        | select(. != "" and (test("^[A-Za-z][A-Za-z0-9._-]*$")))
        | "SCRIPT\t" + (if endswith(".sh") then . else . + ".sh" end) )
  ' "$AUDIT_LOG" 2>/dev/null \
    | sort -u \
    | while IFS="$(printf '\t')" read -r kind name; do
        case "$kind" in
          HOOK)   printf 'hooks/%s.sh\n' "$name" ;;
          SCRIPT) resolve_script_path "$name" ;;
        esac
      done >> "$rawpaths" || true
fi

{
  normalize "$(local_plugin_names)" < "$raw" | grep -v '^CROSS_PLUGIN:' || true
  cat "$rawpaths"
} \
  | awk 'NF && !seen[$0]++' \
  | while read -r path; do
      # Existence is tested against PLUGIN_ROOT; the emitted path stays root-relative so
      # Step 4's mapper compares like with like. `|| true`: a non-existent candidate is
      # normal (each qualified ref probes agent/command/skill paths), and under `set -e`
      # its non-zero status would otherwise become the script's exit code.
      [ -f "$PLUGIN_ROOT/$path" ] && echo "$path" || true
    done \
  | sort -u
