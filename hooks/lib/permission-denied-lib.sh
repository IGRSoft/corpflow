#!/usr/bin/env bash
# @description permission-denied-lib.sh — the one derivation of a permission denial's detail,
#   dedupe key and prior-row lookup, sourced by hooks/permission-denied.sh and
#   skills/worktask/scripts/permission-park.sh. Both write the same audit row from opposite
#   sides of a denial; a second derivation of the key is how they would disagree and log twice.
#
#   Symbol names carry no corpflow_ prefix: that namespace is the model-switch-lib surface
#   tests/shell/meta/hook-symbol-parity.bats enumerates.
#
#   Symbols: pd_detail_from_event, pd_normalize_detail, pd_dedupe_key, pd_audit_has_key,
#   pd_audit_has_twin, PD_JQ_DEFS (pd_bound, pd_truncated, pd_fence, pd_rule, pd_detail).
#
# Minimum shell: bash 3.2+. Sets no shell options; every symbol returns 0 with empty stdout
# on failure, except the pd_audit_has_* predicates.

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  printf >&2 'permission-denied-lib.sh: this is a library — source it, do not execute it directly\n'
  exit 2
fi
[ -n "${_PD_LIB:-}" ] && return 0
_PD_LIB=1

# Denied-command text is untrusted and reaches both a user prompt and the committed audit
# log, so every field is bounded before either sees it. Control characters and the U+2028/2029
# separators become spaces; Unicode format characters (\p{Cf}: bidi overrides and isolates,
# zero-width characters, BOM, soft hyphen, tag characters) are removed outright, because they
# render as nothing and can make the command a user pastes differ from the one they read.
# shellcheck disable=SC2016  # jq program text: its $names are jq variables, not shell ones
PD_JQ_DEFS='
def pd_bound($n): (. // "") | tostring | gsub("\\p{Cf}"; "") | gsub("[[:cntrl:]\u2028\u2029]"; " ")
  | sub("^ +"; "") | sub(" +$"; "")
  | if length > $n then .[0:($n - 1)] + "…" else . end;
def pd_truncated($n): length == $n and endswith("…");
def pd_fence: . as $s
  | ([$s | match("`+"; "g") | .length] | max // 0) as $run
  | ([3, $run + 1] | max) as $w
  | ([range(0; $w)] | map("`") | add) as $f
  | "\($f)\n\($s)\n\($f)";
def pd_rule($tool; $cmd):
  if $tool == "" then ""
  elif $cmd == "" or ($tool | test("^mcp__")) then $tool
  else "\($tool)(\($cmd))" end;
def pd_detail($tool; $cmd; $reason; $rule):
  ($tool | pd_bound(64)) as $t
  | ($cmd | pd_bound(512)) as $c
  | {tool: $t, command: $c, classifier_reason: ($reason | pd_bound(512)),
     allow_rule: ((if ($rule // "") == "" then pd_rule($t; $c) else $rule end) | pd_bound(600))};
'

# pd_detail_from_event <payload> — the four-key detail from a Claude Code PermissionDenied
# payload (tool_name, tool_input, reason); empty when the payload names no tool.
pd_detail_from_event() {
  command -v jq > /dev/null 2>&1 || return 0
  printf '%s' "${1:-}" | jq -c "$PD_JQ_DEFS"'
    select(type == "object" and ((.tool_name // "") | pd_bound(64) | length) > 0)
    | (.tool_name | pd_bound(64)) as $tool
    | (.tool_input // {}) as $in
    | (if ($in | type) != "object" then ($in | tojson)
       elif $tool == "Bash" then ($in.command // "")
       elif $in.file_path != null then $in.file_path
       elif $in.url != null then $in.url
       elif $in.path != null then $in.path
       else ($in | tojson) end) as $cmd
    | pd_detail($tool; $cmd; .reason; "")
  ' 2> /dev/null || true
  return 0
}

# pd_normalize_detail <json> — re-bounds a caller-supplied detail and fills allow_rule when
# absent; empty unless tool is a non-empty string.
pd_normalize_detail() {
  command -v jq > /dev/null 2>&1 || return 0
  printf '%s' "${1:-}" | jq -c "$PD_JQ_DEFS"'
    select(type == "object" and (.tool | type) == "string" and (.tool | length) > 0)
    | pd_detail(.tool; .command; .classifier_reason; .allow_rule)
  ' 2> /dev/null || true
  return 0
}

# pd_dedupe_key <task_id> <tool> <command> — first 16 hex of sha256("task:tool:command").
# With no sha256 tool, two POSIX cksum CRCs (the input, then the input reversed in field order)
# stand in: weaker, but the hook and the helper run on one host and derive it identically, so
# the key still pairs their rows where an empty key would pair nothing.
pd_dedupe_key() {
  local _pd_in _pd_sum="" _pd_a _pd_b
  _pd_in=$(printf '%s:%s:%s' "${1:-}" "${2:-}" "${3:-}")
  if command -v shasum > /dev/null 2>&1; then
    _pd_sum=$(printf '%s' "$_pd_in" | shasum -a 256 2> /dev/null) || _pd_sum=""
  elif command -v sha256sum > /dev/null 2>&1; then
    _pd_sum=$(printf '%s' "$_pd_in" | sha256sum 2> /dev/null) || _pd_sum=""
  fi
  _pd_sum="${_pd_sum%% *}"
  if [ -z "$_pd_sum" ] && command -v cksum > /dev/null 2>&1; then
    _pd_a=$(printf '%s' "$_pd_in" | cksum 2> /dev/null) || _pd_a=""
    _pd_b=$(printf '%s:%s:%s' "${3:-}" "${2:-}" "${1:-}" | cksum 2> /dev/null) || _pd_b=""
    _pd_a="${_pd_a%% *}" _pd_b="${_pd_b%% *}"
    case "$_pd_a$_pd_b" in '' | *[!0-9]*) _pd_sum="" ;; *) _pd_sum=$(printf '%08x%08x' "$_pd_a" "$_pd_b") ;; esac
  fi
  printf '%s' "${_pd_sum:0:16}"
  return 0
}

# pd_audit_has_key <audit.jsonl> <key> — 0 when a permission_denied row already carries key.
# A fixed-string grep, not a parse: one malformed line elsewhere must not hide the match.
pd_audit_has_key() {
  [ -f "${1:-}" ] && [ -n "${2:-}" ] || return 1
  grep -F '"action":"permission_denied"' -- "$1" 2> /dev/null \
    | grep -Fq "\"dedupe_key\":\"$2\"" 2> /dev/null
}

# pd_audit_has_twin <audit.jsonl> <tool> <command> [unknown] — 0 when a permission_denied row
# for the same tool and command exists; with `unknown`, only a row whose subject was never
# resolved to a task. That unresolved row keys on "unknown", so the key alone cannot pair it.
pd_audit_has_twin() {
  [ -f "${1:-}" ] || return 1
  command -v jq > /dev/null 2>&1 || return 1
  jq -nRe --arg tool "${2:-}" --arg cmd "${3:-}" --arg only "${4:-any}" '
    [inputs | fromjson? | select(type == "object" and .action == "permission_denied"
      and .metadata.tool == $tool and .metadata.command == $cmd
      and ($only != "unknown" or .subject == "unknown"))] | length > 0
  ' "$1" > /dev/null 2>&1
}
