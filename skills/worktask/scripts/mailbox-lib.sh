#!/usr/bin/env bash
# @description mailbox-lib.sh — the one definition of the durable cross-session mailbox: the
#   ask_id grammar, the request/reply file shapes, the atomic no-clobber writer, the reply
#   verifier and the leg-metadata builder. Sourced by mailbox.sh, mailbox-reply.sh and
#   blocked-on-dispatch.sh, so the router's route/resume and the two CLIs agree on one grammar,
#   one hash input and one dedupe key without a second copy anywhere to drift.
#
#   Change protocol: a file-shape or grammar change here changes the shared-seam registry entry and the seam
#   declaration in the same PR.
#
#   Symbols: MB_ASK_ID_ERE, MB_JQ_DEFS (mb_epoch, mb_schema_ok, mb_answer_ok, mb_hash_input),
#   mb_valid_ask_id, mb_now, mb_dir, mb_write_nc, mb_sha256, mb_create_request, mb_read_request,
#   mb_verified_reply, mb_leg_meta, mb_leg_recorded.
#
# @exitcode 2 executed rather than sourced
#
# Minimum shell: bash 3.2+. jq required by every symbol except mb_valid_ask_id and mb_now.

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  printf >&2 'mailbox-lib.sh: this is a library — source it, do not execute it directly\n'
  exit 2
fi
[ -n "${_MAILBOX_LIB:-}" ] && return 0
_MAILBOX_LIB=1

# Not readonly: consumer suites source this file more than once per process, and a second
# readonly assignment returns 1 under a `set -e` caller.
_MB_LIB_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2> /dev/null && pwd -P)" || _MB_LIB_DIR=""
_MB_RESOLVE_ROOT="$_MB_LIB_DIR/../../shared/scripts/resolve-root.sh"

# Lowercase-only UTC stamp plus 12 hex chars from 6 random bytes — 32 bytes total, no `/` or
# `..` reachable through it. Checked before any path join; nothing this library writes ever
# trusts an id it has not run through mb_valid_ask_id first.
MB_ASK_ID_ERE='^ask-[0-9]{8}t[0-9]{6}z-[0-9a-f]{12}$'

# shellcheck disable=SC2016  # jq program text: its $names are jq variables, not shell ones
MB_JQ_DEFS='
def mb_epoch:
  if type != "string" then null else
    (capture("^(?<y>[0-9]{4})-(?<mo>[0-9]{2})-(?<d>[0-9]{2})T(?<h>[0-9]{2}):(?<mi>[0-9]{2}):(?<s>[0-9]{2})(?:\\.[0-9]+)?(?<tz>Z|[+-][0-9]{2}:[0-9]{2})$")?) as $c
    | if $c == null then null else
        ($c.y | tonumber) as $y | ($c.mo | tonumber) as $mo | ($c.d | tonumber) as $d
        | ($c.h | tonumber) as $h | ($c.mi | tonumber) as $mi | ($c.s | tonumber) as $s
        | (if $c.tz == "Z" then 0
           else (($c.tz[1:3] | tonumber) * 3600 + ($c.tz[4:6] | tonumber) * 60)
                * (if $c.tz[0:1] == "-" then -1 else 1 end)
           end) as $off
        | ("\($y)-\($mo)-\($d)T\($h):\($mi):\($s)Z" | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime) - $off
      end
  end;
def mb_schema_ok:
  (type == "object")
  and ((keys - ["type", "maxLength", "minLength", "enum"]) == [])
  and (.type == "string")
  and ((.maxLength | type) == "number" and (.maxLength | floor) == .maxLength
       and .maxLength >= 1 and .maxLength <= 4000)
  and ((.minLength // 1) as $mn | (($mn | type) == "number") and (($mn | floor) == $mn)
       and $mn >= 0 and $mn <= .maxLength)
  and (if has("enum") then
         (.enum | type) == "array" and (.enum | length) >= 1 and (.enum | length) <= 50
         and (.enum | all(.[]; type == "string" and length <= 200))
       else true end);
def mb_answer_ok($schema):
  (type == "string")
  and (($schema.minLength // 1) as $mn | ($schema.maxLength) as $mx | length >= $mn and length <= $mx)
  and (if ($schema | has("enum")) then (. as $a | $schema.enum | index($a) != null) else true end);
def mb_hash_input($ask_id; $kind; $session; $ts; $answer):
  [$ask_id, $kind, $session, $ts, $answer] | join("\n");
'

# mb_valid_ask_id <id> — the one gate before any ask_id reaches a path join.
mb_valid_ask_id() {
  [[ "${1:-}" =~ $MB_ASK_ID_ERE ]]
}

# mb_now — MAILBOX_NOW (test seam, epoch int) when set and numeric, else the host clock. ISO
# stamps are always derived from this through jq todate: no GNU/BSD `date` formatting split.
mb_now() {
  if [ -n "${MAILBOX_NOW:-}" ]; then
    case "$MAILBOX_NOW" in
      *[!0-9]*) : ;;
      '') : ;;
      *)
        printf '%s' "$MAILBOX_NOW"
        return 0
        ;;
    esac
  fi
  date +%s
}

# mb_new_ask_id <epoch> — one candidate id for mb_create_request's retry loop; never trusted
# without a following mb_valid_ask_id call, even though its own shape matches the grammar.
mb_new_ask_id() {
  local stamp rand
  command -v jq > /dev/null 2>&1 || return 1
  stamp=$(jq -rn --argjson t "${1:-0}" '($t | todate) | gsub("[-:]"; "") | ascii_downcase' 2> /dev/null) || return 1
  [ -n "$stamp" ] || return 1
  rand=$(od -An -N6 -tx1 /dev/urandom 2> /dev/null | tr -d ' \n') || return 1
  [ "${#rand}" -eq 12 ] || return 1
  printf 'ask-%s-%s' "$stamp" "$rand"
}

# mb_dir — prints the mailbox root (…/mailbox, or MAILBOX_DIR verbatim under the test
# seam) with requests/ and replies/ siblings created and mode 700, or returns 1 ("unavailable")
# without printing anything. Refuses a symlink, a non-directory or a dir this process does not
# own at any of the three levels it manages (mailbox/, requests/, replies/) — never a partial
# mailbox root a later write could be redirected through.
mb_dir() {
  local root ctx d
  if [ -n "${MAILBOX_DIR:-}" ]; then
    case "$MAILBOX_DIR" in
      /*) root="$MAILBOX_DIR" ;;
      *) return 1 ;;
    esac
  else
    [ -r "$_MB_RESOLVE_ROOT" ] || return 1
    ctx=$(bash "$_MB_RESOLVE_ROOT" 2> /dev/null) || return 1
    [ -n "$ctx" ] || return 1
    if [ ! -e "$ctx" ]; then
      mkdir -m 700 -- "$ctx" 2> /dev/null || return 1
    fi
    [ -d "$ctx" ] && [ ! -L "$ctx" ] || return 1
    root="$ctx/mailbox"
  fi
  for d in "$root" "$root/requests" "$root/replies"; do
    if [ ! -e "$d" ]; then
      mkdir -m 700 -- "$d" 2> /dev/null || return 1
    fi
    [ ! -L "$d" ] || return 1
    [ -d "$d" ] || return 1
    [ -O "$d" ] || return 1
    # No `--`: BSD chmod takes it as a filename, so the guard would fail every call
    # on macOS. Safe without one — every $d here is an absolute path.
    chmod 700 "$d" 2> /dev/null || return 1
  done
  printf '%s' "$root"
  return 0
}

# mb_sha256 — stdin to lowercase hex on stdout; rc 2 with neither tool installed.
mb_sha256() {
  if command -v shasum > /dev/null 2>&1; then
    shasum -a 256 2> /dev/null | awk '{print $1}'
  elif command -v sha256sum > /dev/null 2>&1; then
    sha256sum 2> /dev/null | awk '{print $1}'
  else
    return 2
  fi
}

# mb_write_nc <dir> <ask_id> <json> — the atomic no-clobber write. rc 0 written; rc 1 the
# target already exists (first writer wins); rc 2 any other I/O refusal (symlinked target,
# mktemp/chmod/write failure). The umask and the temp file live in one subshell so a caller's
# umask is never touched and a failed write never leaves the temp file behind.
mb_write_nc() {
  local dir="$1" id="$2" json="$3"
  local target="$dir/$id.json"
  [ ! -L "$target" ] || return 2
  (
    umask 077
    tmp=$(mktemp "$dir/.$id.json.XXXXXX" 2> /dev/null) || exit 2
    if ! printf '%s\n' "$json" > "$tmp" || ! chmod 600 "$tmp" 2> /dev/null; then
      rm -f -- "$tmp"
      exit 2
    fi
    if [ -L "$target" ]; then
      rm -f -- "$tmp"
      exit 2
    fi
    if ln -- "$tmp" "$target" 2> /dev/null; then
      rm -f -- "$tmp"
      exit 0
    fi
    rm -f -- "$tmp"
    if [ -e "$target" ]; then exit 1; else exit 2; fi
  )
}

# mb_create_request <from_task> <to> <question> <deadline-or-empty> — writes requests/<id>.json
# and prints {"ask_id","deadline"}. rc 1: mailbox unavailable (a directory-check refusal, or 3 retries
# exhausted on a write collision — both read as "unavailable" by the router as unavailable).
# rc 3: the given deadline does not parse as ISO-8601 (kept apart from rc 1 so the router can
# emit its own named fail: line rather than folding a value error into the availability path).
mb_create_request() {
  local from="$1" to="$2" question="$3" deadline_in="${4:-}"
  local now created_at deadline_epoch deadline_iso dir req_dir ask_id out i=0 rc
  command -v jq > /dev/null 2>&1 || return 1
  now=$(mb_now)
  created_at=$(jq -rn --argjson t "$now" '($t | todate)' 2> /dev/null) || return 1
  [ -n "$created_at" ] || return 1

  if [ -n "$deadline_in" ]; then
    deadline_epoch=$(jq -rn --arg d "$deadline_in" "$MB_JQ_DEFS"'($d | mb_epoch) // "x"' 2> /dev/null) || deadline_epoch="x"
    case "$deadline_epoch" in
      '' | *[!0-9]*) return 3 ;;
    esac
  else
    deadline_epoch=$((now + 1800))
  fi
  [ "$deadline_epoch" -ge "$((now + 60))" ] || deadline_epoch=$((now + 60))
  [ "$deadline_epoch" -le "$((now + 86400))" ] || deadline_epoch=$((now + 86400))
  deadline_iso=$(jq -rn --argjson t "$deadline_epoch" '($t | todate)' 2> /dev/null) || return 1
  [ -n "$deadline_iso" ] || return 1

  dir=$(mb_dir) || return 1
  req_dir="$dir/requests"

  while [ "$i" -lt 3 ]; do
    ask_id=$(mb_new_ask_id "$now") || return 1
    mb_valid_ask_id "$ask_id" || return 1
    out=$(jq -cn --arg id "$ask_id" --arg f "$from" --arg to "$to" --arg q "$question" \
      --arg dl "$deadline_iso" --arg ca "$created_at" \
      '{ask_id: $id, from_task: $f, to: $to, question: $q, deadline: $dl, created_at: $ca,
        reply_schema: {type: "string", minLength: 1, maxLength: 2000}}' 2> /dev/null) || return 1
    rc=0
    mb_write_nc "$req_dir" "$ask_id" "$out" || rc=$?
    if [ "$rc" -eq 0 ]; then
      jq -cn --arg id "$ask_id" --arg dl "$deadline_iso" '{ask_id: $id, deadline: $dl}'
      return 0
    fi
    if [ "$rc" -eq 1 ]; then
      i=$((i + 1))
      continue
    fi
    return 1
  done
  return 1
}

# mb_read_request <ask_id> — the request JSON on stdout, rc 0; rc 1 on a bad id, a missing,
# symlinked, non-regular or unparseable file.
mb_read_request() {
  local id="$1" dir f
  mb_valid_ask_id "$id" || return 1
  dir=$(mb_dir) || return 1
  f="$dir/requests/$id.json"
  [ -e "$f" ] && [ ! -L "$f" ] && [ -f "$f" ] || return 1
  jq -e '.' "$f" 2> /dev/null
}

# mb_verified_reply <ask_id> — the reply JSON on stdout, rc 0, ONLY when the file is a
# regular file, its own ask_id matches, its shape is complete, its sha256 matches
# mb_hash_input's recomputation, and (when the request is still readable) its answer still
# satisfies that request's reply_schema. Any miss is rc 1 — an unreadable or inconsistent reply
# counts as no reply, never as a soft warning, so it cannot hold an ask open past its deadline.
#
# The hash is unkeyed over public inputs, so it establishes integrity, not authenticity: anyone
# who can write the file can recompute it. What keeps a forged reply out is mb_dir's 0700 and
# owner checks on the mailbox, not this check.
mb_verified_reply() {
  local id="$1" dir f reply kind session ts sha_have answer sha_calc req schema ok
  mb_valid_ask_id "$id" || return 1
  dir=$(mb_dir) || return 1
  f="$dir/replies/$id.json"
  [ -e "$f" ] && [ ! -L "$f" ] && [ -f "$f" ] || return 1
  reply=$(jq -c '.' "$f" 2> /dev/null) || return 1
  [ -n "$reply" ] || return 1
  printf '%s' "$reply" | jq -e --arg id "$id" '
    .ask_id == $id and (.answer | type) == "string" and (.ts | type) == "string"
    and (.answered_by | type) == "object" and (.answered_by.kind | type) == "string"
    and (.answered_by.session | type) == "string" and (.sha256 | type) == "string"' \
    > /dev/null 2>&1 || return 1
  kind=$(printf '%s' "$reply" | jq -r '.answered_by.kind')
  session=$(printf '%s' "$reply" | jq -r '.answered_by.session')
  ts=$(printf '%s' "$reply" | jq -r '.ts')
  sha_have=$(printf '%s' "$reply" | jq -r '.sha256')
  answer=$(printf '%s' "$reply" | jq -j '.answer')
  sha_calc=$(jq -j -n --arg a "$id" --arg k "$kind" --arg s "$session" --arg t "$ts" --arg ans "$answer" \
    "$MB_JQ_DEFS"'mb_hash_input($a;$k;$s;$t;$ans)' 2> /dev/null | mb_sha256) || return 1
  [ -n "$sha_calc" ] && [ "$sha_calc" = "$sha_have" ] || return 1

  if req=$(mb_read_request "$id" 2> /dev/null); then
    schema=$(printf '%s' "$req" | jq -c '.reply_schema // {}' 2> /dev/null) || schema='{}'
    ok=$(jq -n --arg ans "$answer" --argjson sc "$schema" "$MB_JQ_DEFS"'$ans | mb_answer_ok($sc)' 2> /dev/null) || ok=false
    [ "$ok" = "true" ] || return 1
  fi
  printf '%s\n' "$reply"
  return 0
}

# mb_leg_meta <leg> <ask_id> [transport] [transport_result] [answered_by_kind] [reply_ref]
#             [decision_ref] — no key here ever carries question, options or answer text;
#             the caller decides which optional fields apply for its leg.
mb_leg_meta() {
  jq -cn --arg l "$1" --arg id "$2" --arg tr "${3:-}" --arg tres "${4:-}" \
    --arg abk "${5:-}" --arg rr "${6:-}" --arg dr "${7:-}" '
    {kind: "peer_session", arm: "peer_session", leg: $l, ask_id: $id}
    + (if $tr != "" then {transport: $tr} else {} end)
    + (if $tres != "" then {transport_result: $tres} else {} end)
    + (if $abk != "" then {answered_by_kind: $abk} else {} end)
    + (if $rr != "" then {reply_ref: $rr} else {} end)
    + (if $dr != "" then {decision_ref: $dr} else {} end)'
}

# mb_leg_recorded <audit.jsonl> <task_id> <ask_id> <leg> — dedupe on (subject,
# metadata.ask_id, metadata.leg), never on a closing-row window. Each ask_id is written once, so
# there is no reopen case that needs a leg replayed under the same id.
mb_leg_recorded() {
  local audit="$1" task_id="$2" ask_id="$3" leg="$4"
  [ -f "$audit" ] || return 1
  jq -nRe --arg t "$task_id" --arg a "$ask_id" --arg l "$leg" '
    [inputs | fromjson? | select(type == "object" and .action == "blocked_on"
      and .subject == $t and (.metadata.ask_id? // "") == $a and .metadata.leg == $l)]
    | length > 0' "$audit" > /dev/null 2>&1
}
