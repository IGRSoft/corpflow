#!/usr/bin/env bash
# @description user-decision-record.sh — one script, two manifest entries. PostToolUse
#   (AskUserQuestion) records one ledger row per genuinely answered question; PreToolUse
#   (Write|Edit|Bash) denies a direct write to the ledger or a shell command that visibly
#   touches it. The event comes from the payload's own `hook_event_name`, never argv, so a
#   manifest entry cannot register this script against a mode its stdin disagrees with.
#
#   `--lib-only`: sourced (not executed) by the selftest, so it can call the functions below
#   directly against its own fixtures without this file's own stdin dispatch running.
#
#   Every refusal here writes no ledger row and, once the event/tool/id shape itself is sound,
#   one `user_decision_refused` audit row naming only the reason — never the question or answer.
#   Exit 0 on every path: a hook failure must never break the session it observes.
#
# Usage: cat payload.json | user-decision-record.sh
#        . user-decision-record.sh --lib-only   # selftest only
set -u

# _ud_fold <text> -> sets FOLDED to <text> with the two non-ASCII characters APFS folds onto ASCII
# letters, U+017F (long s -> s) and U+212A (Kelvin -> k), rewritten, raw or as JSON \u escapes;
# nocasematch folds neither. sed rather than ${x//}, which is superlinear on bash 3.2.
# rc 1 when a fold was needed and sed failed: FOLDED is then the unfolded text, and every caller
# must fail closed, since the unfolded spelling is exactly the one the name checks miss.
_ud_fold() {
  FOLDED="$1"
  case "$1" in
    *$'\xc5\xbf'* | *$'\xe2\x84\xaa'* | *'\u017'[fF]* | *'\u212'[aA]*)
      FOLDED=$(printf '%s' "$1" | LC_ALL=C sed -e $'s/\xc5\xbf/s/g' -e $'s/\xe2\x84\xaa/k/g' \
        -e 's/\\u017[fF]/s/g' -e 's/\\u212[aA]/k/g') && [ -n "$FOLDED" ] && return 0
      FOLDED="$1"
      return 1
      ;;
  esac
  return 0
}

# Hot path: a payload naming none of the strings do_pre and do_post act on exits before any lib
# or jq. `$(cat)`, not `read -d ''`: bash reads a pipe a byte per syscall, slower on big Writes.
if [ "${1:-}" != "--lib-only" ]; then
  PAYLOAD=""
  [ -t 0 ] || PAYLOAD=$(cat 2> /dev/null)
  [ -n "$PAYLOAD" ] || exit 0
  # Case-blind: on a case-insensitive volume DECISIONS.JSONL is the same file.
  # A failed fold cannot rule the payload out, so it goes on to do_pre, which denies.
  if _ud_fold "$PAYLOAD"; then
    shopt -s nocasematch
    case "$FOLDED" in
      *decisions.jsonl* | *user-decision-record.sh* | *AskUserQuestion*) : ;;
      *) exit 0 ;;
    esac
    shopt -u nocasematch
  fi
fi

_HOOK_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" 2> /dev/null && pwd -P)"

for _ud_libfile in model-switch-lib.sh lib/command-head-lib.sh lib/permission-denied-lib.sh lib/user-decision-lib.sh; do
  _CF_OPTS=$-
  set +e
  # shellcheck source=/dev/null
  [ -f "$_HOOK_DIR/$_ud_libfile" ] && . "$_HOOK_DIR/$_ud_libfile"
  case "$_CF_OPTS" in *e*) set -e ;; esac
done
set +e

UD_AUDIT_CTX=""

# _ud_icase_has <haystack> <needle> / _ud_icase_eq <a> <b> / _ud_icase_under <path> <dir> —
# case-blind name tests, leaving the caller's nocasematch setting as it found it.
_ud_icase_has() {
  local r=1 was=0
  shopt -q nocasematch && was=1
  shopt -s nocasematch
  case "$1" in *"$2"*) r=0 ;; esac
  [ "$was" -eq 1 ] || shopt -u nocasematch
  return "$r"
}
_ud_icase_eq() {
  local r=1 was=0
  shopt -q nocasematch && was=1
  shopt -s nocasematch
  [[ $1 == "$2" ]] && r=0
  [ "$was" -eq 1 ] || shopt -u nocasematch
  return "$r"
}
_ud_icase_under() {
  local r=1 was=0
  shopt -q nocasematch && was=1
  shopt -s nocasematch
  [[ $1 == "$2"/* ]] && r=0
  [ "$was" -eq 1 ] || shopt -u nocasematch
  return "$r"
}
_UD_LEDGER_ALLOW_RE='^(cat|head|tail|wc|grep|jq|ls|stat|file|shasum|sha256sum)$'
# git is deliberately absent from BOTH arms. It is a configurable command executor — `git -c
# alias.x='!bash <hook>' x`, `git difftool -x bash`, `GIT_EXTERNAL_DIFF=<hook> git diff`, pagers
# and textconv all run arbitrary programs — so no substring guard over one command line can admit
# it safely. Inspecting the hook with git still works from any command that does not name the
# script itself (`git diff hooks/`, `git checkout -- hooks/`), which this guard never sees.
_UD_HOOK_ALLOW_RE='^(cat|head|tail|wc|grep|jq|ls|stat|file|shasum|sha256sum|shellcheck)$'

# _ud_refuse <ctx> <reason> [<tool_use_id>] — one user_decision_refused row; tool_use_id is
# folded in only once P2 (event/tool/id shape) has already passed.
_ud_refuse() {
  local ctx="$1" reason="$2" tuid="${3:-}" meta task
  command -v corpflow_hook_audit_row > /dev/null 2>&1 || return 0
  task=$(corpflow_audit_task_id "$ctx")
  if [ -n "$tuid" ]; then
    meta=$(jq -cn --arg r "$reason" --arg t "$tuid" '{reason: $r, tool_use_id: $t}' 2> /dev/null)
  else
    meta=$(jq -cn --arg r "$reason" '{reason: $r}' 2> /dev/null)
  fi
  [ -n "$meta" ] || meta="{}"
  corpflow_hook_audit_row --ctx "$ctx" --actor "hook:user-decision" --action user_decision_refused \
    --result skipped --subject AskUserQuestion --task-id "$task" --meta "$meta"
  return 0
}

# _ud_cb <id> <tool_use_id> <row_sha256> <item> — the ud_append_call callback: one
# user_decision_recorded row per appended line, confirmed by re-reading the log; a miss gets a
# second row with result degraded rather than a silent gap.
_ud_cb() {
  local id="$1" tuid="$2" sha="$3" item="${4:-}" meta audit task
  task=$(corpflow_audit_task_id "$UD_AUDIT_CTX")
  meta=$(jq -cn --arg id "$id" --arg t "$tuid" --arg s "$sha" --arg i "$item" \
    '{decision_id: $id, tool_use_id: $t, row_sha256: $s, item: (if $i == "" then null else $i end)}' 2> /dev/null)
  [ -n "$meta" ] || meta="{}"
  corpflow_hook_audit_row --ctx "$UD_AUDIT_CTX" --actor "hook:user-decision" --action user_decision_recorded \
    --result ok --subject "$id" --task-id "$task" --meta "$meta"
  audit="$UD_AUDIT_CTX/logs/audit.jsonl"
  if ! { [ -f "$audit" ] \
    && grep -qF '"action":"user_decision_recorded"' "$audit" 2> /dev/null \
    && grep -qF "\"subject\":\"$id\"" "$audit" 2> /dev/null; }; then
    corpflow_hook_audit_row --ctx "$UD_AUDIT_CTX" --actor "hook:user-decision" --action user_decision_recorded \
      --result degraded --subject "$id" --task-id "$task" --meta "$meta"
  fi
  return 0
}

# do_post — PostToolUse on the ask tool, native or MCP-proxied. Reads $PAYLOAD (already staged as one JSON string).
do_post() {
  local CTX TOOL_NAME TUID PFILE preason prc treason trc STATE LEDGER areason arc
  CTX=$(corpflow_context_root)
  [ -n "$CTX" ] || return 0
  command -v jq > /dev/null 2>&1 || return 0

  # AD4 P1, and it runs first: without a state.json carrying a non-empty worktask_id there is no
  # context to audit into, so the hook exits silently rather than writing a row nobody can read.
  STATE="$CTX/state.json"
  if [ ! -f "$STATE" ] || [ -z "$(jq -r '.worktask_id // ""' "$STATE" 2> /dev/null)" ]; then
    return 0
  fi

  TOOL_NAME=$(printf '%s' "$PAYLOAD" | jq -r '.tool_name // ""' 2> /dev/null) || TOOL_NAME=""
  TUID=$(printf '%s' "$PAYLOAD" | jq -r '.tool_use_id // "" | tostring' 2> /dev/null) || TUID=""

  # UD_ASK_TOOL_RE lives only in the lib. Refuse before the match when the lib is absent or the
  # pattern is empty: an empty ERE matches every tool name, so an unguarded test would accept all.
  if ! command -v ud_append_call > /dev/null 2>&1 || [ -z "${UD_ASK_TOOL_RE:-}" ]; then
    _ud_refuse "$CTX" no_digest_tool
    return 0
  fi

  if ! [[ "$TOOL_NAME" =~ $UD_ASK_TOOL_RE ]] || ! [[ "$TUID" =~ ^[A-Za-z0-9_-]{1,128}$ ]]; then
    _ud_refuse "$CTX" bad_event
    return 0
  fi

  PFILE=$(mktemp 2> /dev/null) || {
    _ud_refuse "$CTX" no_digest_tool "$TUID"
    return 0
  }
  printf '%s' "$PAYLOAD" > "$PFILE" 2> /dev/null
  ud_normalize_answers "$PFILE" > /dev/null 2>&1

  # AD4 is a ladder and first failure wins, so P3's payload half (idle_auto_answer, no_answer)
  # is asked before P4 reads the transcript. ud_append_call stages the answers again later; one
  # extra jq pass per call is the price of reporting the reason AD4 orders first.
  preason=$(ud_extract_answers "$PFILE")
  prc=$?
  if [ "$prc" -eq 1 ]; then
    rm -f "$PFILE"
    _ud_refuse "$CTX" "$preason" "$TUID"
    return 0
  fi
  [ "$prc" -eq 0 ] && rm -f "$preason"

  treason=$(ud_transcript_check "$PFILE")
  trc=$?
  if [ "$trc" -eq 1 ]; then
    rm -f "$PFILE"
    _ud_refuse "$CTX" "$treason" "$TUID"
    return 0
  fi
  if [ "$trc" -ne 0 ]; then
    rm -f "$PFILE"
    _ud_refuse "$CTX" no_digest_tool "$TUID"
    return 0
  fi

  LEDGER="$CTX/decisions.jsonl"
  UD_AUDIT_CTX="$CTX"

  areason=$(ud_append_call "$LEDGER" "$STATE" "$PFILE" _ud_cb)
  arc=$?
  rm -f "$PFILE"
  # rc 2 (IO) prints no reason; no_digest_tool is this hook's existing IO code, same as the
  # mktemp and transcript-IO paths above, so the refusal row always names a closed-set reason.
  [ -n "$areason" ] || areason=no_digest_tool
  [ "$arc" -eq 0 ] || _ud_refuse "$CTX" "$areason" "$TUID"
  return 0
}

# _ud_deny <reason text> <tool> [<command or path text>] — prints the PreToolUse deny document
# and writes one block-result audit row through the same redacted-head seam every denial in this
# plugin uses; never the raw command/path itself.
_ud_deny() {
  local reason="$1" tool="$2" text="${3:-}" doc CTXD task kcmd meta
  doc=$(jq -cn --arg r "$reason" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}' \
    2> /dev/null)
  [ -n "$doc" ] && printf '%s\n' "$doc"

  CTXD=$(corpflow_context_root)
  [ -n "$CTXD" ] || return 0
  command -v corpflow_hook_audit_row > /dev/null 2>&1 || return 0
  task=$(corpflow_audit_task_id "$CTXD")
  meta="{}"
  if command -v pd_audit_meta > /dev/null 2>&1; then
    kcmd=$(pd_key_command "$text")
    meta=$(pd_audit_meta "$tool" "$text" "$(pd_dedupe_key "$task" "$tool" "$kcmd")")
  fi
  [ -n "$meta" ] || meta="{}"
  corpflow_hook_audit_row --ctx "$CTXD" --actor "hook:user-decision" --action user_decision_ledger_write_denied \
    --result block --subject "$tool" --task-id "$task" --meta "$meta"
  return 0
}

# _ud_deny_fail_closed — the fast path matched, but jq or a library is unavailable: deny, no
# audit row (writing one needs the same missing jq), so deleting a file or dropping jq from PATH
# cannot disarm the guard.
_ud_deny_fail_closed() {
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"user-decision-record.sh: jq or its library is unavailable; denying by default after the ledger/hook-script prefilter matched."}}'
  return 0
}

# _ud_guard_ledger_cmd <command> — AD8 Bash-ledger arm: every `; & |`-split segment (assignment
# stripped) must start with a read-only program, carry no substitution/eval/xargs/tee, and
# redirect nowhere but /dev/null, 2>&1 or &2.
_ud_guard_ledger_cmd() {
  local cmd="$1" seg sseg prog scrub segs
  segs=$(printf '%s\n' "$cmd" | tr ';&|' '\n')
  while IFS= read -r seg; do
    case "$seg" in *[![:space:]]*) ;; *) continue ;; esac
    # AD8's rule is over the command, so the checks below read the RAW segment: an assignment's
    # value is shell the shell still runs (`X=$(tee<a>ledger) cat ledger`), and stripping it
    # first would hide the substitution, the redirect and the denied program alike. The stripped
    # form is used for nothing but the program name.
    # shellcheck disable=SC2016  # these are literal glob patterns, not expansions to interpolate
    if [[ "$seg" == *'$('* || "$seg" == *'`'* || "$seg" == *'<('* || "$seg" == *'>('* ]]; then
      _ud_deny "a Bash command naming the user-decision ledger contains command substitution or process substitution, which is denied." Bash "$cmd"
      return 0
    fi
    if [[ "$seg" =~ (^|[^A-Za-z0-9_./-])(eval|xargs|tee)([[:space:]]|$) ]]; then
      _ud_deny "a Bash command naming the user-decision ledger runs eval, xargs or tee, which is denied." Bash "$cmd"
      return 0
    fi
    scrub="$seg"
    scrub="${scrub//2>\/dev\/null/}"
    scrub="${scrub//>\/dev\/null/}"
    scrub="${scrub//2>&1/}"
    scrub="${scrub//>&2/}"
    if [[ "$scrub" == *'>'* ]]; then
      _ud_deny "a Bash command naming the user-decision ledger redirects output somewhere other than /dev/null, which is denied." Bash "$cmd"
      return 0
    fi
    sseg="$seg"
    if command -v strip_assignments > /dev/null 2>&1; then
      sseg=$(strip_assignments "$seg")
    fi
    prog=$(printf '%s' "$sseg" | awk '{print $1}')
    prog="${prog##*/}"
    if ! [[ "$prog" =~ $_UD_LEDGER_ALLOW_RE ]]; then
      _ud_deny "a Bash command naming the user-decision ledger runs a program outside the read-only allow-list, which is denied." Bash "$cmd"
      return 0
    fi
  done <<< "$segs"
  return 0
}

# _ud_guard_hook_cmd <command> — AD8 Bash-hook-script arm, deny-by-default like the ledger arm
# above: a segment naming user-decision-record.sh is denied unless it is a read-only or lint
# shape (`bash -n`, shellcheck, or a program from the read-only allow-list). An allow-list of
# interpreters cannot work, because `env bash`, `command bash`, `timeout 10 bash` and `nohup bash`
# all run the script under a first word that is not an interpreter name. Re-invoking the hook is
# itself a forgery primitive: the transcript of a declined dialog still holds a matching
# tool_use, so a hand-built payload would mint both the ledger row and its audit corroboration.
_ud_guard_hook_cmd() {
  local cmd="$1" seg sseg prog segs scrub
  segs=$(printf '%s\n' "$cmd" | tr ';&|' '\n')
  while IFS= read -r seg; do
    case "$seg" in *[![:space:]]*) ;; *) continue ;; esac
    _ud_icase_has "$seg" user-decision-record.sh || continue
    # Raw segment, for the reason spelled out in the ledger arm above: an assignment value like
    # `X=$(./hooks/user-decision-record.sh<p.json)` runs the hook before the allow-listed program
    # on the same line ever starts.
    # shellcheck disable=SC2016  # these are literal glob patterns, not expansions to interpolate
    if [[ "$seg" == *'$('* || "$seg" == *'`'* || "$seg" == *'<('* || "$seg" == *'>('* ]]; then
      _ud_deny "a Bash command naming user-decision-record.sh contains command substitution or process substitution, which is denied." Bash "$cmd"
      return 0
    fi
    if [[ "$seg" =~ (^|[^A-Za-z0-9_./-])(eval|xargs|tee|exec)([[:space:]]|$) ]]; then
      _ud_deny "a Bash command naming user-decision-record.sh runs eval, exec, xargs or tee, which is denied." Bash "$cmd"
      return 0
    fi
    scrub="$seg"
    scrub="${scrub//2>\/dev\/null/}"
    scrub="${scrub//>\/dev\/null/}"
    scrub="${scrub//2>&1/}"
    scrub="${scrub//>&2/}"
    if [[ "$scrub" == *'>'* || "$scrub" == *'<'* ]]; then
      _ud_deny "a Bash command naming user-decision-record.sh redirects, which is denied: the hook reads its payload from stdin." Bash "$cmd"
      return 0
    fi
    # `bash -n <script>` is the one interpreter shape allowed, and only with -n as its first word.
    # Anchored to bash or sh themselves, optionally path-qualified: `xsh -n <hook>` must not ride
    # the carve-out by ending in the two letters the pattern looks for.
    if [[ "$seg" =~ ^[[:space:]]*([^[:space:]]*/)?(bash|sh)[[:space:]]+-n([[:space:]]|$) ]]; then
      continue
    fi
    sseg="$seg"
    if command -v strip_assignments > /dev/null 2>&1; then
      sseg=$(strip_assignments "$seg")
    fi
    prog=$(printf '%s' "$sseg" | awk '{print $1}')
    prog="${prog##*/}"
    if ! [[ "$prog" =~ $_UD_HOOK_ALLOW_RE ]]; then
      _ud_deny "a Bash command naming user-decision-record.sh runs a program outside the read-only allow-list, which is denied outside bash -n or shellcheck." Bash "$cmd"
      return 0
    fi
  done <<< "$segs"
  return 0
}

# do_pre — PreToolUse Write|Edit|Bash. The fast path is a bare substring test on the raw
# payload text: with neither string present, nothing below this point ever forks. On a hit, a
# missing context library denies (no root can be found, so "no worktask here" is unprovable);
# once a root is found, no state.json still allows, and a missing jq or ledger library denies.
do_pre() {
  if ! _ud_fold "$PAYLOAD"; then
    _ud_deny_fail_closed
    return 0
  fi
  _ud_icase_has "$FOLDED" decisions.jsonl || _ud_icase_has "$FOLDED" user-decision-record.sh || return 0

  local CTX TOOL FPATH CMD LEDGER LOCKDIR base parent phys target ctxp
  if ! command -v corpflow_context_root > /dev/null 2>&1; then
    _ud_deny_fail_closed
    return 0
  fi
  CTX=$(corpflow_context_root)
  [ -n "$CTX" ] || return 0
  [ -f "$CTX/state.json" ] || return 0
  if ! command -v jq > /dev/null 2>&1 || ! command -v ud_lock_acquire > /dev/null 2>&1; then
    _ud_deny_fail_closed
    return 0
  fi

  TOOL=$(printf '%s' "$PAYLOAD" | jq -r '.tool_name // ""' 2> /dev/null) || TOOL=""
  LEDGER="$CTX/decisions.jsonl"
  LOCKDIR="${LEDGER}.lock"

  case "$TOOL" in
    Write | Edit)
      FPATH=$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.file_path // ""' 2> /dev/null) || FPATH=""
      [ -n "$FPATH" ] || return 0
      base="${FPATH##*/}"
      parent="${FPATH%/*}"
      [ "$parent" != "$FPATH" ] || parent="."
      phys="$(CDPATH='' cd -- "$parent" 2> /dev/null && pwd -P)"
      [ -n "$phys" ] || return 0
      _ud_fold "$phys/$base" || { _ud_deny_fail_closed; return 0; }
      target="$FOLDED"
      # Both sides physical: a root reached through a symlink (macOS /var -> /private/var) would
      # otherwise never string-equal the resolved target.
      ctxp="$(CDPATH='' cd -- "$CTX" 2> /dev/null && pwd -P)"
      if [ -n "$ctxp" ]; then
        LEDGER="$ctxp/decisions.jsonl"
        LOCKDIR="${LEDGER}.lock"
      fi
      # Name compare is case-blind and -ef adds the same-file test (another spelling, a hard link).
      if _ud_icase_eq "$target" "$LEDGER" || { [ -e "$LEDGER" ] && [ "$target" -ef "$LEDGER" ]; }; then
        _ud_deny "$TOOL targets the user-decision ledger, which only hooks/user-decision-record.sh may write." "$TOOL" "$FPATH"
      elif _ud_icase_eq "$target" "$LOCKDIR" || _ud_icase_under "$target" "$LOCKDIR" \
        || { [ -e "$LOCKDIR" ] && { [ "$target" -ef "$LOCKDIR" ] || [ "$phys" -ef "$LOCKDIR" ]; }; }; then
        _ud_deny "$TOOL targets the user-decision ledger's lock directory." "$TOOL" "$FPATH"
      fi
      ;;
    Bash)
      CMD=$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.command // ""' 2> /dev/null) || CMD=""
      [ -n "$CMD" ] || return 0
      _ud_fold "$CMD" || { _ud_deny_fail_closed; return 0; }
      CMD="$FOLDED"
      _ud_icase_has "$CMD" decisions.jsonl && _ud_guard_ledger_cmd "$CMD"
      _ud_icase_has "$CMD" user-decision-record.sh && _ud_guard_hook_cmd "$CMD"
      ;;
  esac
  return 0
}

# _ud_event_nojq — sets EVENT without jq; PostToolUse only when the one unescaped
# `"hook_event_name"` key has that value, else PreToolUse, which denies on a fast-path hit.
# Dropping escapes first means a copy of the key inside a JSON string value never reads as a key.
# One sed|grep pass: bash 3.2 `${x//pat/}` is superlinear and reaches the hook timeout at ~25 KB.
_ud_event_nojq() {
  local hits re='"PostToolUse"$'
  EVENT=PreToolUse
  hits=$(printf '%s' "$PAYLOAD" | LC_ALL=C sed -e 's/\\\\//g' -e 's/\\"//g' \
    | LC_ALL=C grep -oE '"hook_event_name"([[:space:]]*:[[:space:]]*"[A-Za-z]*")?' 2> /dev/null)
  case "$hits" in '' | *$'\n'*) return 0 ;; esac
  [[ $hits =~ $re ]] && EVENT=PostToolUse
  return 0
}

if [ "${1:-}" = "--lib-only" ]; then
  # shellcheck disable=SC2317  # reachable only when this file is executed rather than sourced
  return 0 2> /dev/null || exit 0
fi

if command -v jq > /dev/null 2>&1; then
  EVENT=$(printf '%s' "$PAYLOAD" | jq -r '.hook_event_name // ""' 2> /dev/null) || EVENT=""
else
  _ud_event_nojq
fi
case "$EVENT" in
  PostToolUse) do_post ;;
  PreToolUse) do_pre ;;
esac
exit 0
