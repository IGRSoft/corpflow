#!/usr/bin/env bash
# @description ack-check.sh — read-only delivery check for orchestrator messages to a stage.
#
#   A `reattach_send_result` row of `ok` proves the harness accepted a message, not that the
#   stage read it. Delivery is proven only by the `message_ack` row the stage writes itself
#   (`state-patch.sh --ack <ID> <msg_id>`). This joins the two per msg_id and, given the
#   stage artifact, compares `handoff.acted_on_msg_id` with the newest acknowledged message
#   no later send superseded, so the instruction a stage followed is read from evidence
#   rather than inferred from message order.
#
#   STRICTLY READ-ONLY: writes no ledger, audit row or log.
#
#   Send rows without a metadata.msg_id predate message ids and are ignored rather than
#   reported unacked. A torn audit line is skipped, never fatal.
#
#   A fix round re-dispatches the same task key with run_index bumped, so --run-index scopes
#   the check to one dispatch: send rows whose metadata.run_index differs are ignored, and a
#   send row with no run_index counts as run 0. Acks carry no run_index and still join by
#   msg_id, which is unique per key across runs; an ack whose msg_id was sent in another run
#   is dropped, not listed as an orphan. Without the flag every run is in scope.
#
# @arg --task <ID>        Ledger key whose messages are checked (<STAGE><N>, e.g. DV0).
# @arg --run-index <N>    Only sends of dispatch N (non-negative integer) count; missing = 0.
# @arg --context <dir>    .context dir (default: .context).
# @arg --audit <path>     Audit log (default: <context>/logs/audit.jsonl). Absent = no sends.
# @arg --artifact <path>  Stage artifact carrying handoff.acted_on_msg_id. Omitted: delivery
#                         only, and no acted_on line.
# @arg --self-test        Run the built-in scenarios and exit.
# @arg -h | --help        Show this header.
#
# Output, one token-led line each:
#   msg <msg_id> <acked|superseded|not-delivered> send=<result|none>
#   orphan-ack <msg_id>                                     ack with no send row; informational
#   acted_on <value|missing> expected=<msg_id|none> <match|mismatch>        --artifact only
#   verdict: <clear|not-delivered|mismatch>
#
# @exitcode 0  Clear: every msg_id-bearing send is acked or superseded and acted_on matches
#              (no sends and no acted_on is clear too).
# @exitcode 1  At least one message not delivered. Wins over a mismatch, even when the
#              artifact names that very msg_id.
# @exitcode 2  Usage or unreadable input: bad or missing --task, a malformed --run-index, a
#              flag without its value, jq absent, an unreadable audit log, a send row with a
#              malformed msg_id (or, under --run-index, a malformed run_index), an artifact
#              that is unreadable or carries no handoff: block.
# @exitcode 3  Every message delivered, but acted_on is missing, differs from expected, or
#              is set while nothing was acknowledged.
#
# Minimum shell: bash 3.2+ (macOS default); needs jq.

set -Eeuo pipefail
IFS=$'\n\t'
trap 'printf >&2 "error: %s:%d: exit %d\n" "${BASH_SOURCE[0]}" "$LINENO" "$?"' ERR

readonly TASK_ID_RE='^(PL|AR|TL|DV|DR|SR|QA|DC|RE|FN|ST|IR|ET)[0-9]+$'

CONTEXT_DIR=".context"
AUDIT_PATH=""
TASK_ID=""
RUN_INDEX=""
ARTIFACT=""
ACTED_ON=""
WORK_DIR=""
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cleanup() {
  if [ -n "$WORK_DIR" ]; then rm -rf -- "$WORK_DIR"; fi
}
trap cleanup EXIT

usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$SELF"; }

# Exit 1 and 3 are findings the orchestrator acts on, so every input problem must land on 2.
die_usage() {
  printf 'ack-check: %s\n' "$1" >&2
  exit 2
}

need_value() { # <flag> [candidate]
  case "${2:-}" in
    '' | --*) die_usage "$1 needs a value" ;;
  esac
}

work_dir() {
  if [ -z "$WORK_DIR" ]; then
    WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ack-check.XXXXXX")"
  fi
}

# \A and \z, not ^ and $: Oniguruma's $ also matches before a trailing newline, which would
# let a msg_id smuggle a second output line past the grammar.
# shellcheck disable=SC2016  # jq program text; $vars are jq's, not the shell's
readonly JQ_JOIN='
  def meta(k): if (.metadata | type) == "object" then .metadata[k] else null end;
  def mid: meta("msg_id") // .msg_id;
  def valid: type == "string" and test("\\A[A-Za-z0-9_][A-Za-z0-9._:@/-]{0,199}\\z");
  def safe: tostring | gsub("[^A-Za-z0-9._:@/-]"; "_");
  def push($x): if any(.[]; . == $x) then . else . + [$x] end;
  def run: meta("run_index")
    | if . == null then 0
      elif type == "number" and . >= 0 and . == floor then .
      elif type == "string" and test("\\A[0-9]{1,9}\\z") then tonumber
      else error("send row with a malformed run_index") end;

  [inputs | (fromjson? // empty) | objects
    | select(((.task_id // .subject) | tostring) == $id)] as $rows
  | [$rows[] | select(.action == "reattach_send_result" and (mid != null))] as $every
  | if any($every[]; mid | valid | not) then error("send row with a malformed msg_id") else . end
  | [$every[] | select($run == null or run == $run)] as $sends
  | [$rows[] | select(.action == "message_ack") | mid | select(valid)] as $acks
  | [$sends[] | meta("supersedes") | select(type == "string")] as $superseded
  | (reduce ($sends[] | mid) as $m ([]; push($m))) as $order
  | [$order[] as $m
      | {m: $m,
         send: ([$sends[] | select(mid == $m)] | last | (.result // "none") | safe),
         state: (if any($superseded[]; . == $m) then "superseded"
                 elif any($acks[]; . == $m) then "acked"
                 else "not-delivered" end)}] as $msgs
  | (reduce ($acks[] | select(. as $a | any($every[]; mid == $a) | not)) as $a ([]; push($a)))
    as $orphans
  | {lines: ([$msgs[] | "msg \(.m) \(.state) send=\(.send)"]
             + [$orphans[] | "orphan-ack \(.)"]),
     expected: ([$msgs[] | select(.state == "acked") | .m] | last // "none"),
     undelivered: ([$msgs[] | select(.state == "not-delivered")] | length)}
'

read_acted_on() {
  local fm
  if ! { [ -f "$ARTIFACT" ] && [ -r "$ARTIFACT" ]; }; then
    die_usage "artifact not readable: $ARTIFACT"
  fi
  if [ ! -r "$LIB_DIR/frontmatter-lib.sh" ]; then
    die_usage "frontmatter-lib.sh unreachable at $LIB_DIR"
  fi
  # shellcheck source=frontmatter-lib.sh
  . "$LIB_DIR/frontmatter-lib.sh"
  work_dir
  fm="$WORK_DIR/frontmatter.yaml"
  if ! corpflow_fm_block "$ARTIFACT" > "$fm" || ! corpflow_fm_has_handoff "$fm"; then
    die_usage "artifact has no handoff: block: $ARTIFACT"
  fi
  ACTED_ON="$(corpflow_fm_field "$fm" acted_on_msg_id "")"
}

run_check() {
  local summary expected undelivered shown state verdict="clear" rc=0 run_json="null"

  [[ "$TASK_ID" =~ $TASK_ID_RE ]] || die_usage "--task needs <STAGE><N> (e.g. DV0), got: ${TASK_ID:-nothing}"
  if [ -n "$RUN_INDEX" ]; then
    # Nine digits keep the value an exact integer in jq; 10# strips leading zeros.
    [[ "$RUN_INDEX" =~ ^[0-9]{1,9}$ ]] \
      || die_usage "--run-index needs a non-negative integer, got: ${RUN_INDEX//[^A-Za-z0-9._-]/_}"
    run_json="$((10#$RUN_INDEX))"
  fi
  command -v jq > /dev/null 2>&1 || die_usage "jq is required"
  [ -n "$AUDIT_PATH" ] || AUDIT_PATH="${CONTEXT_DIR%/}/logs/audit.jsonl"
  # Parsed before any output so an unreadable artifact never follows a printed partial report.
  if [ -n "$ARTIFACT" ]; then read_acted_on; fi

  if [ -e "$AUDIT_PATH" ]; then
    if ! { [ -f "$AUDIT_PATH" ] && [ -r "$AUDIT_PATH" ]; }; then
      die_usage "audit log not readable: $AUDIT_PATH"
    fi
    # `|| exit 1` inside the substitution keeps the errtrace-inherited ERR trap quiet there.
    summary="$(jq -cnR --arg id "$TASK_ID" --argjson run "$run_json" "$JQ_JOIN" \
      < "$AUDIT_PATH" 2> /dev/null || exit 1)" \
      || die_usage "audit log unusable (malformed msg_id or run_index on a send row?): $AUDIT_PATH"
  else
    summary='{"lines":[],"expected":"none","undelivered":0}'
  fi

  jq -r '.lines[]' <<< "$summary"
  expected="$(jq -r '.expected' <<< "$summary")"
  undelivered="$(jq -r '.undelivered' <<< "$summary")"

  if [ "$undelivered" -gt 0 ]; then
    verdict="not-delivered"
    rc=1
  fi

  if [ -n "$ARTIFACT" ]; then
    if [ -z "$ACTED_ON" ]; then
      [ "$expected" = "none" ] && state="match" || state="mismatch"
    elif [ "$expected" = "none" ]; then
      state="mismatch"
    else
      [ "$ACTED_ON" = "$expected" ] && state="match" || state="mismatch"
    fi
    shown="${ACTED_ON//[^A-Za-z0-9._:@\/-]/_}"
    printf 'acted_on %s expected=%s %s\n' "${shown:-missing}" "$expected" "$state"
    if [ "$state" = "mismatch" ] && [ "$rc" -eq 0 ]; then
      verdict="mismatch"
      rc=3
    fi
  fi

  printf 'verdict: %s\n' "$verdict"
  return "$rc"
}

_st_case() { # <name> <want-rc> <args...>
  local name="$1" want="$2" rc=0
  shift 2
  bash "$SELF" --task DV0 "$@" > /dev/null 2>&1 || rc=$?
  if [ "$rc" -eq "$want" ]; then
    printf 'self-test: %s exits %s: ok\n' "$name" "$want"
  else
    printf 'self-test: %s exited %s, want %s: FAIL\n' "$name" "$rc" "$want" >&2
    exit 1
  fi
}

_st_artifact() { # <path> [acted_on_msg_id]  empty: the field is absent
  if [ -n "${2:-}" ]; then
    printf -- '---\nhandoff:\n  stage: DV\n  verdict: ok\n  acted_on_msg_id: %s\n---\n\n# Development\n' \
      "$2" > "$1"
  else
    printf -- '---\nhandoff:\n  stage: DV\n  verdict: ok\n---\n\n# Development\n' > "$1"
  fi
}

self_test() {
  local td send1 send2 ack2 ack1
  work_dir
  td="$WORK_DIR"
  send1='{"action":"reattach_send_result","subject":"DV0","result":"ok","task_id":"DV0","metadata":{"msg_id":"DV0-m1"}}'
  send2='{"action":"reattach_send_result","subject":"DV0","result":"ok","task_id":"DV0","metadata":{"msg_id":"DV0-m2","supersedes":"DV0-m1"}}'
  ack2='{"action":"message_ack","subject":"DV0","result":"ok","task_id":"DV0","metadata":{"msg_id":"DV0-m2"}}'
  printf '%s\n' "$send1" "$send2" "$ack2" > "$td/supersede.jsonl"
  printf '%s\n' "$send1" > "$td/unacked.jsonl"
  printf '%s\n' '{"action":"reattach_send_result","subject":"DV0","result":"ok","task_id":"DV0","metadata":{}}' \
    > "$td/legacy.jsonl"
  ack1='{"action":"message_ack","subject":"DV0","result":"ok","task_id":"DV0","metadata":{"msg_id":"DV0-m1"}}'
  # Run-0 rows without metadata.run_index: they must count as run 0.
  printf '%s\n' "$send1" "$ack1" "$send2" > "$td/run0-unacked.jsonl"
  printf '%s\n' '{"action":"reattach_send_result","subject":"DV0","result":"ok","task_id":"DV0","metadata":{"msg_id":"DV0-m1","run_index":"x"}}' \
    > "$td/bad-run.jsonl"
  _st_artifact "$td/m1.md" DV0-m1
  _st_artifact "$td/m2.md" DV0-m2
  _st_artifact "$td/bare.md"

  _st_case supersede-match 0 --audit "$td/supersede.jsonl" --artifact "$td/m2.md"
  _st_case supersede-mismatch 3 --audit "$td/supersede.jsonl" --artifact "$td/m1.md"
  _st_case unacked 1 --audit "$td/unacked.jsonl" --artifact "$td/m1.md"
  _st_case legacy-only 0 --audit "$td/legacy.jsonl"
  _st_case run-scope-later-run 0 --run-index 1 --audit "$td/supersede.jsonl" --artifact "$td/bare.md"
  _st_case run-scope-unscoped 3 --audit "$td/supersede.jsonl" --artifact "$td/bare.md"
  _st_case run-scope-unacked-later-run 0 --run-index 1 --audit "$td/run0-unacked.jsonl" --artifact "$td/bare.md"
  _st_case run-scope-unacked-own-run 1 --run-index 0 --audit "$td/run0-unacked.jsonl"
  _st_case run-scope-bad-flag 2 --run-index -1 --audit "$td/supersede.jsonl"
  _st_case run-scope-bad-row 2 --run-index 0 --audit "$td/bad-run.jsonl"
  _st_case run-scope-bad-row-unscoped 1 --audit "$td/bad-run.jsonl"
  printf 'self-test: ALL PASS\n'
  exit 0
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --task) need_value "$@"; TASK_ID="$2"; shift 2 ;;
    --context) need_value "$@"; CONTEXT_DIR="$2"; shift 2 ;;
    --audit) need_value "$@"; AUDIT_PATH="$2"; shift 2 ;;
    --run-index) need_value "$@"; RUN_INDEX="$2"; shift 2 ;;
    --artifact) need_value "$@"; ARTIFACT="$2"; shift 2 ;;
    --self-test) self_test ;;
    -h | --help) usage; exit 0 ;;
    *)
      printf 'ack-check: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

run_check && exit 0 || exit "$?"
