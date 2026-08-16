#!/usr/bin/env bash
# @description preflight-issue-scan.sh — ADVISORY scan for open GitHub issues that
#   plausibly already cover the request, run at `/worktask` entry BEFORE `.context/`
#   is created (`commands/worktask.md § Step 2a`).
#
#   `skills/gh-issue-dedup` binds one issue per `.context/` via the anchor or an
#   exact-title search — both only reachable once a `.context/` exists, so they
#   guard re-runs and never the first run of work already filed under different
#   wording. This scan is the layer above: advisory only, human-confirmed, and it
#   NEVER links, comments, or writes. The exact-match-only auto-bind stays as is;
#   widening it would let an unrelated same-worded issue capture a fresh context.
#
#   Scoring is local keyword overlap rather than a server-side query because
#   GitHub's issue search ANDs free-text terms — a query built from a whole request
#   sentence returns nothing for exactly the paraphrase this must catch.
#
#   NON-BLOCKING BY CONTRACT, like every helper the orchestrator invokes with a
#   trailing `|| true`: no network, no `gh`, no auth, no remote, a timeout, a
#   malformed response, or zero hits all exit 0 with a `result=` the caller reads as
#   "proceed". There is no runtime state in which this step stops a worktask.
#
#   It writes NO audit row: the ledger it would append to does not exist yet at
#   Step 2a, and creating `.context/logs/` here would strand scratch state in a
#   worktask the user then abandons in favour of an existing issue.
#
# @arg --goal <text>      The user's request text. Empty => `skipped/no_goal`.
# @arg --context <dir>    .context dir probed for the dedup anchor (default: .context).
# @arg --limit <n>        Max candidates emitted (default: 3).
# @arg --no-gh-issue      Caller passed /worktask --no-gh-issue => `skipped/opted_out`.
# @arg -h | --help        Show this header.
#
# @env PREFLIGHT_ISSUE_SCAN   0 => `skipped/opted_out`.
# @env CORPFLOW_NONINTERACTIVE 1 => `skipped/non_interactive` (nothing can answer the gate).
# @env MILESTONE_MODE         1 => `skipped/milestone_mode` (/megatask owns issue identity).
# @env INCIDENT_MODE          1 => `skipped/incident_mode` (no PL stage, no plan issue).
# @env PREFLIGHT_SCAN_POOL    Open issues fetched before scoring (default: 100).
# @env PREFLIGHT_SCAN_TIMEOUT Seconds bounding the `gh` call (default: 20).
# @env GH_BIN                 `gh` binary (default: gh).
# @env WORKSPACE_ROOT         Root probed for a megatask `workspace.json`.
#
# @stdout `result=shown|none|skipped`, `reason=<closed set>` when not `shown`,
#         `candidates=<n>`, and one `candidate=<compact-json>` line per hit
#         (`{number,url,title,score}`). JSON per line because issue titles contain
#         every plausible field separator.
#
# @exitcode 0   Every runtime outcome, candidates or not.
# @exitcode 2   Usage error or -h.
#
# Minimum shell: bash 3.2+ (macOS default).

set -u

CONTEXT_DIR=".context"
GOAL=""
GOAL_SEEN=0
LIMIT=3
OPT_OUT=0

GH_BIN="${GH_BIN:-gh}"
POOL="${PREFLIGHT_SCAN_POOL:-100}"
SCAN_TIMEOUT="${PREFLIGHT_SCAN_TIMEOUT:-20}"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-}"

# A title word must clear this many characters to count as a keyword, and a
# candidate must share this many keywords to be shown. Both are deliberately
# blunt: the output is a human prompt, not an automated decision.
MIN_KEYWORD_LEN=3
MIN_SCORE=2
MAX_KEYWORDS=8

# Request-shaped filler that co-occurs with everything and would otherwise score
# unrelated issues into the list. Words under MIN_KEYWORD_LEN are dropped anyway.
STOPWORDS="the and for with that this from into when then make made use used using
add adds added fix fixes fixed new old all any not but can its our your are was were
has have had does did get got set run via per out off support feature
should would could must need needs also more less than them they there here what
which while into onto upon about after before over under such only just even
worktask task work update updates change changes"

usage() {
  awk 'NR>1{ if (!/^#/) exit; sub(/^# ?/,""); print }' "$0"
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --goal)
      shift
      [ $# -gt 0 ] || { printf >&2 'preflight-issue-scan: --goal requires a value\n'; exit 2; }
      GOAL="$1"; GOAL_SEEN=1; shift ;;
    --context)
      shift
      [ $# -gt 0 ] || { printf >&2 'preflight-issue-scan: --context requires a value\n'; exit 2; }
      CONTEXT_DIR="$1"; shift ;;
    --limit)
      shift
      [ $# -gt 0 ] || { printf >&2 'preflight-issue-scan: --limit requires a value\n'; exit 2; }
      LIMIT="$1"; shift ;;
    --no-gh-issue) OPT_OUT=1; shift ;;
    -h|--help) usage ;;
    *) printf >&2 'preflight-issue-scan: unknown argument: %s\n' "$1"; exit 2 ;;
  esac
done

[ "$GOAL_SEEN" = "1" ] || { printf >&2 'preflight-issue-scan: --goal is required\n'; exit 2; }
case "$LIMIT" in
  ''|*[!0-9]*) printf >&2 'preflight-issue-scan: --limit must be a non-negative integer\n'; exit 2 ;;
esac

finish_skipped() { # $1=reason
  printf 'result=skipped\n'
  printf 'reason=%s\n' "$1"
  printf 'candidates=0\n'
  exit 0
}

finish_none() { # $1=reason
  printf 'result=none\n'
  printf 'reason=%s\n' "$1"
  printf 'candidates=0\n'
  exit 0
}

# Bounded execution WITHOUT coreutils, mirroring publish-pl-issue.sh: stock macOS
# ships neither `timeout` nor `gtimeout`, so the usual `command -v timeout` idiom
# resolves to empty and leaves the call unbounded on the platform that needs it.
TIMEOUT_BIN="${TIMEOUT_BIN:-$(command -v gtimeout || command -v timeout || true)}"
run_with_timeout() {
  local secs="$1"; shift
  if [ -n "$TIMEOUT_BIN" ]; then
    "$TIMEOUT_BIN" "$secs" "$@"
    return $?
  fi
  "$@" &
  local p=$! n=0
  while kill -0 "$p" 2> /dev/null && [ "$n" -lt "$secs" ]; do
    sleep 1; n=$((n + 1))
  done
  if kill -0 "$p" 2> /dev/null; then
    kill -9 "$p" 2> /dev/null || true
    wait "$p" 2> /dev/null || true
    return 124
  fi
  wait "$p" 2> /dev/null
  return $?
}

# ---------- guards ----------------------------------------------------------
[ "$OPT_OUT" = "1" ] && finish_skipped opted_out
[ "${PREFLIGHT_ISSUE_SCAN:-1}" = "0" ] && finish_skipped opted_out
[ "$LIMIT" = "0" ] && finish_skipped opted_out

# An AskUserQuestion gate cannot be answered by a batch, cron or CI invocation, so
# an unattended run must never reach one. Skip-and-proceed is the only safe default:
# the worst case is the duplicate this step exists to prevent, which is strictly
# better than a pipeline blocked on a prompt nobody will see.
[ "${CORPFLOW_NONINTERACTIVE:-0}" = "1" ] && finish_skipped non_interactive
[ "${INCIDENT_MODE:-0}" = "1" ] && finish_skipped incident_mode
[ "${MILESTONE_MODE:-0}" = "1" ] && finish_skipped milestone_mode
if [ -n "$WORKSPACE_ROOT" ] && [ -f "$WORKSPACE_ROOT/workspace.json" ]; then
  finish_skipped milestone_mode
fi
[ -f "$PWD/workspace.json" ] && finish_skipped milestone_mode

# A context already bound to an issue is a RESUME, not a first run — the anchor in
# skills/gh-issue-dedup already answers this question authoritatively.
[ -f "$CONTEXT_DIR/gh-issue.json" ] && finish_skipped already_anchored

command -v jq > /dev/null 2>&1 || finish_skipped jq_unavailable

# ---------- keyword extraction ----------------------------------------------
# Stemmed to a bare singular, and matched as a word PREFIX below, so "issues"
# scores against "issue" and "open" against "opened" — morphological drift is the
# commonest way a paraphrase escapes exact matching.
KEYWORDS=$(
  printf '%s' "$GOAL" \
    | LC_ALL=C tr '[:upper:]' '[:lower:]' \
    | LC_ALL=C tr -c 'a-z0-9' ' ' \
    | LC_ALL=C tr -s ' ' '\n' \
    | awk -v min="$MIN_KEYWORD_LEN" '
        length($0) >= min {
          if (length($0) >= 4 && substr($0, length($0)) == "s" && substr($0, length($0) - 1) != "ss") {
            $0 = substr($0, 1, length($0) - 1)
          }
          if (length($0) >= min) print
        }' \
    | grep -v -w -F -f <(printf '%s' "$STOPWORDS" | tr -s '[:space:]' '\n') \
    | awk '!seen[$0]++' \
    | head -n "$MAX_KEYWORDS"
)
[ -n "$KEYWORDS" ] || finish_skipped no_keywords

KEYWORDS_JSON=$(printf '%s\n' "$KEYWORDS" | jq -R . | jq -cs .) || finish_skipped no_keywords

# A single surviving keyword cannot clear a 2-keyword bar; requiring it would make
# short requests silently unscannable rather than honestly unmatched.
EFFECTIVE_MIN="$MIN_SCORE"
if [ "$(printf '%s\n' "$KEYWORDS" | wc -l | tr -d ' ')" -lt "$MIN_SCORE" ]; then
  EFFECTIVE_MIN=1
fi

# ---------- fetch ------------------------------------------------------------
command -v "$GH_BIN" > /dev/null 2>&1 || finish_skipped gh_not_installed
run_with_timeout "$SCAN_TIMEOUT" "$GH_BIN" auth status > /dev/null 2>&1 || finish_skipped auth_missing
git remote get-url origin 2> /dev/null | grep -q . || finish_skipped no_remote

# Redirected to a file rather than captured through `$(...)`: a killed `gh` can
# leave a grandchild holding the write end of a command-substitution pipe, and the
# read would then outlive the timeout it exists to enforce.
SCAN_TMP=$(mktemp "${TMPDIR:-/tmp}/preflight-issue-scan.XXXXXX" 2> /dev/null) \
  || finish_skipped search_failed
trap 'rm -f "$SCAN_TMP" 2>/dev/null || true' EXIT

run_with_timeout "$SCAN_TIMEOUT" "$GH_BIN" issue list --state open \
  --json number,title,url --limit "$POOL" > "$SCAN_TMP" 2> /dev/null \
  || finish_skipped search_failed
RAW=$(cat "$SCAN_TMP" 2> /dev/null || true)
[ -n "$RAW" ] || finish_skipped search_failed
printf '%s' "$RAW" | jq -e 'type == "array"' > /dev/null 2>&1 || finish_skipped search_failed

# Keywords are `[a-z0-9]+` by construction above, so interpolating them into the
# regex below cannot inject alternation or anchors. `$k` is bound before the pipe
# because `$t | test(...)` rebinds `.` to the title.
MATCHED=$(printf '%s' "$RAW" | jq -c \
  --argjson kws "$KEYWORDS_JSON" --argjson min "$EFFECTIVE_MIN" --argjson lim "$LIMIT" '
  [ .[]
    | select((.title // "") != "")
    | . as $i
    | (($i.title | ascii_downcase)) as $t
    | { number: $i.number, url: $i.url, title: $i.title,
        score: ([ $kws[] | . as $k
                  | select($t | test("(^|[^a-z0-9])" + $k)) ] | length) }
  ]
  | map(select(.score >= $min))
  | sort_by(-.score, -.number)
  | .[0:$lim]' 2> /dev/null) || finish_skipped search_failed
[ -n "$MATCHED" ] || finish_skipped search_failed

COUNT=$(printf '%s' "$MATCHED" | jq 'length' 2> /dev/null || printf '0')
[ "$COUNT" = "0" ] && finish_none no_candidates

printf 'result=shown\n'
printf 'candidates=%s\n' "$COUNT"
printf '%s' "$MATCHED" | jq -c '.[]' | while IFS= read -r line; do
  printf 'candidate=%s\n' "$line"
done
printf >&2 'preflight-issue-scan: %s open issue(s) may already cover this request\n' "$COUNT"
exit 0
