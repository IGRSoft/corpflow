#!/usr/bin/env bash
# @description permission-denied-lib.sh — the one derivation of a permission denial's detail,
#   dedupe key and prior-row lookup, sourced by hooks/permission-denied.sh and
#   skills/worktask/scripts/permission-park.sh. Both write the same audit row from opposite
#   sides of a denial; a second derivation of the key is how they would disagree and log twice.
#
#   Symbol names carry no corpflow_ prefix: that namespace is the model-switch-lib surface
#   tests/shell/meta/hook-symbol-parity.bats enumerates.
#
#   Symbols: pd_detail_from_event, pd_normalize_detail, pd_key_command, pd_dedupe_key,
#   pd_command_head, pd_audit_meta, pd_audit_has_key, pd_audit_has_twin, PD_HEAD_MAX,
#   PD_JQ_DEFS (pd_bound, pd_truncated, pd_fence, pd_rule, pd_detail, pd_mask).
#
#   Audit rows never carry the denied command, classifier_reason, allow_rule or tool_input:
#   audit.jsonl is committed, and a denied call is the one most likely to hold a credential.
#   Rows carry pd_audit_meta's redacted shape. The full detail stays outside the log, in the
#   ledger's and the stage artifact's blocked_on, the resume instruction and the user prompt.
#   The dedupe key is derived from the masked command (pd_key_command), never the unmasked text.
#
# Minimum shell: bash 3.2+. Sets no shell options; every symbol returns 0 with empty stdout
# on failure, except the pd_audit_has_* predicates.

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  printf >&2 'permission-denied-lib.sh: this is a library — source it, do not execute it directly\n'
  exit 2
fi
[ -n "${_PD_LIB:-}" ] && return 0
_PD_LIB=1
_PD_LIB_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2> /dev/null && pwd -P)" || _PD_LIB_DIR=""
PD_HEAD_MAX=80

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
# pd_mask: a value is a double-quoted run, a single-quoted run or a bare run, and a quoted value
# is masked whole, quotes included, because agents quote passwords that hold spaces. A quote
# with no closing partner runs to the end, since a 512 bound can cut the closer off. Userinfo
# runs to the last @ before a /, whitespace or quote, as a password may itself contain @. The
# runs beside the keyword alternation are capped at 64: unbounded, they backtrack polynomially
# on a crafted 512-character command, and the hook has 5 s to mask it twice.
def pd_mask:
  gsub("(?<p>[a-z][a-z0-9+.-]*://)[^\\s/\"\u0027`]+@"; "\(.p)[masked]@"; "i")
  | gsub("(?<k>(?:proxy-)?authorization[\"\u0027]?\\s*[:=]\\s*)(?:(?<s>bearer|basic|token|digest|negotiate)\\s+)?[^\\s\"\u0027`]+";
      "\(.k)\(if .s then .s + " " else "" end)[masked]"; "i")
  | gsub("\\b(?<s>bearer|basic)\\s+[A-Za-z0-9._~+/=-]{8,}"; "\(.s) [masked]"; "i")
  | gsub("(?<f>(?:^|\\s)(?:-u|--user|--proxy-user))(?<e>\\s+|=)(?:\"[^\"]*:[^\"]*(?:\"|$)|\u0027[^\u0027]*:[^\u0027]*(?:\u0027|$)|[^\\s\"\u0027`]*:[^\\s\"\u0027`]*)";
      "\(.f)\(.e)[masked]")
  | gsub("(?<f>--?[a-z0-9_-]{0,64}(?:token|password|passwd|secret|api[_-]?key|apikey|access[_-]?key|private[_-]?key|credentials?)[a-z0-9_-]{0,64})(?<e>=|\\s+)(?:\"[^\"]*(?:\"|$)|\u0027[^\u0027]*(?:\u0027|$)|[^\\s\"\u0027`]+)";
      "\(.f)\(.e)[masked]"; "i")
  | gsub("(?<k>[a-z0-9_.-]{0,64}(?:token|password|passwd|secret|api[_-]?key|apikey|access[_-]?key|private[_-]?key|client[_-]?secret|credentials?|session[_-]?id|cookie)[a-z0-9_.-]{0,64}[\"\u0027]?\\s*[:=]\\s*)(?:\"[^\"]*(?:\"|$)|\u0027[^\u0027]*(?:\u0027|$)|[^\\s\"\u0027`&;,]+)";
      "\(.k)[masked]"; "i")
  | gsub("\\b(?:AKIA|ASIA)[0-9A-Z]{16}\\b|\\bgh[pousr]_[A-Za-z0-9]{20,}|\\bgithub_pat_[A-Za-z0-9_]{20,}|\\bglpat-[A-Za-z0-9_-]{20,}|\\bsk-[A-Za-z0-9_-]{16,}|\\bxox[abprs]-[A-Za-z0-9-]{10,}|\\bAIza[0-9A-Za-z_-]{30,}|\\bnpm_[A-Za-z0-9]{30,}|\\beyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}";
      "[masked]");
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

# pd_key_command <command> — the command as every dedupe key hashes it: bounded to 512, then
# masked. A row's command_head shows everything around each [masked], so a key over the raw text
# would let a guessed secret be confirmed offline. Empty on failure; a caller holding a non-empty
# command must then write no key at all.
pd_key_command() {
  command -v jq > /dev/null 2>&1 || return 0
  local _pd_k
  _pd_k=$(printf '%s' "${1:-}" | jq -Rrs "$PD_JQ_DEFS"'pd_bound(512) | pd_mask' 2> /dev/null) || _pd_k=""
  printf '%s' "$_pd_k"
  return 0
}

# pd_audit_has_key <audit.jsonl> <key> — 0 when a permission_denied row already carries key.
# A fixed-string grep, not a parse: one malformed line elsewhere must not hide the match.
pd_audit_has_key() {
  [ -f "${1:-}" ] && [ -n "${2:-}" ] || return 1
  grep -F '"action":"permission_denied"' -- "$1" 2> /dev/null \
    | grep -Fq "\"dedupe_key\":\"$2\"" 2> /dev/null
}

# pd_audit_has_twin <audit.jsonl> <tool> <key_command> <task_id>... — 0 when a permission_denied
# row carries the key this tool and pd_key_command output derive under any of the given
# subjects; the caller masks once, before the loop, rather than once per subject. Rows hold
# no command to compare, so a twin written under another subject (a hook row that resolved to
# `unknown`, or a fallback row for the task the hook could not name) is found by re-deriving
# its key.
pd_audit_has_twin() {
  local _pd_audit="${1:-}" _pd_tool="${2:-}" _pd_cmd="${3:-}" _pd_id
  [ -f "$_pd_audit" ] || return 1
  [ "$#" -ge 4 ] || return 1
  shift 3
  for _pd_id in "$@"; do
    [ -n "$_pd_id" ] || continue
    pd_audit_has_key "$_pd_audit" "$(pd_dedupe_key "$_pd_id" "$_pd_tool" "$_pd_cmd")" && return 0
  done
  return 1
}

# pd_command_head <command> — `{"command_head":"…","truncated":bool}` for an audit row, or `{}`
# when no head may be written. Secret shapes are masked, then host paths are scrubbed, and only
# then is the text cut to PD_HEAD_MAX: masking first keeps the literal out of the scrub's
# pipeline and lets the patterns see the original token boundaries, and cutting last means a
# bound can never leave half a secret that the patterns would no longer recognise.
#
# path-scrub.sh is consumed per its sourcing contract: `[ -r ]` before `.`, because `.` on a
# missing file exits the caller. A missing file, function or pattern, or a non-zero scrub,
# yields `{}`: an unscrubbed head would carry the host paths the scrub exists to remove.
pd_command_head() {
  command -v jq > /dev/null 2>&1 || { printf '{}'; return 0; }
  local _pd_head
  _pd_head=$(
    set -o pipefail
    _pd_scrub="${_PD_LIB_DIR:-}/../../skills/shared/scripts/path-scrub.sh"
    [ -n "${_PD_LIB_DIR:-}" ] && [ -r "$_pd_scrub" ] || exit 1
    # shellcheck source=/dev/null
    . "$_pd_scrub" > /dev/null 2>&1 || exit 1
    command -v corpflow_path_scrub > /dev/null 2>&1 || exit 1
    [ -n "${CORPFLOW_HOST_PATH_ERE:-}" ] && [ -n "${CORPFLOW_DRIVE_PATH_ERE:-}" ] || exit 1
    _pd_masked=$(pd_key_command "${1:-}")
    [ -n "$_pd_masked" ] || [ -z "${1:-}" ] || exit 1
    _pd_clean=$(printf '%s\n' "$_pd_masked" | corpflow_path_scrub) || exit 1
    printf '%s' "$_pd_clean" | jq -Rsc --argjson n "$PD_HEAD_MAX" "$PD_JQ_DEFS"'
      pd_bound(4096) | {command_head: pd_bound($n), truncated: (length > $n)}'
  ) || _pd_head=""
  case "$_pd_head" in
    '{"command_head":'*) printf '%s' "$_pd_head" ;;
    *) printf '{}' ;;
  esac
  return 0
}

# pd_audit_meta <tool> <command> <dedupe_key> — the one redacted metadata object every
# permission audit row starts from: {tool, dedupe_key} plus pd_command_head's fields.
pd_audit_meta() {
  command -v jq > /dev/null 2>&1 || return 0
  jq -cn --arg t "${1:-}" --arg k "${3:-}" --argjson h "$(pd_command_head "${2:-}")" "$PD_JQ_DEFS"'
    {tool: ($t | pd_bound(64)), dedupe_key: $k} + $h' 2> /dev/null || true
  return 0
}
