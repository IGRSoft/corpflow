#!/usr/bin/env bash
# @description mailbox.sh — the orchestrator side of the durable cross-session mailbox: writes
#   the sent/delivered/answered/expired legs, renders and posts the comment transport, ingests
#   accepted reply comments, and scans/sweeps the run's own open asks against their deadlines.
#   mailbox-reply.sh is the only writer of replies/; this script never writes one (a replier
#   in another worktree has no ledger task to cite, so only the originating orchestrator logs).
#
# Usage:
#   mailbox.sh show    --ask-id <id> [--state <state.json>]
#   mailbox.sh leg      --task-id <ID> --ask-id <id> --leg sent|delivered --transport message
#                        [--result ok|queued|refused|dropped|oversized|burst_limited]
#                        [--state <state.json>]
#   mailbox.sh comment --task-id <ID> [--render-only] [--state <state.json>]
#   mailbox.sh ingest-comments [--state <state.json>]
#   mailbox.sh scan     [--state <state.json>]
#   mailbox.sh sweep    [--state <state.json>]
#   mailbox.sh wait     [--max-seconds N] [--state <state.json>]
#
# @arg show     Prints the request JSON for --ask-id verbatim (a same-repo peer's read of
#                "mailbox ask <ask_id>"). No ledger lookup: the mailbox file is the answer.
# @arg leg      The message transport.s legs only (comment writes its own). Refuses a task that
#                is not an open peer_session ask for the given id. Idempotent: a leg
#                already recorded for (task, ask_id, leg) writes nothing and reports so.
# @arg comment  Gate order (opt-out, then issue lookup, then render, then post) — checked in
#                that order both at runtime and in this file.s source order. --render-only stops
#                after render and writes no leg and makes no gh call.
# @arg ingest-comments  The accepted-reply filter over the run.s comments, the answer-file
#                pipe into mailbox-reply.sh, and the mailbox_ingest row when anything was
#                ignored.
# @arg scan     Ledger scan; writes the answered leg (if absent) for every verified reply.
# @arg sweep    Deadline expiry; routes an expired ask to user_decision through the
#                router's own fallback.
# @arg wait     Loop-boundary fallback poll; backgroundable, never required.
#
# @exitcode 0 ok
# @exitcode 1 refused: not an open ask, an invalid leg, or a bad ask_id
# @exitcode 2 usage error, missing or unparseable ledger, or a broken plugin install
#
# Minimum shell: bash 3.2+. Requires jq.
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
_MB_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd -P)"
_MB_DISPATCH="$SCRIPT_DIR/blocked-on-dispatch.sh"
_MB_STATE_PATCH="$SCRIPT_DIR/state-patch.sh"
_MB_REPLY="$SCRIPT_DIR/mailbox-reply.sh"
_MB_PATH_SCRUB="$_MB_ROOT/skills/shared/scripts/path-scrub.sh"
_MB_PUBLISH_LIB="$SCRIPT_DIR/publish-pl-issue.sh"
GH_BIN="${GH_BIN:-gh}"

die() {
  printf >&2 'mailbox: %s\n' "$2"
  exit "$1"
}

usage() {
  sed -n '/^# Usage:/,/^# @arg show/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//' >&2
  exit 2
}

command -v jq > /dev/null 2>&1 || die 2 "jq is required"
for _mb_lib in "$_MB_ROOT/hooks/lib/permission-denied-lib.sh" \
  "$_MB_ROOT/skills/shared/lib/audit-lib.sh" \
  "$_MB_ROOT/skills/shared/lib/state-read-lib.sh" \
  "$SCRIPT_DIR/mailbox-lib.sh"; do
  [ -r "$_mb_lib" ] || die 2 "plugin install broken — missing $_mb_lib"
  # shellcheck disable=SC1090
  . "$_mb_lib"
done

SUBCMD="${1:-}"
[ "$#" -gt 0 ] && shift
TASK_ARG="" ASK_ARG="" LEG_ARG="" TRANSPORT_ARG="" RESULT_ARG="" STATE_PATH="" RENDER_ONLY=0
MAX_SECONDS_ARG=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --render-only)
      RENDER_ONLY=1
      shift
      continue
      ;;
  esac
  [ "$#" -ge 2 ] || die 2 "missing value for $1"
  case "$1" in
    --task-id) TASK_ARG="$2" ;;
    --ask-id) ASK_ARG="$2" ;;
    --leg) LEG_ARG="$2" ;;
    --transport) TRANSPORT_ARG="$2" ;;
    --result) RESULT_ARG="$2" ;;
    --state) STATE_PATH="$2" ;;
    --max-seconds) MAX_SECONDS_ARG="$2" ;;
    *) die 2 "unknown flag: $1" ;;
  esac
  shift 2
done

is_task_id() {
  [[ "${1:-}" =~ ^(PL|AR|TL|DV|DR|SR|QA|DC|RE|FN|ST|IR|ET)[0-9]+$ ]]
}

resolve_state() {
  local ctx rc=0
  if [ -z "$STATE_PATH" ]; then
    ctx=$(corpflow_context_dir) || rc=$?
    [ "$rc" -eq 0 ] || die 2 "no .context/ resolved; pass --state"
    STATE_PATH="$ctx/state.json"
  fi
  [ -f "$STATE_PATH" ] || die 2 "no ledger at $STATE_PATH"
  jq -e 'type == "object"' "$STATE_PATH" > /dev/null 2>&1 || die 2 "unparseable ledger at $STATE_PATH"
  AUDIT="${STATE_PATH%/*}/logs/audit.jsonl"
}

# mb_open_ledger_json — every task blocked on a native peer_session need with a
# grammar-valid ask_id, as {task_id, ask_id}. The mailbox directory is never scanned.
mb_open_ledger_json() {
  jq -c '[(.tasks // {}) | to_entries[]
    | select(.value.status == "blocked" and (.value.metadata.blocked_on.kind? // "") == "peer_session")
    | {task_id: .key, ask_id: (.value.metadata.ask_id? // "")}
    | select(.ask_id | test("^ask-[0-9]{8}t[0-9]{6}z-[0-9a-f]{12}$"))]' "$STATE_PATH"
}

# mb_task_ask_id <task> — the open ask.s id for one task, or rc 1.
mb_task_ask_id() {
  local task="$1" ask
  ask=$(jq -r --arg t "$task" '
    (.tasks[$t]? // empty)
    | select(.status == "blocked" and (.metadata.blocked_on.kind? // "") == "peer_session")
    | (.metadata.ask_id? // empty)' "$STATE_PATH" 2> /dev/null) || ask=""
  [ -n "$ask" ] || return 1
  mb_valid_ask_id "$ask" || return 1
  printf '%s' "$ask"
}

# mb_no_gh_issue [task] — checked textually and logically before mb_resolve_issue
# is ever called on any path through this file.
mb_no_gh_issue() {
  local task="${1:-}" v
  case "${NO_GH_ISSUE:-}" in
    1 | true | TRUE | True | yes) return 0 ;;
  esac
  v=$(jq -r '.metadata.no_gh_issue // empty' "$STATE_PATH" 2> /dev/null) || v=""
  [ "$v" = "true" ] && return 0
  if [ -n "$task" ]; then
    v=$(jq -r --arg t "$task" '.tasks[$t].metadata.no_gh_issue // empty' "$STATE_PATH" 2> /dev/null) || v=""
    [ "$v" = "true" ] && return 0
  fi
  local ri
  ri=$(corpflow_run_index "$STATE_PATH")
  v=$(jq -r --arg t "PL$ri" '.tasks[$t].metadata.no_gh_issue // empty' "$STATE_PATH" 2> /dev/null) || v=""
  [ "$v" = "true" ] && return 0
  return 1
}

# mb_resolve_issue — PL<ri>'s issue_number, then the run's github_issue_url, then
# the run context's gh-issue.json anchor; rc 1 when none resolves to a bare positive integer.
mb_resolve_issue() {
  local ri n url anchor
  ri=$(corpflow_run_index "$STATE_PATH")
  n=$(jq -r --arg t "PL$ri" '.tasks[$t].metadata.issue_number // empty' "$STATE_PATH" 2> /dev/null) || n=""
  if [[ ! "$n" =~ ^[1-9][0-9]{0,9}$ ]]; then
    url=$(jq -r '.metadata.github_issue_url // empty' "$STATE_PATH" 2> /dev/null) || url=""
    if [[ "$url" =~ ^https://github\.com/[^/]+/[^/]+/issues/([0-9]+)$ ]]; then
      n="${BASH_REMATCH[1]}"
    else
      n=""
    fi
  fi
  if [[ ! "$n" =~ ^[1-9][0-9]{0,9}$ ]]; then
    anchor="${STATE_PATH%/*}/gh-issue.json"
    if [ -r "$anchor" ]; then
      n=$(jq -r '.number // empty' "$anchor" 2> /dev/null) || n=""
    fi
  fi
  [[ "$n" =~ ^[1-9][0-9]{0,9}$ ]] || return 1
  printf '%s' "$n"
}

# mb_leg_row <task> <leg> <ask_id> [transport] [transport_result] [answered_by_kind] — dedupe
# through mb_leg_recorded, then one blocked_on audit row. Always rc 0 (an audit row is evidence,
# never a gate — same contract as corpflow_audit_row).
mb_leg_row() {
  local task="$1" leg="$2" ask="$3" transport="${4:-}" tresult="${5:-}" abk="${6:-}" meta
  mb_leg_recorded "$AUDIT" "$task" "$ask" "$leg" && return 0
  meta=$(mb_leg_meta "$leg" "$ask" "$transport" "$tresult" "$abk")
  corpflow_audit_row --file "$AUDIT" --actor orchestrator --action blocked_on --result blocked \
    --subject "$task" --task-id "$task" --meta "$meta"
  return 0
}

# --- show --------------------------------------------------------------------------
cmd_show() {
  mb_valid_ask_id "$ASK_ARG" || die 1 "invalid --ask-id"
  local req
  req=$(mb_read_request "$ASK_ARG") || die 1 "no such ask: $ASK_ARG"
  printf '%s\n' "$req"
}

# --- leg (message transport only; comment writes its own) --------------------------
cmd_leg() {
  is_task_id "$TASK_ARG" || die 2 "leg needs --task-id <STAGE><N>"
  mb_valid_ask_id "$ASK_ARG" || die 1 "invalid --ask-id"
  case "$LEG_ARG" in
    sent | delivered) ;;
    *) die 2 "leg needs --leg sent|delivered" ;;
  esac
  [ "$TRANSPORT_ARG" = "message" ] || die 2 "leg needs --transport message"
  if [ "$LEG_ARG" = delivered ]; then
    case "$RESULT_ARG" in
      ok | queued | refused | dropped | oversized | burst_limited) ;;
      *) die 2 "delivered needs --result ok|queued|refused|dropped|oversized|burst_limited" ;;
    esac
  fi
  resolve_state
  local open_ask=""
  open_ask=$(mb_task_ask_id "$TASK_ARG" 2> /dev/null) || true
  [ "$open_ask" = "$ASK_ARG" ] || die 1 "tasks.$TASK_ARG is not an open peer_session ask for $ASK_ARG"
  local before written=false
  before=$(_rows_leg "$TASK_ARG" "$ASK_ARG" "$LEG_ARG")
  mb_leg_row "$TASK_ARG" "$LEG_ARG" "$ASK_ARG" message "$RESULT_ARG"
  [ "$before" -eq 0 ] && written=true
  jq -cn --argjson w "$written" '{written: $w}'
}

# mb_posted_ask <task> <ask_id> — 0 when this ask's comment reached the issue. A reply comment can
# only exist for one of these, so it gates the ingest poll.
mb_posted_ask() {
  [ -f "$AUDIT" ] || return 1
  jq -nRe --arg t "$1" --arg a "$2" '
    [inputs | fromjson? | select(type == "object" and .action == "blocked_on" and .subject == $t
      and (.metadata.ask_id? // "") == $a and .metadata.leg == "delivered"
      and (.metadata.transport_result? // "") == "posted")] | length > 0' "$AUDIT" > /dev/null 2>&1
}

_rows_leg() {
  [ -f "$AUDIT" ] || { echo 0; return 0; }
  jq -nR --arg t "$1" --arg a "$2" --arg l "$3" \
    '[inputs | fromjson? | select(.action == "blocked_on" and .subject == $t
      and (.metadata.ask_id? // "") == $a and .metadata.leg == $l)] | length' "$AUDIT"
}

# --- comment (opt-out, resolve issue, render, post) ---------------------
cmd_comment() {
  is_task_id "$TASK_ARG" || die 2 "comment needs --task-id <STAGE><N>"
  resolve_state
  local ask_id
  ask_id=$(mb_task_ask_id "$TASK_ARG") || die 1 "tasks.$TASK_ARG is not an open peer_session ask"

  # One send per ask, whatever its result: a sent leg means the question is already published, and
  # a second comment would ask a peer the same question twice. A failed send waits for the
  # deadline instead. --render-only carries no send, so it is never gated here.
  if [ "$RENDER_ONLY" -eq 0 ] && mb_leg_recorded "$AUDIT" "$TASK_ARG" "$ask_id" sent; then
    jq -cn '{posted: false, result: "already_sent"}'
    return 0
  fi

  # Opt-out first: before any issue lookup, textually and logically.
  if mb_no_gh_issue "$TASK_ARG"; then
    [ "$RENDER_ONLY" -eq 1 ] && die 1 "opted_out"
    mb_leg_row "$TASK_ARG" delivered "$ask_id" comment opted_out
    jq -cn '{posted: false, result: "opted_out"}'
    return 0
  fi

  # Resolve the issue.
  local issue=""
  issue=$(mb_resolve_issue) || issue=""
  if [ -z "$issue" ]; then
    [ "$RENDER_ONLY" -eq 1 ] && die 1 "unavailable"
    mb_leg_row "$TASK_ARG" delivered "$ask_id" comment unavailable
    jq -cn '{posted: false, result: "unavailable"}'
    return 0
  fi

  # Render: sanitiser and scrub in one subshell (a missing scrub library
  # must not kill this script, only fail this ask's post).
  local req question body_ok=0 rendered=""
  req=$(mb_read_request "$ask_id") || die 1 "request unreadable for $ask_id"
  question=$(printf '%s' "$req" | jq -r '.question')
  rendered=$(
    (
      set -o pipefail
      [ -r "$_MB_PATH_SCRUB" ] || exit 1
      [ -r "$_MB_PUBLISH_LIB" ] || exit 1
      # shellcheck disable=SC1090
      . "$_MB_PATH_SCRUB" || exit 1
      # shellcheck disable=SC1090
      PUBLISH_LIB_ONLY=1 . "$_MB_PUBLISH_LIB" || exit 1
      command -v sanitise_body > /dev/null 2>&1 || exit 1
      command -v corpflow_path_scrub > /dev/null 2>&1 || exit 1
      q=$(printf '%s' "$question" | jq -Rs "$PD_JQ_DEFS"'pd_bound(512)' 2> /dev/null) || exit 1
      q=$(printf '%s' "$q" | jq -r '.' 2> /dev/null) || exit 1
      q=$(printf '%s\n' "$q" | sanitise_body) || exit 1
      [ -n "$q" ] || exit 1
      body=$(printf '%s\n\n%s' "$ask_id" "$q")
      scrubbed=$(printf '%s' "$body" | corpflow_path_scrub) || exit 1
      [ "$scrubbed" = "$body" ] || exit 1
      printf '%s' "$body"
    )
  ) && body_ok=1
  if [ "$body_ok" -ne 1 ] || [ -z "$rendered" ]; then
    [ "$RENDER_ONLY" -eq 1 ] && die 1 "scrub_failed"
    mb_leg_row "$TASK_ARG" delivered "$ask_id" comment scrub_failed
    jq -cn '{posted: false, result: "scrub_failed"}'
    return 0
  fi
  if [ "$RENDER_ONLY" -eq 1 ]; then
    jq -cn --arg b "$rendered" '{body: $b}'
    return 0
  fi

  # Post.
  mb_leg_row "$TASK_ARG" sent "$ask_id" comment
  local tmp
  tmp=$(mktemp 2> /dev/null) || {
    mb_leg_row "$TASK_ARG" delivered "$ask_id" comment post_failed
    jq -cn '{posted: false, result: "post_failed"}'
    return 0
  }
  chmod 600 "$tmp" 2> /dev/null || true
  printf '%s' "$rendered" > "$tmp"
  if "$GH_BIN" issue comment "$issue" --body-file "$tmp" > /dev/null 2>&1; then
    rm -f -- "$tmp"
    mb_leg_row "$TASK_ARG" delivered "$ask_id" comment posted
    jq -cn '{posted: true, result: "posted"}'
  else
    rm -f -- "$tmp"
    mb_leg_row "$TASK_ARG" delivered "$ask_id" comment post_failed
    jq -cn '{posted: false, result: "post_failed"}'
  fi
}

# --- ingest-comments (author filter, answer-file pipe, audit row) -------------------------
# shellcheck disable=SC2016  # jq program text: its $names are jq variables, not shell ones
_MB_INGEST_JQ='def mb_first_line: (. // "") | gsub("\r\n"; "\n") | split("\n")[0] | sub("[ \t]+$"; "");'

mb_reply_answer() {
  jq -Rsr '
    gsub("\r\n"; "\n") | split("\n") | .[1:] as $rest
    | (reduce range(0; ($rest | length)) as $i
        (null; if . == null and (($rest[$i] // "") | length) > 0 then $i else . end)) as $start
    | if $start == null then "" else ($rest[$start:] | join("\n")) end'
}

cmd_ingest() {
  resolve_state
  local open_json count ingested=0 ignored_total=0
  open_json=$(mb_open_ledger_json)
  count=$(printf '%s' "$open_json" | jq 'length')
  if [ "$count" -eq 0 ]; then
    jq -cn '{ingested: 0, ignored: 0}'
    return 0
  fi
  if mb_no_gh_issue; then
    jq -cn '{ingested: 0, ignored: 0}'
    return 0
  fi
  local n
  n=$(mb_resolve_issue) || {
    jq -cn '{ingested: 0, ignored: 0}'
    return 0
  }

  # Eligibility first, and per task: an ask is answerable on the issue only if its own task did not
  # opt out of GitHub and its comment actually reached the issue. Without both checks a collaborator
  # could answer a question addressed to a different peer, over a channel this run declined.
  local eligible='[]' row
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    local task ask req
    task=$(printf '%s' "$row" | jq -r '.task_id')
    ask=$(printf '%s' "$row" | jq -r '.ask_id')
    mb_no_gh_issue "$task" && continue
    mb_posted_ask "$task" "$ask" || continue
    req=$(mb_read_request "$ask" 2> /dev/null) || continue
    eligible=$(printf '%s' "$eligible" | jq -c --arg t "$task" --arg a "$ask" \
      --arg ca "$(printf '%s' "$req" | jq -r '.created_at')" \
      '. + [{task_id: $t, ask_id: $a, created_at: $ca}]')
  done <<< "$(printf '%s' "$open_json" | jq -c '.[]')"
  if [ "$(printf '%s' "$eligible" | jq 'length')" -eq 0 ]; then
    jq -cn '{ingested: 0, ignored: 0}'
    return 0
  fi

  # `since` is the earliest open ask's creation time, so the fetch never walks the issue's whole
  # history — it also subsumes the per-comment stale check for everything before that point.
  # jq -s, not gh's --slurp: --paginate concatenates one array per page and gh only learned
  # --slurp in 2.42, where an older gh would silently hand back page 1 alone.
  local since comments max_comments="${MAILBOX_INGEST_MAX:-500}"
  case "$max_comments" in '' | *[!0-9]*) max_comments=500 ;; esac
  since=$(printf '%s' "$eligible" | jq -r 'map(.created_at) | sort | .[0]')
  comments=$("$GH_BIN" api \
    "repos/{owner}/{repo}/issues/$n/comments?since=$since&per_page=100" --paginate 2> /dev/null \
    | jq -s -c --argjson cap "$max_comments" \
      '[.[] | if type == "array" then .[] else empty end] | .[:$cap]' 2> /dev/null) || comments="[]"
  printf '%s' "$comments" | jq -e 'type == "array"' > /dev/null 2>&1 || comments="[]"

  # One normalisation pass for the whole batch: the per-ask loop below then costs one jq call per
  # ask rather than a handful per comment per ask, which `wait` would otherwise pay every minute.
  local normalised
  normalised=$(printf '%s' "$comments" | jq -c "$_MB_INGEST_JQ"'
    [.[] | {first: (.body | mb_first_line), body: (.body // ""),
            author: (.author_association // ""), btype: (.user.type // ""),
            login: (.user.login // ""), ctime: (.created_at // "")}]
    | sort_by(.ctime)' 2> /dev/null) || normalised='[]'

  while IFS= read -r row; do
    [ -n "$row" ] || continue
    local task ask created_at task_ignored=0 task_reasons='[]' done_task=0
    task=$(printf '%s' "$row" | jq -r '.task_id')
    ask=$(printf '%s' "$row" | jq -r '.ask_id')
    created_at=$(printf '%s' "$row" | jq -r '.created_at')

    local candidates cand
    candidates=$(printf '%s' "$normalised" | jq -c --arg ask "reply $ask" --arg ca "$created_at" '
      [.[] | select(.first == $ask)
       | {login, body,
          reason: (if ((.author == "OWNER") or (.author == "MEMBER") or (.author == "COLLABORATOR") | not) then "author"
                   elif .btype == "Bot" then "bot"
                   elif (.login | test("^[A-Za-z0-9][A-Za-z0-9-]{0,38}$") | not) then "author"
                   elif .ctime < $ca then "stale"
                   else "" end)}]')

    while IFS= read -r cand; do
      [ -n "$cand" ] || continue
      local reason login body
      reason=$(printf '%s' "$cand" | jq -r '.reason')
      login=$(printf '%s' "$cand" | jq -r '.login')
      [ "$done_task" -eq 0 ] || reason=duplicate
      if [ -n "$reason" ]; then
        task_ignored=$((task_ignored + 1))
        task_reasons=$(printf '%s' "$task_reasons" | jq -c --arg r "$reason" '. + [$r]')
        continue
      fi

      local answer out rc=0
      body=$(printf '%s' "$cand" | jq -r '.body')
      answer=$(printf '%s' "$body" | mb_reply_answer)
      out=$(printf '%s' "$answer" \
        | bash "$_MB_REPLY" --ask-id "$ask" --answer-file - --kind peer --session "gh:$login" 2>&1) || rc=$?
      if [ "$rc" -eq 0 ]; then
        ingested=$((ingested + 1))
        done_task=1
        continue
      fi
      local frc=""
      frc=$(printf '%s' "$out" | sed -n 's/^fail: \([a-z_]*\):.*/\1/p' | head -n 1)
      case "$frc" in
        late) reason=late ;;
        schema_invalid | too_long) reason=schema ;;
        duplicate)
          reason=duplicate
          done_task=1
          ;;
        *) reason="" ;;
      esac
      if [ -n "$reason" ]; then
        task_ignored=$((task_ignored + 1))
        task_reasons=$(printf '%s' "$task_reasons" | jq -c --arg r "$reason" '. + [$r]')
      fi
    done <<< "$(printf '%s' "$candidates" | jq -c '.[]')"
    if [ "$task_ignored" -gt 0 ]; then
      ignored_total=$((ignored_total + task_ignored))
      corpflow_audit_row --file "$AUDIT" --actor orchestrator --action mailbox_ingest --result ok \
        --subject "$task" --task-id "$task" \
        --meta "$(jq -cn --arg id "$ask" --argjson cnt "$task_ignored" --argjson r "$task_reasons" \
          '{ask_id: $id, ignored: $cnt, reasons: $r}')"
    fi
  done <<< "$(printf '%s' "$eligible" | jq -c '.[]')"

  jq -cn --argjson i "$ingested" --argjson g "$ignored_total" '{ingested: $i, ignored: $g}'
}

# --- scan (ledger scan; writes the answered leg once) --------------------------
cmd_scan() {
  resolve_state
  local open_json replied='[]' open_out='[]' row
  open_json=$(mb_open_ledger_json)
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    local task ask
    task=$(printf '%s' "$row" | jq -r '.task_id')
    ask=$(printf '%s' "$row" | jq -r '.ask_id')
    local reply
    if reply=$(mb_verified_reply "$ask" 2> /dev/null); then
      local kind
      kind=$(printf '%s' "$reply" | jq -r '.answered_by.kind')
      mb_leg_row "$task" answered "$ask" "" "" "$kind"
      replied=$(printf '%s' "$replied" | jq -c --arg t "$task" --arg a "$ask" '. + [{task_id: $t, ask_id: $a}]')
    else
      local req deadline=""
      req=$(mb_read_request "$ask" 2> /dev/null) && deadline=$(printf '%s' "$req" | jq -r '.deadline')
      open_out=$(printf '%s' "$open_out" | jq -c --arg t "$task" --arg a "$ask" --arg d "$deadline" \
        '. + [{task_id: $t, ask_id: $a, deadline: $d}]')
    fi
  done <<< "$(printf '%s' "$open_json" | jq -c '.[]')"
  jq -cn --argjson r "$replied" --argjson o "$open_out" '{replied: $r, open: $o}'
}

# --- sweep (expiry; routes through the router's own user_decision fallback) --
cmd_sweep() {
  resolve_state
  local open_json now expired='[]' row
  open_json=$(mb_open_ledger_json)
  now=$(mb_now)
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    local task ask
    task=$(printf '%s' "$row" | jq -r '.task_id')
    ask=$(printf '%s' "$row" | jq -r '.ask_id')
    if mb_verified_reply "$ask" > /dev/null 2>&1; then continue; fi
    local req question options='[]' deadline_epoch="" grace=5
    if req=$(mb_read_request "$ask" 2> /dev/null); then
      local dl
      dl=$(printf '%s' "$req" | jq -r '.deadline')
      deadline_epoch=$(jq -rn --arg d "$dl" "$MB_JQ_DEFS"'($d | mb_epoch) // empty' 2> /dev/null) || deadline_epoch=""
      question=$(printf '%s' "$req" | jq -r '.question')
      options=$(printf '%s' "$req" | jq -c '.options // []')
    else
      # No readable request: the file that held the deadline and the reply_schema is gone, so
      # nothing can still arrive on this ask. The ledger keeps the question, and the ask expires
      # at once rather than parking the task forever on a record that no longer exists.
      question=$(jq -r --arg t "$task" '.tasks[$t].metadata.blocked_on.detail.question // ""' "$STATE_PATH")
      local led_dl
      led_dl=$(jq -r --arg t "$task" '.tasks[$t].metadata.blocked_on.detail.deadline // ""' "$STATE_PATH")
      deadline_epoch=$(jq -rn --arg d "$led_dl" "$MB_JQ_DEFS"'($d | mb_epoch) // empty' 2> /dev/null) || deadline_epoch=""
      if [ -z "$deadline_epoch" ]; then
        deadline_epoch="$now"
        grace=0
      else
        # The ledger holds the stage's raw value, which request creation would have clamped. Without
        # the same cap here, a stage naming a far deadline parks its task past the one-day bound.
        [ "$deadline_epoch" -le "$((now + 86400))" ] || deadline_epoch=$((now + 86400))
      fi
    fi
    [ -n "$deadline_epoch" ] || continue
    [ "$now" -ge "$((deadline_epoch + grace))" ] || continue

    mb_leg_row "$task" expired "$ask"
    local payload routed=false
    payload=$(jq -cn --arg q "$question" --argjson o "$options" \
      '{verdict: "blocked", blocked_on: {kind: "user_decision",
        detail: {question: $q, options: $o}, resume_with: "decision_ref"}}')
    if bash "$_MB_DISPATCH" route --task-id "$task" --payload "$payload" --state "$STATE_PATH" > /dev/null 2>&1; then
      routed=true
    else
      # A refused route leaves the need on peer_session with a valid ask_id, which `batch` skips —
      # the ask would reach no terminal state and nobody would be asked. Dropping the id puts the
      # need back in front of the user at the next boundary, whatever refused the route.
      bash "$_MB_STATE_PATCH" --state "$STATE_PATH" --log /dev/null \
        --task-meta "$task" --set '{"ask_id":null}' > /dev/null 2>&1 || true
    fi
    expired=$(printf '%s' "$expired" | jq -c --arg t "$task" --arg a "$ask" --argjson r "$routed" \
      '. + [{task_id: $t, ask_id: $a, routed: $r}]')
  done <<< "$(printf '%s' "$open_json" | jq -c '.[]')"
  jq -cn --argjson e "$expired" '{expired: $e}'
}

# --- wait (loop-boundary fallback poll; never required) -----------
cmd_wait() {
  resolve_state
  local max="${MAX_SECONDS_ARG:-3600}" poll="${MAILBOX_POLL_SECONDS:-15}"
  case "$max" in '' | *[!0-9]*) max=3600 ;; esac
  # A floor of 1, not just a digit check: MAILBOX_POLL_SECONDS=0 would turn this into a spin loop
  # burning a core until the deadline.
  case "$poll" in '' | *[!0-9]*) poll=15 ;; esac
  [ "$poll" -ge 1 ] || poll=1
  local start last_ingest
  start=$(mb_now)
  last_ingest=0
  while :; do
    local now open_json count min_deadline=""
    now=$(mb_now)
    open_json=$(mb_open_ledger_json)
    count=$(printf '%s' "$open_json" | jq 'length')
    if [ "$count" -eq 0 ]; then
      jq -cn '{reason: "none"}'
      return 0
    fi
    local row posted_open=0
    while IFS= read -r row; do
      [ -n "$row" ] || continue
      local task ask
      task=$(printf '%s' "$row" | jq -r '.task_id')
      ask=$(printf '%s' "$row" | jq -r '.ask_id')
      if mb_verified_reply "$ask" > /dev/null 2>&1; then
        jq -cn '{reason: "reply"}'
        return 0
      fi
      mb_posted_ask "$task" "$ask" && posted_open=1
      local req dl de
      if req=$(mb_read_request "$ask" 2> /dev/null); then
        dl=$(printf '%s' "$req" | jq -r '.deadline')
        de=$(jq -rn --arg d "$dl" "$MB_JQ_DEFS"'($d | mb_epoch) // empty' 2> /dev/null) || de=""
        if [ -n "$de" ] && { [ -z "$min_deadline" ] || [ "$de" -lt "$min_deadline" ]; }; then
          min_deadline="$de"
        fi
      fi
    done <<< "$(printf '%s' "$open_json" | jq -c '.[]')"

    if [ -n "$min_deadline" ] && [ "$now" -ge "$((min_deadline + 5))" ]; then
      jq -cn '{reason: "deadline"}'
      return 0
    fi
    if [ "$((now - start))" -ge "$max" ]; then
      jq -cn '{reason: "timeout"}'
      return 0
    fi
    # Only a comment that was actually posted can be answered on the issue. Polling for a
    # message-transport ask would spend a GitHub API call a minute reading an issue nobody was
    # asked on.
    if [ "$posted_open" -eq 1 ] && [ "$((now - last_ingest))" -ge 60 ]; then
      cmd_ingest > /dev/null 2>&1 || true
      last_ingest=$now
    fi
    sleep "$poll" 2> /dev/null || break
  done
  jq -cn '{reason: "timeout"}'
}

case "$SUBCMD" in
  show) cmd_show ;;
  leg) cmd_leg ;;
  comment) cmd_comment ;;
  ingest-comments) cmd_ingest ;;
  scan) cmd_scan ;;
  sweep) cmd_sweep ;;
  wait) cmd_wait ;;
  -h | --help | "") usage ;;
  *) die 2 "unknown subcommand: $SUBCMD" ;;
esac
