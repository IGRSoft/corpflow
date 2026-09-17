#!/usr/bin/env bash
# @description command-head-lib.sh — what a hook may keep of a shell command: the
#   leading-assignment strip the test-execution gate classifies with, and the redacted
#   command_head and bounded targets an audit row carries. audit.jsonl is committed, so
#   nothing here ever hands back raw command text.
#
#   Loading defines functions only (no fork, no source, no probe): the gate loads this
#   on every PreToolUse call. The path scrub is sourced on the first redaction, once.
#
#   Symbols: strip_assignments, audit_command_head, audit_targets. Both audit_* also set
#   AUDIT_COMMAND_HEAD, AUDIT_TARGETS (one per line), AUDIT_TARGETS_TRUNCATED (0|1) and
#   AUDIT_REDACTION ("" or scrub_unavailable), so a caller needing both the head and the
#   targets of one command pays one scrub and no command substitution.
#
#   A head keeps the program's basename and at most three more tokens, each a single-letter flag
#   (`-v`), a lowercase long flag of at most 32 characters with nothing attached (`--verbose`), a
#   ledger task id or a ledger status. Every other token is "[redacted]", including clustered or
#   value-carrying flags such as `-rf`, `-pS3cret`, `--password=x` and `--S3cret`.
#
# Minimum shell: bash 3.2+ (macOS default).

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  printf >&2 'command-head-lib.sh: this is a library — source it, do not execute it directly\n'
  exit 2
fi

[ -n "${_CORPFLOW_CMDHEAD_LIB:-}" ] && return 0
_CORPFLOW_CMDHEAD_LIB=1
_CH_LIB_SRC="${BASH_SOURCE[0]:-$0}"

# strip_assignments <segment> -> the segment with leading VAR=value and `env` wrappers
# removed, so a secret in a leading assignment (`API_KEY=sk-... pytest x`) reaches
# neither a classifier's head-token check nor an audit row.
#
# A quoted value is consumed as one unit: `FOO="a b" pytest x` stripped to the next
# space would leave a fragment in head position, dropping the invocation out of the
# runner set or colliding with a real runner name. [[ =~ ]] keeps it fork-free.
#
# The separator is [[:blank:]], never [[:space:]]: against a multi-line command a
# newline match would consume the FIRST line's assignment and promote the second
# line's program into head position.
_ASSIGN_RE='^[A-Za-z_][A-Za-z0-9_]*=("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:]]*)[[:blank:]]+'
strip_assignments() {
  local _s _next
  _s="$1"
  while :; do
    case "$_s" in
      env\ *) _s="${_s#env }" ;;
      *)
        [[ $_s =~ $_ASSIGN_RE ]] || break
        _next="${_s#"${BASH_REMATCH[0]}"}"
        [ "$_next" != "$_s" ] || break
        _s="$_next"
        ;;
    esac
  done
  printf '%s' "$_s"
}

# A flag never carries its value: `-pS3cret` and `--password=x` are single tokens.
_CH_FLAG_RE='^(-[A-Za-z]|--[a-z][a-z0-9-]{0,30})$'
_CH_TASK_RE='^[A-Z]{2}[0-9]+$'
_CH_PROG_RE='^[A-Za-z0-9._+-]+$'
_CH_PATH_RE='^[A-Za-z0-9._/~-]+$'
# The 32+ run excludes `/`, `-` and `_` so an ordinary long repo path is not read as a key.
_CH_SECRET_RE='([Kk][Ee][Yy]|[Tt][Oo][Kk][Ee][Nn]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Pp][Aa][Ss][Ss])[A-Za-z0-9_]*=|[Bb][Ee][Aa][Rr][Ee][Rr]|(^|[^A-Za-z0-9])(gh[opsu]_|github_pat_|sk-|xox[a-z]-|AKIA)|://[^/@]+@|[A-Za-z0-9+=]{32,}'

# A segment with digits sandwiched between letters twice over is a l33t-speak secret, not a
# name: `sup3rs3cret` matches, `md5sum` and `base64url` (one sandwich) do not.
_CH_SEG_MIXED_RE='[A-Za-z][0-9]+[A-Za-z].*[A-Za-z][0-9]+[A-Za-z]'

# _ch_target_ok <token> -> 0 when every slash-delimited segment still looks like a path name.
# Targets need a structural bound of their own: the head's token grammar never reaches them,
# and the secret mask cannot be the answer either, because a credential with slashes in it IS
# a path-shaped token (an AWS secret key, a Slack webhook tail). Over-redaction costs one
# target's telemetry; under-redaction publishes the key.
_ch_target_ok() {
  local _t="$1" _seg
  while [ -n "$_t" ]; do
    case "$_t" in
      */*) _seg="${_t%%/*}"; _t="${_t#*/}" ;;
      *) _seg="$_t"; _t="" ;;
    esac
    [ -n "$_seg" ] || continue
    [ "${#_seg}" -le 64 ] || return 1
    # No word separator means a name, not a token: longer than any ordinary one, shorter than a key.
    case "$_seg" in
      *[-._~]*) : ;;
      *) [ "${#_seg}" -le 16 ] || return 1 ;;
    esac
    # Lower, upper and digits in one segment is the shape of a generated credential.
    if [[ $_seg =~ [a-z] ]] && [[ $_seg =~ [A-Z] ]] && [[ $_seg =~ [0-9] ]]; then return 1; fi
    [[ $_seg =~ $_CH_SEG_MIXED_RE ]] && return 1
  done
  return 0
}

# _ch_mask <token> -> _CH_TOK: the token, or "[redacted]" when any part of it is
# secret-shaped. Defence in depth only; the token grammar is the primary bound.
_ch_mask() {
  if [[ $1 =~ $_CH_SECRET_RE ]]; then _CH_TOK="[redacted]"; else _CH_TOK="$1"; fi
}

# _ch_segment <command> <match> -> _CH_SEG: on the first line, the first segment
# outside quotes split at ; & |, or with <match> the first containing it, else empty.
# Backslash escapes are not honoured; a mis-split only narrows what is kept.
_ch_segment() {
  local _line="${1%%$'\n'*}" _match="$2" _seg="" _c _q="" _i _n
  _CH_SEG=""
  _n=${#_line}
  for ((_i = 0; _i <= _n; _i++)); do
    if [ "$_i" -lt "$_n" ]; then
      _c="${_line:_i:1}"
      if [ -n "$_q" ]; then
        [ "$_c" != "$_q" ] || _q=""
        _seg="$_seg$_c"
        continue
      fi
      case "$_c" in
        "'" | '"') _q="$_c" ;;
        ';' | '&' | '|') ;;
        *)
          _seg="$_seg$_c"
          continue
          ;;
      esac
      if [ -n "$_q" ]; then
        _seg="$_seg$_c"
        continue
      fi
    fi
    if [ -n "${_seg//[[:blank:]]/}" ]; then
      if [ -z "$_match" ]; then
        _CH_SEG="$_seg"
        break
      fi
      case "$_seg" in *"$_match"*)
        _CH_SEG="$_seg"
        break
        ;;
      esac
    fi
    _seg=""
  done
  _CH_SEG="${_CH_SEG#"${_CH_SEG%%[![:blank:]]*}"}"
}

_ch_scrub_load() {
  [ -z "${_CH_SCRUB_STATE:-}" ] || return 0
  _CH_SCRUB_STATE=unavailable
  local _lib _opts
  case "$_CH_LIB_SRC" in
    */*) _lib="${_CH_LIB_SRC%/*}" ;;
    *) _lib=. ;;
  esac
  _lib="$_lib/../../skills/shared/scripts/path-scrub.sh"
  # `.` on a missing file exits the shell before any guard runs.
  [ -r "$_lib" ] || return 0
  _opts=$-
  set +e
  # shellcheck disable=SC1090  # resolved from this file's own location at run time
  . "$_lib"
  case "$_opts" in *e*) set -e ;; esac
  command -v corpflow_path_scrub > /dev/null 2>&1 || return 0
  [ -n "${CORPFLOW_HOST_PATH_ERE:-}" ] && [ -n "${CORPFLOW_DRIVE_PATH_ERE:-}" ] || return 0
  _CH_SCRUB_STATE=ok
}

# _ch_scrub <lines> -> _CH_SCRUBBED; returns 1 unless the scrub loaded, exited 0 and
# answered one line per input line. Any other outcome must publish nothing.
_ch_scrub() {
  local _out _nl=$'\n' _t _in_n
  _ch_scrub_load
  [ "$_CH_SCRUB_STATE" = ok ] || return 1
  _out=$(
    set -o pipefail
    printf '%s\n' "$1" | corpflow_path_scrub 2> /dev/null
  ) || return 1
  _t="${1//[!$_nl]/}"
  _in_n=${#_t}
  _t="${_out//[!$_nl]/}"
  [ "$_in_n" -eq "${#_t}" ] || return 1
  _CH_SCRUBBED="$_out"
}

# _ch_redact <command> <match> <want_head> — fills the AUDIT_* results. Order is strip,
# mask, scrub, bound, cap: capping last means a cut can never shorten a secret below the
# length its mask recognises, and the target bounds judge the scrub's own output.
# shellcheck disable=SC2034  # AUDIT_* are this library's out-variables, read by callers
_ch_redact() {
  local _want="$3" _seg _tok _prog _head="" _text="" _line _i=0 _n _k _kept _count=0
  local _toks=()
  AUDIT_COMMAND_HEAD=""
  AUDIT_TARGETS=""
  AUDIT_TARGETS_TRUNCATED=0
  AUDIT_REDACTION=""

  _ch_segment "$1" "$2"
  _seg=$(strip_assignments "$_CH_SEG")
  IFS=$' \t' read -r -a _toks <<< "$_seg" || true
  _n=${#_toks[@]}

  if [ "$_n" -gt 1 ]; then
    case "${_toks[0]##*/}" in
      bash | sh | zsh | dash | ksh) [[ ${_toks[1]} == -* ]] || _i=1 ;;
    esac
  fi

  if [ "$_want" = 1 ]; then
    _head="[redacted]"
    if [ "$_i" -lt "$_n" ]; then
      _prog="${_toks[_i]##*/}"
      [[ $_prog =~ $_CH_PROG_RE ]] || _prog="[redacted]"
      _ch_mask "$_prog"
      _head="$_CH_TOK"
      _kept=1
      for ((_k = _i + 1; _k < _n && _kept < 4; _k++)); do
        _tok="${_toks[_k]}"
        if ! [[ $_tok =~ $_CH_FLAG_RE || $_tok =~ $_CH_TASK_RE ]]; then
          case "$_tok" in
            pending | in_progress | completed | blocked | skipped | failed) ;;
            *) _tok="[redacted]" ;;
          esac
        fi
        _ch_mask "$_tok"
        _head="$_head $_CH_TOK"
        _kept=$((_kept + 1))
      done
    fi
    _text="$_head"
  fi

  for ((_k = 0; _k < _n; _k++)); do
    _tok="${_toks[_k]}"
    case "$_tok" in */*) ;; *) continue ;; esac
    [[ $_tok =~ $_CH_PATH_RE ]] || continue
    _count=$((_count + 1))
    if [ "$_count" -gt 5 ]; then
      AUDIT_TARGETS_TRUNCATED=1
      break
    fi
    _ch_mask "$_tok"
    _text="$_text${_text:+$_NL_CH}$_CH_TOK"
  done

  [ -n "$_text" ] || return 0
  if ! _ch_scrub "$_text"; then
    [ "$_want" != 1 ] || AUDIT_COMMAND_HEAD="[redacted]"
    AUDIT_TARGETS_TRUNCATED=0
    AUDIT_REDACTION="scrub_unavailable"
    return 0
  fi

  _k=0
  while IFS= read -r _line; do
    if [ "$_want" = 1 ] && [ "$_k" -eq 0 ]; then
      AUDIT_COMMAND_HEAD="${_line:0:120}"
    else
      # Post-scrub, before the cap, because both checks judge what is PUBLISHED: a target still
      # absolute is a host path the scrub did not know (a root outside its pattern, no repo
      # root resolved), and a random host segment the scrub already replaced is no credential.
      case "$_line" in /*) _line="[local-path]" ;; esac
      _ch_target_ok "$_line" || _line="[redacted]"
      AUDIT_TARGETS="$AUDIT_TARGETS${AUDIT_TARGETS:+$_NL_CH}${_line:0:160}"
    fi
    _k=$((_k + 1))
  done <<< "$_CH_SCRUBBED"
  return 0
}
_NL_CH=$'\n'

# audit_command_head <command> [<match>] -> prints the head of the segment <match>
# selects: the program's basename plus up to three single-letter flag, bare lowercase long
# flag, task-id or status tokens, anything else "[redacted]"; masked, path-scrubbed, <=120 chars.
audit_command_head() {
  _ch_redact "${1:-}" "${2:-}" 1
  printf '%s' "$AUDIT_COMMAND_HEAD"
  return 0
}

# audit_targets <command|path> [<match>] -> prints that segment's path-shaped tokens,
# one per line: masked, scrubbed, at most 5 entries of at most 160 chars each.
audit_targets() {
  _ch_redact "${1:-}" "${2:-}" 0
  [ -z "$AUDIT_TARGETS" ] || printf '%s\n' "$AUDIT_TARGETS"
  return 0
}
