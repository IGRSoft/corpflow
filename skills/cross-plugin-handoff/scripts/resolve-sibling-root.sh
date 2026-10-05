#!/usr/bin/env bash
# @description Prints the install root of a sibling plugin as loaded for this session, so a
#              dispatch prompt can hand the sibling an absolute path instead of a search.
#              Reads only the active config dir — ${CLAUDE_CONFIG_DIR:-$HOME/.claude} — so a
#              session under an isolated config never resolves into another config's cache.
#              Resolution:
#                1. plugins/installed_plugins.json, entries keyed `<name>@<marketplace>`: the
#                   local/project entry whose projectPath is the project dir or an ancestor
#                   of it (longest wins), else the user-scope entry; its installPath.
#                2. plugins/known_marketplaces.json: when that marketplace is a `directory`
#                   source, the plugin's directory inside it replaces installPath, because
#                   Claude Code loads directory-marketplace plugins in place.
#              The chosen root must hold CORPFLOW.md or .claude-plugin/plugin.json.
#              Requires bash >= 3.2 and jq.
# @arg <plugin-name>   Sibling plugin name, e.g. apple-developer.
# @arg --self-test     Run the bundled fixture checks; prints "self-test OK".
# @arg -h | --help     Print usage on stdout.
# @env CLAUDE_CONFIG_DIR, HOME   Locate the config dir.
# @env CLAUDE_PROJECT_DIR        Project dir for scope matching (default: $PWD).
# @stdout Exit 0 only: the absolute root, one line.
# @stderr Exit 1: one "resolve-sibling-root: <reason>" line the caller records verbatim.
# @exitcode 0  Resolved and verified.
# @exitcode 1  Not installed for this session, unreadable registry, jq missing, or no marker.
# @exitcode 2  Usage error.
set -uo pipefail

SELF="${BASH_SOURCE[0]:-$0}"
# The self-test re-runs this file from inside a fixture dir, so the path must be absolute.
SELF="$(CDPATH='' cd -- "$(dirname -- "$SELF")" 2> /dev/null && pwd -P)/$(basename -- "$SELF")"

# shellcheck disable=SC2016 # the help text names the variables literally
usage() {
  printf '%s\n' \
    'Usage: resolve-sibling-root.sh <plugin-name>' \
    '       resolve-sibling-root.sh --self-test' \
    '       resolve-sibling-root.sh -h | --help' \
    '' \
    'Prints the absolute install root of <plugin-name> as loaded for this session, read' \
    'from ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins. Exit 1 with one stderr reason when' \
    'the plugin is not installed for this session or its root has no CORPFLOW.md and no' \
    '.claude-plugin/plugin.json; exit 2 on a usage error.'
}

usage_error() {
  printf >&2 'resolve-sibling-root: usage: %s\n' "$1"
  exit 2
}

not_found() {
  printf >&2 'resolve-sibling-root: %s\n' "$1"
  exit 1
}

has_marker() {
  [ -d "$1" ] && { [ -f "$1/CORPFLOW.md" ] || [ -f "$1/.claude-plugin/plugin.json" ]; }
}

# pwd -L, not -P: a config dir reached through a symlink must keep that spelling, or a
# consumer checking "is this path under CLAUDE_CONFIG_DIR" would see it leave.
normalize_dir() {
  (CDPATH='' cd -- "$1" 2> /dev/null && pwd -L)
}

# Entry order: a project-bound entry covering the project dir beats a global one; among
# those the deepest projectPath, then local over project scope, then the newest record.
# shellcheck disable=SC2016 # $name, $pl, $pp are jq variables
readonly JQ_PICK_ENTRY='
def covers($p): ($p | rtrimstr("/")) as $q
  | [$pl, $pp] | any(. != "" and (. == $q or startswith($q + "/")));
[ (.plugins // {}) | to_entries[]
  | select(.key | startswith($name + "@"))
  | (.key | ltrimstr($name + "@")) as $mkt
  | (.value | if type == "array" then .[] else . end)
  | select(type == "object" and (.installPath | type) == "string" and .installPath != "")
  | . + {mkt: $mkt} ] as $all
| ( [ $all[] | select((.projectPath // "") != "" and covers(.projectPath)) ]
    | sort_by((.projectPath | length), (if .scope == "local" then 1 else 0 end),
              (.lastUpdated // "")) | last )
  // ( [ $all[] | select((.projectPath // "") == "") ] | sort_by(.lastUpdated // "") | last )
| select(. != null) | .mkt, .installPath'

# shellcheck disable=SC2016 # $mkt is a jq variable
readonly JQ_DIR_MARKETPLACE='
.[$mkt] // empty | select((.source.source // "") == "directory")
| .installLocation // .source.path // empty | select(type == "string" and . != "")'

# A bare source name is relative to metadata.pluginRoot; ./, ../ and absolute are not.
# shellcheck disable=SC2016 # $name is a jq variable
readonly JQ_PLUGIN_SOURCE='
(.metadata.pluginRoot // "") as $pr
| [ .plugins[]? | select(.name == $name) | .source | select(type == "string") ] | first // empty
| if test("^(/|\\./|\\.\\./)") or $pr == "" then . else ($pr | rtrimstr("/")) + "/" + . end'

# <plugin-name> — prints the verified root or exits 1.
resolve() {
  local name="$1" config pfile mfile proj_l proj_p pick mkt install_path base src candidate
  config="${CLAUDE_CONFIG_DIR:-}"
  if [ -z "$config" ]; then
    [ -n "${HOME:-}" ] || not_found "neither CLAUDE_CONFIG_DIR nor HOME is set"
    config="$HOME/.claude"
  fi
  pfile="$config/plugins/installed_plugins.json"
  mfile="$config/plugins/known_marketplaces.json"
  command -v jq > /dev/null 2>&1 || not_found "jq not found on PATH"
  [ -f "$pfile" ] || not_found "no installed_plugins.json at $pfile"

  proj_l="${CLAUDE_PROJECT_DIR:-$PWD}"
  proj_p="$( (CDPATH='' cd -P -- "$proj_l" 2> /dev/null && pwd -P) || true)"
  pick="$(jq -r --arg name "$name" --arg pl "${proj_l%/}" --arg pp "${proj_p%/}" \
    "$JQ_PICK_ENTRY" "$pfile" 2> /dev/null)" \
    || not_found "cannot parse $pfile"
  mkt="$(printf '%s\n' "$pick" | sed -n 1p)"
  install_path="$(printf '%s\n' "$pick" | sed -n 2p)"
  [ -n "$install_path" ] \
    || not_found "$name is not installed for this session (no usable $name@* entry in $pfile)"

  if [ -f "$mfile" ]; then
    base="$(jq -r --arg mkt "$mkt" "$JQ_DIR_MARKETPLACE" "$mfile" 2> /dev/null || true)"
    if [ -n "$base" ] && [ -f "$base/.claude-plugin/marketplace.json" ]; then
      src="$(jq -r --arg name "$name" "$JQ_PLUGIN_SOURCE" \
        "$base/.claude-plugin/marketplace.json" 2> /dev/null || true)"
      if [ -n "$src" ]; then
        case "$src" in
          /*) candidate="$src" ;;
          *) candidate="${base%/}/$src" ;;
        esac
        candidate="$(normalize_dir "$candidate" || true)"
        if [ -n "$candidate" ] && has_marker "$candidate"; then
          printf '%s\n' "$candidate"
          return 0
        fi
      fi
    fi
  fi

  candidate="$(normalize_dir "$install_path" || true)"
  [ -n "$candidate" ] || not_found "installPath for $name is not a directory: $install_path"
  has_marker "$candidate" \
    || not_found "$candidate holds neither CORPFLOW.md nor .claude-plugin/plugin.json"
  printf '%s\n' "$candidate"
}

# Fixtures live in one mktemp dir with HOME and CLAUDE_CONFIG_DIR pointed into it, so the
# self-test can never read the operator's real registry.
self_test() {
  local t rc out
  t="$(mktemp -d 2> /dev/null)" || { printf >&2 'self-test FAIL: mktemp\n'; exit 1; }
  # shellcheck disable=SC2064 # $t is fixed now; expanding it later would be wrong if reassigned
  trap "rm -rf -- '$t'" EXIT
  mkdir -p "$t/cfg/plugins" "$t/cache/p/1.0/.claude-plugin" "$t/proj" "$t/other"
  : > "$t/cache/p/1.0/.claude-plugin/plugin.json"
  printf '{"version":2,"plugins":{"p@m":[{"scope":"user","installPath":"%s"}]}}\n' \
    "$t/cache/p/1.0" > "$t/cfg/plugins/installed_plugins.json"

  _st_case() {
    local want_rc="$1" want_out="$2" label="$3"
    shift 3
    rc=0
    out="$(cd "$t/proj" && env -u CLAUDE_PROJECT_DIR HOME="$t/other" \
      CLAUDE_CONFIG_DIR="$t/cfg" bash "$SELF" "$@" 2> /dev/null)" || rc=$?
    [ "$rc" -eq "$want_rc" ] || { printf >&2 'self-test FAIL: %s: rc %s\n' "$label" "$rc"; exit 1; }
    [ "$out" = "$want_out" ] || { printf >&2 'self-test FAIL: %s: %s\n' "$label" "$out"; exit 1; }
  }

  _st_case 0 "$t/cache/p/1.0" "user-scope installPath" p
  _st_case 1 "" "not installed" q
  _st_case 2 "" "invalid name" '../p'

  mkdir -p "$t/mkt/.claude-plugin"
  : > "$t/mkt/CORPFLOW.md"
  printf '{"name":"m","plugins":[{"name":"p","source":"./"}]}\n' \
    > "$t/mkt/.claude-plugin/marketplace.json"
  printf '{"m":{"source":{"source":"directory","path":"%s"},"installLocation":"%s"}}\n' \
    "$t/mkt" "$t/mkt" > "$t/cfg/plugins/known_marketplaces.json"
  _st_case 0 "$t/mkt" "directory marketplace in place" p

  printf 'self-test OK\n'
  exit 0
}

[ "$#" -gt 0 ] || usage_error "no arguments; see --help"
case "$1" in
  -h | --help)
    [ "$#" -eq 1 ] || usage_error "$1 takes no further arguments"
    usage
    exit 0
    ;;
  --self-test)
    [ "$#" -eq 1 ] || usage_error "--self-test takes no further arguments"
    self_test
    ;;
  -*) usage_error "unknown option: $1" ;;
esac
[ "$#" -eq 1 ] || usage_error "exactly one <plugin-name> expected"
# The name reaches jq only through --arg, so the charset guards paths, not the program.
case "$1" in
  *[!A-Za-z0-9._-]* | .* | '') usage_error "invalid plugin name: $1" ;;
esac
resolve "$1"
