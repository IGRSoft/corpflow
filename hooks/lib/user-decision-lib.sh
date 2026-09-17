#!/usr/bin/env bash
# @description user-decision-lib.sh — the one implementation of the user-decision ledger:
#   canonical hashing, chain walk, the scope ladder, the append lock and the verifier. Sourced
#   by hooks/user-decision-record.sh and skills/worktask/scripts/state-patch.sh's
#   --verify-decision op, so a hook-side and a CLI-side hash implementation can never drift.
#
#   Pure by construction: every function takes explicit path/arg inputs, writes no audit row
#   itself (callers pass a callback) and resolves no context root. Symbols are `ud_*` only — no
#   `corpflow_*` name, since hook-symbol-parity counts that namespace. No `set`, `shopt`, `trap`
#   or `exit` runs at load, and there is no `readonly -f`: a suite that sources this twice per
#   process must see a plain no-op, not a redefinition error.
#
#   Byte rule: decoded question or answer text never passes through a shell variable, `$(…)` or
#   `read` — it moves only as jq reading a file/pipe, or as argv for an expected-answer compare.
#   A JSON-encoded line (a whole ledger row, or a `[question,answer]` canonical form) is not
#   "decoded" and may sit in a variable; only the unescaped text itself may not.
#
#   Symbols: ud_digest, ud_row_sha256, ud_line_sha256, ud_extract_answers, ud_transcript_check,
#   ud_scope_for, ud_lock_acquire, ud_lock_release, ud_append_call, ud_chain_walk,
#   ud_audit_corroborates, ud_verify, ud_find_covering.
#   Constants: UD_ACTOR, UD_ID_RE, UD_ROW_KEYS, UD_REASONS.
#
# Minimum shell: bash 3.2+ (macOS default). Option-set neutral: correct under both a `set -e`
# caller (state-patch.sh) and a plain caller (the hook), because it sets none of its own.

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  printf >&2 'user-decision-lib.sh: this is a library — source it, do not execute it directly\n'
  exit 2
fi
[ -n "${_UD_LIB:-}" ] && return 0
_UD_LIB=1

UD_ACTOR="hook:user-decision"
UD_ID_RE='^ud-[0-9]{8}T[0-9]{6}Z-[1-9][0-9]*$'
UD_ROW_KEYS="id ts actor tool_use_id question answer scope sha256 prev_sha256"
# shellcheck disable=SC2034  # public constant: the closed reason set ud_verify's callers match against
UD_REASONS="not_found ledger_symlink malformed_row duplicate_id duplicate_tool_use actor_mismatch sha256_mismatch chain_broken worktask_mismatch scope_not_covering audit_uncorroborated answer_mismatch"

# AD2 pinned canonical probe: the digest of `jq -jc` over a [question,answer] pair carrying a
# DEL, U+2028/U+2029, U+FFFD, C0 controls, a non-BMP codepoint, `/` and `\`. A jq whose string
# escaping differs from the pinned reference (jq 1.7.1) fails this, and the verifier then exits 2
# with `jq_canon_drift` rather than reading its own stored digests as forgeries. The probe value
# is built from codepoints, so this file holds no raw control byte and no escape to mis-decode.
UD_CANON_SHA="0710843c3d55cd66ecd919da7f62cc1e761baff43303000f38d571bc8e3e7059"
# shellcheck disable=SC2034  # public constant: the probe program, exposed for drift diagnosis
UD_CANON_PROBE='[([97,34,98,92,99,47,100,1,101,9,102,10,103,127,104,8232,105,65533,106,119070,107] | implode), ([122,8233] | implode)]'

_UD_LOCK_DIR=""
_UD_LOCK_TOKEN=""

# ud_canon_ok — rc 0 when this jq encodes the pinned probe exactly as the reference did; rc 1 on
# drift; rc 2 when jq or a digest tool is missing (the caller's own IO exit).
ud_canon_ok() {
  local _out
  command -v jq > /dev/null 2>&1 || return 2
  _out=$(jq -jcn "$UD_CANON_PROBE" 2> /dev/null | ud_digest) || return 2
  [ "$_out" = "$UD_CANON_SHA" ] || return 1
  return 0
}

# ud_digest — stdin's bytes -> 64 lowercase hex on stdout; rc 2 with empty stdout when neither
# digest tool works. Buffers stdin to a file first, never a variable: a mid-stream shasum
# failure (not just its absence) must still fall back to sha256sum on the SAME bytes, and a
# pipe can only be read once.
ud_digest() {
  local _tmp _out
  _tmp="" _out=""
  _tmp=$(mktemp 2> /dev/null) || return 2
  cat > "$_tmp" 2> /dev/null || {
    rm -f "$_tmp"
    return 2
  }
  if command -v shasum > /dev/null 2>&1; then
    _out=$(LC_ALL=C shasum -a 256 -- "$_tmp" 2> /dev/null)
    _out="${_out%% *}"
  fi
  if ! printf '%s' "$_out" | LC_ALL=C grep -Eq '^[0-9a-f]{64}$' 2> /dev/null; then
    _out=""
    if command -v sha256sum > /dev/null 2>&1; then
      _out=$(LC_ALL=C sha256sum -- "$_tmp" 2> /dev/null)
      _out="${_out%% *}"
    fi
  fi
  rm -f "$_tmp"
  printf '%s' "$_out" | LC_ALL=C grep -Eq '^[0-9a-f]{64}$' 2> /dev/null || return 2
  printf '%s' "$_out"
  return 0
}

# ud_row_sha256 <row-json-file|-> — the AD2 canonical digest: sha256 of `jq -jc
# '[.question,.answer]'` over the row, no trailing LF. <-> reads stdin.
ud_row_sha256() {
  local _src _arr _rc
  _src="${1:-}"
  [ -n "$_src" ] || return 2
  command -v jq > /dev/null 2>&1 || return 2
  if [ "$_src" = "-" ]; then
    _arr=$(jq -jc '[.question,.answer]' 2> /dev/null)
  else
    [ -f "$_src" ] && [ ! -L "$_src" ] || return 2
    _arr=$(jq -jc '[.question,.answer]' -- "$_src" 2> /dev/null)
  fi
  _rc=$?
  [ "$_rc" -eq 0 ] && [ -n "$_arr" ] || return 2
  printf '%s' "$_arr" | ud_digest
  return $?
}

# ud_line_sha256 <line> — digest of a whole stored ledger line's bytes (chain linkage, never the
# canonical [question,answer] form). <line> is a JSON-encoded row and may be a shell variable.
ud_line_sha256() {
  [ -n "${1:-}" ] || return 2
  printf '%s' "${1:-}" | ud_digest
}

# ud_extract_answers <payload-file> — stages one JSONL line per tool_input.questions[] entry,
# `{index, header, question_ok, answer_ok}`, to a tmp file whose path is printed on rc 0.
# Whole-call refusals (P3) print a reason token instead: rc 1 idle_auto_answer|no_answer, rc 2
# on IO/jq failure. Per-question shape (P6: string verbatim, array joined) is a boolean here —
# the actual text is never read into this function's own shell state, only into jq's.
ud_extract_answers() {
  local _payload _tmp _rc
  _payload="${1:-}"
  [ -n "$_payload" ] && [ -f "$_payload" ] && [ ! -L "$_payload" ] || return 2
  command -v jq > /dev/null 2>&1 || return 2

  if jq -e '((.tool_response // .response // {}).afkTimeoutMs // null) != null' \
    "$_payload" > /dev/null 2>&1; then
    printf 'idle_auto_answer'
    return 1
  fi

  if ! jq -e '
      ((.tool_response // .response // {}).answers // {}) as $r
      | ((.tool_input // {}).answers // {}) as $i
      | (($r | type) == "object" and ($r | length) > 0)
        or (($i | type) == "object" and ($i | length) > 0)
    ' "$_payload" > /dev/null 2>&1; then
    printf 'no_answer'
    return 1
  fi

  _tmp=$(mktemp 2> /dev/null) || return 2
  jq -c '
    ((.tool_response // .response // {}).answers // {}) as $r
    | ((.tool_input // {}).answers // {}) as $i
    | ((.tool_input // {}).questions // []) as $qs
    | range(0; ($qs | length)) as $idx
    | ($qs[$idx]) as $q
    | (($q.question // "") | length > 0) as $qok
    | (($r[$q.question]? // $i[$q.question]?)) as $a
    | ( ($a | type) == "string"
        or (($a | type) == "array" and ($a | all(type == "string"))) ) as $aok
    | {index: $idx, header: (($q.header // "") | .[0:64]), question_ok: $qok, answer_ok: $aok}
  ' "$_payload" > "$_tmp" 2> /dev/null
  _rc=$?
  if [ "$_rc" -ne 0 ]; then
    rm -f "$_tmp"
    return 2
  fi
  printf '%s' "$_tmp"
  return 0
}

# ud_transcript_check <payload-file> — P4 (the transcript holds this tool_use_id, named
# AskUserQuestion) plus the transcript half of P3 (the ORIGINAL tool_use.input already carried
# `answers`, i.e. pre_answered). Re-reads up to 3 times, 0.2s apart, for a flush race. rc 0 ok,
# rc 1 refused (reason on stdout: transcript_miss|pre_answered), rc 2 IO.
ud_transcript_check() {
  local _payload _tp _sid _tuid _try _found _def
  _payload="${1:-}"
  [ -n "$_payload" ] && [ -f "$_payload" ] && [ ! -L "$_payload" ] || return 2
  command -v jq > /dev/null 2>&1 || return 2
  _tp=$(jq -r '.transcript_path // ""' "$_payload" 2> /dev/null) || return 2
  _sid=$(jq -r '.session_id // ""' "$_payload" 2> /dev/null) || return 2
  _tuid=$(jq -r '.tool_use_id // ""' "$_payload" 2> /dev/null) || return 2
  if [ -z "$_tp" ] || [ -z "$_sid" ] || [ -z "$_tuid" ] || [ "${_tp##*/}" != "${_sid}.jsonl" ]; then
    printf 'transcript_miss'
    return 1
  fi

  # shellcheck disable=SC2016  # jq program text: $id is a jq variable, not a shell one
  _def='
    def ud_tool_uses($id):
      select(type == "object" and .type == "assistant")
      | (.message.content? // empty)
      | (if type == "array" then .[] else empty end)
      | select(type == "object" and .type == "tool_use" and .id == $id and .name == "AskUserQuestion");
  '
  # P4 also requires the recorded call's own questions to be the ones this payload reports: the
  # comparison is byte-equal and happens entirely inside jq, with the payload slurped as a file.
  _found=0
  for _try in 1 2 3; do
    if [ -f "$_tp" ] && [ ! -L "$_tp" ] \
      && jq -sce --arg id "$_tuid" --slurpfile pay "$_payload" "${_def}"'
          [.[] | ud_tool_uses($id)] as $tu
          | (($pay[0].tool_input.questions // []) | map(.question)) as $pq
          | ($tu | length > 0)
            and any($tu[]; ((.input.questions // []) | map(.question)) == $pq)' \
        "$_tp" > /dev/null 2>&1; then
      _found=1
      break
    fi
    [ "$_try" -lt 3 ] && sleep 0.2
  done
  if [ "$_found" -ne 1 ]; then
    printf 'transcript_miss'
    return 1
  fi

  if jq -sce --arg id "$_tuid" "${_def}"'[.[] | ud_tool_uses($id)] | any(.input.answers? != null)' \
    "$_tp" > /dev/null 2>&1; then
    printf 'pre_answered'
    return 1
  fi
  return 0
}

# ud_scope_for <state.json> <header> <payload-file> <index> — the AD5 ladder for one question.
# Prints the scope object on rc 0, or "no_scope" on rc 1 (rung 3, or the header names nothing).
# The question text is compared inside one jq call against state.json; it never reaches a
# variable here, only ids (worktask_id, task keys, the sweep id) do.
ud_scope_for() {
  local _state _header _payload _idx _out
  _state="${1:-}" _header="${2:-}" _payload="${3:-}" _idx="${4:-}"
  case "$_idx" in '' | *[!0-9]*)
    printf 'no_scope'
    return 1
    ;;
  esac
  [ -f "$_state" ] && [ ! -L "$_state" ] || {
    printf 'no_scope'
    return 1
  }
  [ -n "$_header" ] || {
    printf 'no_scope'
    return 1
  }
  [ -f "$_payload" ] && [ ! -L "$_payload" ] || {
    printf 'no_scope'
    return 1
  }
  command -v jq > /dev/null 2>&1 || return 2

  _out=$(jq -n --slurpfile st "$_state" --slurpfile pl "$_payload" --arg h "$_header" --argjson idx "$_idx" '
    ($st[0]) as $s
    | ($pl[0].tool_input.questions[$idx] // {}) as $q
    | ($q.question // "") as $question
    | (($q.options // []) | map(.label? // .)) as $options
    | ($s.worktask_id // "") as $wid
    | ($s.tasks // {}) as $tasks
    | ($tasks[$h] // {}) as $ht
    | ( (($ht.status // "") == "blocked")
        and ((($ht.metadata // {}).blocked_on // {}).kind // "") == "user_decision"
        and (((($ht.metadata // {}).blocked_on // {}).detail // {}).question // "") == $question ) as $rung1
    | if $rung1 then
        ((($ht.metadata // {}).blocked_on // {}).detail.item // null) as $item
        | ( [ $tasks | to_entries[]
              | select(.value.status == "blocked"
                  and (((.value.metadata // {}).blocked_on // {}).kind // "") == "user_decision"
                  and ((((.value.metadata // {}).blocked_on // {}).detail // {}).question // "") == $question
                  and ((((.value.metadata // {}).blocked_on // {}).detail // {}).options // []) == $options
                  and ((((.value.metadata // {}).blocked_on // {}).detail // {}).item // null) == $item)
              | .key ] | sort ) as $tids
        | {worktask_id: $wid, task_ids: $tids, item: $item}
      elif ($h | test("^sw-[A-Z]{2}[0-9]+-[0-9]+$"))
           and ((($s.facts // {}).open_questions // []) | map(.id) | index($h)) != null then
        ($h | capture("^sw-(?<code>[A-Z]{2})(?<n>[0-9]+)-[0-9]+$")) as $c
        | {worktask_id: $wid, task_ids: ["\($c.code)\($c.n)"], item: $h}
      else null end
  ' 2> /dev/null) || _out=""

  if [ -z "$_out" ] || [ "$_out" = "null" ]; then
    printf 'no_scope'
    return 1
  fi
  printf '%s' "$_out"
  return 0
}

# _ud_mtime <path> — GNU stat, else BSD stat, else empty.
_ud_mtime() {
  stat -c '%Y' "${1:-}" 2> /dev/null || stat -f '%m' "${1:-}" 2> /dev/null || printf ''
  return 0
}

# _ud_lock_break <lockdir> <aged-owner-token> — clears `owner` only if it still reads the exact
# token that was found stale, then a plain rmdir (never rm -rf), so a fresh successor's lock —
# claimed between the staleness read and this call — is left standing.
_ud_lock_break() {
  local _lockdir _aged _cur
  _lockdir="${1:-}" _aged="${2:-}"
  [ -n "$_lockdir" ] || return 0
  if [ -f "$_lockdir/owner" ]; then
    _cur=$(cat "$_lockdir/owner" 2> /dev/null)
    [ "$_cur" = "$_aged" ] || return 0
    rm -f "$_lockdir/owner" 2> /dev/null
  fi
  rmdir "$_lockdir" 2> /dev/null
  return 0
}

# ud_lock_acquire <ledger> — mkdir lock at <ledger>.lock; refuses a symlinked ledger or lock dir.
# Retries up to 25 * 0.2s (5s). A dead same-host pid breaks the lock immediately; an mtime >= 60s
# breaks it on the stale rule. rc 0 acquired, rc 1 lock_timeout, rc 2 IO/usage.
ud_lock_acquire() {
  local _ledger _lockdir _tries _mtime _now _tok _opid
  _ledger="${1:-}"
  [ -n "$_ledger" ] || return 2
  [ ! -L "$_ledger" ] || return 2
  _lockdir="${_ledger}.lock"
  [ ! -L "$_lockdir" ] || return 2
  _tries=0

  while :; do
    if mkdir "$_lockdir" 2> /dev/null; then
      _tok="$$:$RANDOM:$(date -u +%s 2> /dev/null || printf 0)"
      printf '%s' "$_tok" > "$_lockdir/owner" 2> /dev/null
      _UD_LOCK_TOKEN="$_tok"
      _UD_LOCK_DIR="$_lockdir"
      return 0
    fi
    if [ -d "$_lockdir" ] && [ ! -L "$_lockdir" ]; then
      _tok=""
      [ -f "$_lockdir/owner" ] && _tok=$(cat "$_lockdir/owner" 2> /dev/null)
      _opid="${_tok%%:*}"
      if [ -n "$_opid" ] && [ "$_opid" != "$$" ] && ! kill -0 "$_opid" 2> /dev/null; then
        _ud_lock_break "$_lockdir" "$_tok"
      else
        _mtime=$(_ud_mtime "$_lockdir")
        _now=$(date -u +%s 2> /dev/null || printf 0)
        if [ -n "$_mtime" ] && [ "$_now" -ge "$((_mtime + 60))" ]; then
          _ud_lock_break "$_lockdir" "$_tok"
        fi
      fi
    fi
    _tries=$((_tries + 1))
    [ "$_tries" -lt 25 ] || return 1
    sleep 0.2
  done
}

# ud_lock_release <ledger> — rmdir the lock this process holds, clearing `owner` first only if
# it still reads this process's own token.
ud_lock_release() {
  local _cur
  [ -n "$_UD_LOCK_DIR" ] || return 0
  if [ -f "$_UD_LOCK_DIR/owner" ]; then
    _cur=$(cat "$_UD_LOCK_DIR/owner" 2> /dev/null)
    [ "$_cur" = "$_UD_LOCK_TOKEN" ] && rm -f "$_UD_LOCK_DIR/owner" 2> /dev/null
  fi
  rmdir "$_UD_LOCK_DIR" 2> /dev/null
  _UD_LOCK_DIR=""
  _UD_LOCK_TOKEN=""
  return 0
}

# ud_append_call <ledger> <state.json> <payload-file> <audit-cb> — under lock: torn-tail and
# replay checks, per-question scope (rung 3 skipped, not refused), row build and one copy+rename
# append, then <audit-cb> <id> <tool_use_id> <row_sha256> <item> once per appended row. rc 0 >= 1
# row appended; rc 1 nothing appended (reason on stdout); rc 2 IO.
ud_append_call() {
  local _ledger _state _payload _cb _rc _staged _tuid
  local _n_prior _prev _prevline _sha _wid _ts_id _ts_row
  local _idx _header _qok _aok _scope _srow _line _newlines _cb_ids _any
  local _tmp _cb_id _cb_tuid _cb_sha _cb_item

  _ledger="${1:-}" _state="${2:-}" _payload="${3:-}" _cb="${4:-}"
  [ -n "$_ledger" ] && [ -n "$_state" ] && [ -n "$_payload" ] && [ -n "$_cb" ] || return 2
  [ -f "$_state" ] && [ ! -L "$_state" ] || return 2
  [ -f "$_payload" ] && [ ! -L "$_payload" ] || return 2
  command -v jq > /dev/null 2>&1 || return 2

  _tuid=$(jq -r '.tool_use_id // ""' "$_payload" 2> /dev/null) || return 2
  [ -n "$_tuid" ] || return 2

  _staged=$(ud_extract_answers "$_payload")
  _rc=$?
  if [ "$_rc" -eq 1 ]; then
    printf '%s' "$_staged"
    return 1
  fi
  [ "$_rc" -eq 0 ] || return 2

  # U+007F alone is refused (jq 1.6 vs 1.7+ escape it differently); the scan stays inside jq.
  if jq -e --argjson del127 127 '
      ([$del127] | implode) as $del
      | [ (.tool_input.questions // [])[].question,
          ((.tool_response // .response // {}).answers // {} | [.[] | if type == "array" then .[]? else . end])[]? ]
      | any(. != null and (tostring | contains($del)))
    ' "$_payload" > /dev/null 2>&1; then
    rm -f "$_staged"
    printf 'unstable_encoding'
    return 1
  fi

  # Checked before locking: ud_lock_acquire's own symlink refusal is indistinguishable from a timeout.
  if [ -L "$_ledger" ]; then
    rm -f "$_staged"
    printf 'ledger_symlink'
    return 1
  fi

  if ! ud_lock_acquire "$_ledger"; then
    rm -f "$_staged"
    printf 'lock_timeout'
    return 1
  fi

  # A last byte that is not LF (tail -c1 prints nothing for a real trailing newline, since
  # command substitution strips it) means an earlier writer left a torn tail.
  if [ -s "$_ledger" ] && [ -n "$(tail -c 1 -- "$_ledger" 2> /dev/null)" ]; then
    ud_lock_release
    rm -f "$_staged"
    printf 'ledger_torn'
    return 1
  fi

  if [ -f "$_ledger" ] && LC_ALL=C grep -qF "\"tool_use_id\":\"$_tuid\"" -- "$_ledger" 2> /dev/null; then
    ud_lock_release
    rm -f "$_staged"
    printf 'replay'
    return 1
  fi

  # P6 runs after P5 (first failure wins): one badly shaped answer refuses the whole call.
  if jq -se 'any(.[]; .question_ok == true and .answer_ok != true)' "$_staged" > /dev/null 2>&1; then
    ud_lock_release
    rm -f "$_staged"
    printf 'answer_shape'
    return 1
  fi

  _n_prior=0
  _prev="null"
  if [ -f "$_ledger" ]; then
    _n_prior=$(LC_ALL=C wc -l < "$_ledger" 2> /dev/null | tr -d ' ')
    case "$_n_prior" in '' | *[!0-9]*) _n_prior=0 ;; esac
    if [ "$_n_prior" -gt 0 ]; then
      _prevline=$(tail -n 1 -- "$_ledger" 2> /dev/null)
      _sha=$(printf '%s' "$_prevline" | ud_digest) || {
        ud_lock_release
        rm -f "$_staged"
        printf 'ledger_torn'
        return 1
      }
      _prev="\"$_sha\""
    fi
  fi
  _wid=$(jq -r '.worktask_id // ""' "$_state" 2> /dev/null)
  _ts_id=$(date -u +%Y%m%dT%H%M%SZ 2> /dev/null) || _ts_id="19700101T000000Z"
  _ts_row=$(date -u +%FT%TZ 2> /dev/null) || _ts_row="unknown"

  _newlines="" _cb_ids="" _any=0
  # The staged file is JSONL; flatten it to TSV here. Header goes last so an empty one cannot
  # shift fields (tab is IFS whitespace, so adjacent tabs collapse), and a header carrying a
  # tab/CR/LF is blanked rather than escaped, so the rest reach `read` byte-exact. Only ids and
  # booleans cross into shell state, never question or answer text.
  while IFS=$'\t' read -r _idx _qok _aok _header; do
    [ -n "$_idx" ] || continue
    [ "$_qok" = "true" ] && [ "$_aok" = "true" ] || continue
    _scope=$(ud_scope_for "$_state" "$_header" "$_payload" "$_idx") || _scope="no_scope"
    [ -n "$_scope" ] && [ "$_scope" != "no_scope" ] || continue

    _n_prior=$((_n_prior + 1))
    _srow=$(jq -c -n --arg id "ud-${_ts_id}-${_n_prior}" --arg ts "$_ts_row" \
      --arg actor "$UD_ACTOR" --arg tuid "$_tuid" --argjson idx "$_idx" \
      --argjson scope "$_scope" --argjson prev "$_prev" --slurpfile pl "$_payload" '
      ($pl[0]) as $p
      | ($p.tool_input.questions[$idx]) as $q
      | (($p.tool_response // $p.response // {}).answers // {}) as $r
      | (($p.tool_input.answers // {})) as $i
      | (($r[$q.question]? // $i[$q.question]?)) as $a
      | (if ($a | type) == "array" then ($a | join(", ")) else $a end) as $answer
      | {id: $id, ts: $ts, actor: $actor, tool_use_id: $tuid,
         question: $q.question, answer: $answer, scope: $scope,
         sha256: null, prev_sha256: $prev}
    ' 2> /dev/null)
    if [ -z "$_srow" ]; then
      _n_prior=$((_n_prior - 1))
      continue
    fi

    _sha=$(printf '%s' "$_srow" | jq -jc '[.question,.answer]' 2> /dev/null | ud_digest)
    if [ -z "$_sha" ]; then
      _n_prior=$((_n_prior - 1))
      continue
    fi
    _line=$(printf '%s' "$_srow" | jq -c --arg sha "$_sha" '.sha256 = $sha' 2> /dev/null)
    if [ -z "$_line" ]; then
      _n_prior=$((_n_prior - 1))
      continue
    fi

    _newlines="${_newlines}${_line}
"
    _cb_item=$(printf '%s' "$_scope" | jq -r '.item // ""' 2> /dev/null)
    _cb_ids="${_cb_ids}ud-${_ts_id}-${_n_prior}	${_tuid}	${_sha}	${_cb_item}
"
    _prev="\"$_sha\""
    _any=1
  done < <(jq -r '
    "\(.index)\t\(.question_ok)\t\(.answer_ok)\t\((.header // "") | if test("[\t\r\n]") then "" else . end)"
  ' "$_staged" 2> /dev/null)
  rm -f "$_staged"

  if [ "$_any" -eq 0 ]; then
    ud_lock_release
    printf 'no_scope'
    return 1
  fi

  _tmp="${_ledger}.tmp.$$"
  (
    umask 077
    [ -f "$_ledger" ] && cat -- "$_ledger" > "$_tmp"
    printf '%s' "$_newlines" >> "$_tmp"
  ) 2> /dev/null
  if [ ! -f "$_tmp" ] || [ -L "$_ledger" ] || ! mv -f -- "$_tmp" "$_ledger" 2> /dev/null; then
    rm -f "$_tmp"
    ud_lock_release
    return 2
  fi
  chmod 0600 "$_ledger" 2> /dev/null

  while IFS=$'\t' read -r _cb_id _cb_tuid _cb_sha _cb_item; do
    [ -n "$_cb_id" ] || continue
    "$_cb" "$_cb_id" "$_cb_tuid" "$_cb_sha" "$_cb_item"
  done <<< "$_cb_ids"

  ud_lock_release
  return 0
}

# ud_chain_walk <ledger> — JSONL, one `{index, id, line_sha256, reasons[]}` per stored line
# (1-based). Batched: one jq pass builds every row's canonical bytes, one shasum call digests
# every row+canon file pair, one jq pass assembles the reasons — not one shasum per row, which
# is what makes a 200-row ledger cost a handful of forks rather than hundreds.
ud_chain_walk() {
  local _ledger _raw _td _tsv _n _shaout _rc
  local _row_line _row_meta _row_canon _i _notail
  local _files

  _ledger="${1:-}"
  [ -n "$_ledger" ] || return 2
  command -v jq > /dev/null 2>&1 || return 2

  if [ -L "$_ledger" ]; then
    printf '{"index":1,"id":null,"line_sha256":null,"reasons":["ledger_symlink"]}\n'
    return 0
  fi
  [ -f "$_ledger" ] || return 0

  # AD6: NUL, CR or a missing final LF is malformed. A NUL cannot survive the `$( )` snapshot at
  # all, so it refuses the whole ledger here; CR is caught per line inside jq; a missing final LF
  # is invisible to `cat` and is carried to the last row as $notail.
  if [ -s "$_ledger" ] \
    && [ "$(LC_ALL=C tr -dc '\000' < "$_ledger" 2> /dev/null | LC_ALL=C wc -c | tr -d ' ')" != "0" ]; then
    printf '{"index":1,"id":null,"line_sha256":null,"reasons":["malformed_row"]}\n'
    return 0
  fi
  _notail=0
  if [ -s "$_ledger" ] && [ -n "$(tail -c 1 -- "$_ledger" 2> /dev/null)" ]; then
    _notail=1
  fi

  _raw=$(cat -- "$_ledger" 2> /dev/null)
  [ -n "$_raw" ] || return 0

  _td=$(mktemp -d 2> /dev/null) || return 2

  # Two lines per stored line: the @tsv meta record, then the canonical [question,answer] JSON.
  # Neither carries a raw LF, and neither passes through @tsv's backslash escaping on its way to
  # a digest — the raw line bytes come from `read` over the snapshot itself, below.
  _tsv=$(printf '%s' "$_raw" | jq -Rr --arg keys "$UD_ROW_KEYS" '
    ($keys | split(" ")) as $want
    | . as $l
    | (try fromjson catch null) as $row
    | if (($l | test("\r")) or $row == null or ($row | type) != "object") then
        (["", "", "", "", "", "no"] | @tsv), "null"
      else
        ([($row.id // "" | tostring), ($row.actor // "" | tostring),
          ($row.prev_sha256 // "" | tostring), ($row.sha256 // "" | tostring),
          ($row.tool_use_id // "" | tostring),
          (if (($row | keys_unsorted) == $want) then "yes" else "no" end)] | @tsv),
        ([$row.question, $row.answer] | tojson)
      end
  ' 2> /dev/null)
  if [ -z "$_tsv" ]; then
    rm -rf "$_td"
    return 2
  fi

  _n=0
  _files=()
  while IFS= read -r _row_line; do
    _n=$((_n + 1))
    printf '%s' "$_row_line" > "$_td/raw.$_n"
    _files+=("$_td/raw.$_n" "$_td/canon.$_n")
  done <<< "$_raw"

  _i=0
  : > "$_td/meta"
  while IFS= read -r _row_meta && IFS= read -r _row_canon; do
    _i=$((_i + 1))
    printf '%s\n' "$_row_meta" >> "$_td/meta"
    printf '%s' "$_row_canon" > "$_td/canon.$_i"
  done <<< "$_tsv"

  if [ "$_n" -eq 0 ] || [ "$_i" -ne "$_n" ]; then
    rm -rf "$_td"
    [ "$_n" -eq 0 ] && return 0
    return 2
  fi

  if command -v shasum > /dev/null 2>&1; then
    _shaout=$(LC_ALL=C shasum -a 256 -- "${_files[@]}" 2> /dev/null)
  elif command -v sha256sum > /dev/null 2>&1; then
    _shaout=$(LC_ALL=C sha256sum -- "${_files[@]}" 2> /dev/null)
  else
    rm -rf "$_td"
    return 2
  fi
  if [ -z "$_shaout" ]; then
    rm -rf "$_td"
    return 2
  fi

  # -r: each row leaves as its own JSON line, not as a quoted JSON string of that line.
  printf '%s\n' "$_shaout" | jq -Rnr --rawfile meta "$_td/meta" --argjson n "$_n" \
    --argjson notail "$_notail" --arg actor "$UD_ACTOR" '
    def digline: capture("^(?<h>[0-9a-f]{64})[ *]+(?<p>\\S.*)$");
    ([inputs | select(length > 0) | digline]) as $digs
    | (reduce $digs[] as $d ({}; . + {($d.p | split("/") | last): $d.h})) as $byname
    | ($meta | split("\n") | map(select(length > 0)) | map(split("\t"))) as $rows
    | ($rows | map(.[0])) as $ids
    | ($rows | map(.[4])) as $tuids
    | range(0; $n) as $i
    | ($rows[$i]) as $m
    | ($i + 1) as $idx
    | ($byname["raw." + ($idx | tostring)]) as $line_sha
    | ($byname["canon." + ($idx | tostring)]) as $canon_sha
    | ($m[5] == "yes") as $shape_ok
    | (if $shape_ok then null else "malformed_row" end) as $r_shape
    | (if $shape_ok and $notail == 1 and $idx == $n then "malformed_row" else null end) as $r_tail
    | (if $shape_ok and $m[3] != $canon_sha then "sha256_mismatch" else null end) as $r_sha
    | (if $shape_ok and $m[1] != $actor then "actor_mismatch" else null end) as $r_actor
    | (if $shape_ok then
         (($m[0] | capture("-(?<n>[0-9]+)$").n // null) | (try tonumber catch null) // -1) as $ord
         | (if $ord != $idx then true
            elif $idx == 1 then $m[2] != ""
            else $m[2] != ($byname["raw." + (($idx - 1) | tostring)] // "") end)
       else false end) as $chain_bad
    | (if $shape_ok and $chain_bad then "chain_broken" else null end) as $r_chain
    | (if $shape_ok and (($ids | map(select(. == $m[0]))) | length) > 1 then "duplicate_id" else null end) as $r_dupid
    | (if $shape_ok and (($tuids | map(select(. == $m[4]))) | length) > 1 then "duplicate_tool_use" else null end) as $r_duptu
    | ([$r_shape, $r_tail, $r_sha, $r_actor, $r_chain, $r_dupid, $r_duptu] | map(select(. != null))) as $reasons
    | {index: $idx, id: (if $shape_ok then $m[0] else null end), line_sha256: $line_sha, reasons: $reasons}
    | tojson
  ' 2> /dev/null
  _rc=$?
  rm -rf "$_td"
  [ "$_rc" -eq 0 ] || return 2
  return 0
}

# ud_audit_corroborates <audit.jsonl> <id> <tool_use_id> <line_sha256> — rc 0 when a
# user_decision_recorded row from UD_ACTOR names this id with this tool_use_id and row_sha256,
# and no row names this id with a DIFFERENT row_sha256 (a corroborated forgery is a contradiction,
# not a pass).
ud_audit_corroborates() {
  local _audit _id _tuid _sha
  _audit="${1:-}" _id="${2:-}" _tuid="${3:-}" _sha="${4:-}"
  [ -f "$_audit" ] && [ -n "$_id" ] && [ -n "$_tuid" ] && [ -n "$_sha" ] || return 1
  command -v jq > /dev/null 2>&1 || return 1
  jq -nRe --arg id "$_id" --arg tuid "$_tuid" --arg sha "$_sha" --arg actor "$UD_ACTOR" '
    [inputs | (try fromjson catch null) | select(. != null and type == "object"
      and .action == "user_decision_recorded" and .actor == $actor and .subject == $id)] as $rows
    | ($rows | any(.metadata.tool_use_id == $tuid and .metadata.row_sha256 == $sha)) as $match
    | ($rows | any(.metadata.row_sha256 != $sha)) as $conflict
    | $match and ($conflict | not)
  ' "$_audit" > /dev/null 2>&1
}

# ud_verify <state.json> <ledger> <audit> <ud-id> <task_id> [expect] — prints the verifier JSON.
# Subshell-bodied and option-neutral (`set +eE -u`) so a caller's own option set survives a call;
# `rc=0; ud_verify … || rc=$?` is the declared idiom. rc 0 valid, rc 1 refused, rc 2 usage/IO.
# Question/answer/scope leave this function only through jq's own stdout, reading the ledger
# file directly — never through a shell variable holding decoded text.
ud_verify() (
  trap - ERR EXIT
  set +eE -u
  IFS=$' \t\n'
  local state ledger audit id task expect has_expect
  local wid reasons idx chain_n walk row dup checks found tuid sha valid _ud_whole
  state="${1:-}" ledger="${2:-}" audit="${3:-}" id="${4:-}" task="${5:-}" expect="${6:-}"
  has_expect=0
  [ "$#" -ge 6 ] && has_expect=1
  if [ -z "$state" ] || [ -z "$ledger" ] || [ -z "$id" ] || [ -z "$task" ]; then
    printf '{}'
    exit 2
  fi
  command -v jq > /dev/null 2>&1 || {
    printf '{}'
    exit 2
  }
  # Whole-string, not grep's per-line match: an id carrying an LF whose second line looks like a
  # valid id is a usage error (exit 2), never a lookup that can reach exit 5.
  [[ $id =~ $UD_ID_RE ]] || {
    printf '{}'
    exit 2
  }

  # AD2: escaping drift is exit 2, never a refusal, so a jq upgrade is never read as forgery.
  ud_canon_ok || {
    jq -cn --arg id "$id" --arg task "$task" '
      {decision_ref: $id, task_id: $task, valid: false, reasons: ["jq_canon_drift"],
       question: null, answer: null, scope: null, row_index: null, chain_rows: 0}'
    exit 2
  }

  wid=""
  [ -f "$state" ] && [ ! -L "$state" ] && wid=$(jq -r '.worktask_id // ""' "$state" 2> /dev/null)

  idx="" chain_n=0 reasons="[]"

  if [ -L "$ledger" ]; then
    reasons='["ledger_symlink"]'
  elif [ ! -f "$ledger" ]; then
    reasons='["not_found"]'
  else
    walk=$(ud_chain_walk "$ledger" 2> /dev/null)
    chain_n=$(printf '%s\n' "$walk" | LC_ALL=C grep -c . 2> /dev/null)
    [ -n "$chain_n" ] || chain_n=0
    row=$(printf '%s\n' "$walk" | jq -c --arg id "$id" 'select(.id == $id)' 2> /dev/null | head -n 1)
    # AD6 whole-ledger trust: an edit anywhere refuses everything, so every row's integrity
    # reasons are folded into the target's. Reported in UD_REASONS check order.
    # shellcheck disable=SC2016  # jq program text: $r/$o/$all are jq variables
    _ud_whole='
      ["ledger_symlink","malformed_row","duplicate_id","duplicate_tool_use",
       "actor_mismatch","sha256_mismatch","chain_broken"] as $whole
      | ($order | split(" ")) as $o
      | ($base + [$rows[] | (.reasons // [])[] | select(. as $r | $whole | any(.[]; . == $r))]) as $all
      | [$o[] | select(. as $r | $all | any(.[]; . == $r))]'

    if [ -z "$row" ]; then
      reasons=$(printf '%s\n' "$walk" | jq -sc --argjson base '["not_found"]' --arg order "$UD_REASONS" \
        '. as $rows | '"$_ud_whole" 2> /dev/null)
      [ -n "$reasons" ] || reasons='["not_found"]'
    else
      idx=$(printf '%s' "$row" | jq -r '.index')
      reasons=$(printf '%s' "$row" | jq -c '.reasons')

      dup=$(printf '%s\n' "$walk" | jq -sc --arg id "$id" '[.[] | select(.id == $id)] | length')
      [ "${dup:-1}" -gt 1 ] && reasons=$(printf '%s' "$reasons" | jq -c '. + ["duplicate_id"] | unique')
      reasons=$(printf '%s\n' "$walk" | jq -sc --argjson base "$reasons" --arg order "$UD_REASONS" \
        '. as $rows | '"$_ud_whole" 2> /dev/null) || reasons=""
      [ -n "$reasons" ] || reasons='["malformed_row"]'

      if [ "$(printf '%s' "$reasons" | jq 'length')" = "0" ]; then
        checks=$(jq -nc --arg id "$id" --arg wid "$wid" --arg task "$task" \
          --argjson has_expect "$has_expect" --arg expect "$expect" '
          ([inputs | select(.id == $id)] | .[0]) as $row
          | if $row == null then {found: false}
            else {
              found: true,
              tool_use_id: ($row.tool_use_id // ""),
              sha256: ($row.sha256 // ""),
              worktask_mismatch: (($row.scope.worktask_id // "") != $wid),
              scope_not_covering: ((($row.scope.task_ids // []) | index($task)) == null),
              answer_mismatch: ($has_expect == 1 and ($row.answer // "") != $expect)
            } end
        ' "$ledger" 2> /dev/null)
        [ -n "$checks" ] || checks='{"found":false}'
        found=$(printf '%s' "$checks" | jq -r '.found')
        if [ "$found" != "true" ]; then
          reasons=$(printf '%s' "$reasons" | jq -c '. + ["not_found"]')
        else
          tuid=$(printf '%s' "$checks" | jq -r '.tool_use_id')
          sha=$(printf '%s' "$checks" | jq -r '.sha256')
          [ "$(printf '%s' "$checks" | jq -r '.worktask_mismatch')" = true ] \
            && reasons=$(printf '%s' "$reasons" | jq -c '. + ["worktask_mismatch"]')
          [ "$(printf '%s' "$checks" | jq -r '.scope_not_covering')" = true ] \
            && reasons=$(printf '%s' "$reasons" | jq -c '. + ["scope_not_covering"]')
          if [ -f "$audit" ]; then
            ud_audit_corroborates "$audit" "$id" "$tuid" "$sha" \
              || reasons=$(printf '%s' "$reasons" | jq -c '. + ["audit_uncorroborated"]')
          else
            reasons=$(printf '%s' "$reasons" | jq -c '. + ["audit_uncorroborated"]')
          fi
          if [ "$has_expect" -eq 1 ] && [ "$(printf '%s' "$checks" | jq -r '.answer_mismatch')" = true ]; then
            reasons=$(printf '%s' "$reasons" | jq -c '. + ["answer_mismatch"]')
          fi
        fi
      fi
    fi
  fi

  valid=false
  [ "$(printf '%s' "$reasons" | jq 'length' 2> /dev/null)" = "0" ] && valid=true

  if [ "$valid" = true ] && [ -f "$ledger" ] && [ ! -L "$ledger" ]; then
    jq -nc --arg id "$id" --arg task "$task" --argjson reasons "$reasons" \
      --argjson idx "${idx:-null}" --argjson chainn "$chain_n" '
      ([inputs | select(.id == $id)] | .[0]) as $row
      | {decision_ref: $id, task_id: $task, valid: true, reasons: $reasons,
         question: $row.question, answer: $row.answer, scope: $row.scope,
         row_index: $idx, chain_rows: $chainn}
    ' "$ledger" 2> /dev/null
  else
    jq -cn --arg id "$id" --arg task "$task" --argjson reasons "$reasons" --argjson chainn "$chain_n" '
      {decision_ref: $id, task_id: $task, valid: false, reasons: $reasons,
       question: null, answer: null, scope: null, row_index: null, chain_rows: $chainn}
    '
  fi

  if [ "$valid" = true ]; then exit 0; else exit 1; fi
)

# ud_find_covering <state.json> <ledger> <audit> <task_id> — the newest valid id whose scope
# covers <task_id> and that no recorded `blocked_on` row for this subject already carries as its
# decision_ref. Prints the id, or nothing (rc 0 either way — "not found" is not a failure here).
ud_find_covering() {
  local _state _ledger _audit _task _ids _id _v _consumed _walk
  _state="${1:-}" _ledger="${2:-}" _audit="${3:-}" _task="${4:-}"
  [ -n "$_state" ] && [ -n "$_ledger" ] && [ -n "$_task" ] || return 2
  command -v jq > /dev/null 2>&1 || return 2
  [ -f "$_ledger" ] && [ ! -L "$_ledger" ] || return 0

  # AD6 whole-ledger trust, checked once up front: any integrity reason on any row (or a walk
  # that cannot run) means no row covers anything.
  _walk=$(ud_chain_walk "$_ledger" 2> /dev/null) || return 0
  [ -n "$_walk" ] || return 0
  printf '%s\n' "$_walk" | jq -se 'all(.[]; (.reasons // ["malformed_row"]) | length == 0)' \
    > /dev/null 2>&1 || return 0

  _ids=$(jq -r --arg t "$_task" '
    select(((.scope.task_ids // []) | index($t)) != null) | .id
  ' "$_ledger" 2> /dev/null | sed -n '1!G;h;$p' 2> /dev/null)
  [ -n "$_ids" ] || return 0

  while IFS= read -r _id; do
    [ -n "$_id" ] || continue
    _consumed=false
    if [ -f "$_audit" ]; then
      jq -nRe --arg id "$_id" --arg t "$_task" '
        any(inputs | (try fromjson catch null); . != null and type == "object"
          and .action == "blocked_on" and .subject == $t and (.metadata.decision_ref? // "") == $id)
      ' "$_audit" > /dev/null 2>&1 && _consumed=true
    fi
    [ "$_consumed" = true ] && continue
    # rc 1 (a refused candidate) is this loop's normal case: keep it off a `set -e` caller.
    _v=$(ud_verify "$_state" "$_ledger" "$_audit" "$_id" "$_task" 2> /dev/null) || _v=""
    if printf '%s' "$_v" | jq -e '.valid == true' > /dev/null 2>&1; then
      printf '%s' "$_id"
      return 0
    fi
  done <<< "$_ids"
  return 0
}
