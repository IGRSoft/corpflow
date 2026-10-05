#!/usr/bin/env bash
# @description pr-body-lint.sh — validate a composed PR body before it is published.
#
#   The FN gate already SANITISES the body (fn-preflight.sh pr-body) but never
#   inspects the result, so a body that lost every image and kept a dead local
#   path passed as "ok". This lint is the missing read-back. It is deliberately
#   redundant with the sanitiser on P1: overlapping coverage is what proves the
#   sanitiser actually ran, rather than assuming it did.
#
#   Rules (each reports file line numbers):
#     P1  local-path leak — .context/, an absolute host path or a Windows drive
#         letter as defined once by skills/shared/scripts/path-scrub.sh
#         (CORPFLOW_HOST_PATH_ERE, CORPFLOW_DRIVE_PATH_ERE — the sanitiser reads the
#         same two), ~/, ../, conductor/workspaces/. Matched on a BACKTICK-NEUTRALISED copy of
#         the line, because a code span used to defeat the sanitiser's own
#         (^|[[:space:]]) anchors and that is precisely how a `.context/` path
#         reached a published PR.
#     P2  a "Visual evidence" section with zero inline images — captures were
#         taken and the reader cannot see any of them.
#     P3  an image reference that is not an absolute https:// URL (relative and
#         local paths never resolve in a PR/issue body).
#     P4  a missing required section (Motivation / Changes / Test plan) or a
#         missing `Closes #<N>` trailer. The trailer arm fires only when an issue
#         anchor resolves (git-conventions.md § No issue anchor); with none, a body
#         without a closing line is compliant, matching `validate-pr`'s degrade.
#
#   Warn-only by DEFAULT: findings print and the exit status stays 0, so this
#   can land without breaking in-flight worktasks. --strict (or
#   CORPFLOW_PR_BODY_STRICT=1) turns findings into exit 1. The strict path is
#   intended to become the default in a later minor, mirroring the
#   handoff-harness.sh AR-ref rollout.
#
#   Like fn-preflight.sh's own gate, this self-disables under batch (/megatask)
#   and incident (--emergency) routing, so those pipelines are unaffected.
#   Zero network: no gh, no git push, no fetch.
#
# @arg --body <path>      Composed PR body file (required).
# @arg --state <path>     state.json path (default: .context/state.json).
# @arg --context <dir>    .context dir (default: .context).
# @arg --strict           Promote findings from warnings to a blocking exit 1.
# @arg --self-test        Run the embedded fixture suite.
# @arg -h | --help        Show this header.
#
# @env CORPFLOW_PR_BODY_STRICT  1 => same as --strict.
# @env MILESTONE_MODE          1 => batch routing; the lint self-disables.
# @env INCIDENT_MODE           1 => incident routing; same self-disable.
#
# @exitcode 0   Clean, or findings in warn-only mode, or scope-disabled.
# @exitcode 1   Findings while --strict is in effect.
# @exitcode 2   Usage error (no --body, unknown flag) or --self-test failure.
# @exitcode 3   branch-lib.sh or path-scrub.sh unreachable — no dispatch runs (plugin
#               install broken).
#
# Minimum shell: bash 3.2+ (macOS default). Mirrors fn-preflight.sh conventions.

set -euo pipefail
IFS=$'\n\t'

STATE_PATH=".context/state.json"
CONTEXT_DIR=".context"
BODY_FILE=""
STRICT="${CORPFLOW_PR_BODY_STRICT:-0}"

# See fn-preflight.sh _resolve_script_dir for why this is a readlink loop with CDPATH= and
# `pwd -P` rather than a plain dirname.
_resolve_script_dir() {
  local src="${BASH_SOURCE[0]:-$0}" dir
  while [ -h "$src" ]; do
    dir=$(CDPATH= cd -- "$(dirname -- "$src")" && pwd -P)
    src=$(readlink "$src")
    case "$src" in
      /*) ;;
      *) src="$dir/$src" ;;
    esac
  done
  CDPATH= cd -- "$(dirname -- "$src")" && pwd -P
}
SCRIPT_DIR="$(_resolve_script_dir 2> /dev/null)" || SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]:-$0}")"

BRANCH_LIB_PATH="${SCRIPT_DIR}/branch-lib.sh"
# `[ -r ]` first, not a bare `.`: sourcing a missing file with the `.` builtin is
# a special-builtin error that exits a `set -e` shell immediately, bypassing an
# `if ! . …; then` guard entirely.
if [ -n "$BRANCH_LIB_PATH" ] && [ -r "$BRANCH_LIB_PATH" ]; then
  # shellcheck disable=SC1090
  . "$BRANCH_LIB_PATH"
else
  printf >&2 'pr-body-lint.sh: branch-lib.sh unreachable at %s — plugin install broken\n' \
    "$BRANCH_LIB_PATH"
  exit 3
fi

# P1 without the shared pattern would report a body clean that the sanitiser never
# checked for host paths, so its absence is the same broken install as above.
PATH_SCRUB_PATH="${SCRIPT_DIR}/../../shared/scripts/path-scrub.sh"
if [ -r "$PATH_SCRUB_PATH" ]; then
  # shellcheck disable=SC1090
  . "$PATH_SCRUB_PATH"
else
  printf >&2 'pr-body-lint.sh: path-scrub.sh unreachable at %s — plugin install broken\n' \
    "$PATH_SCRUB_PATH"
  exit 3
fi

# $1="err" routes the header to stderr. Callers run this script under the house
# `; true` / piped convention, where a usage ERROR printing help on stdout reads as
# ordinary output and the exit-2 diagnostic on stderr is never reconciled with it.
# An explicit -h/--help keeps stdout so it stays pipeable.
usage() {
  if [ "${1:-}" = "err" ]; then
    awk 'NR>1{ if (!/^#/) exit; sub(/^# ?/,""); print }' "$0" >&2
  else
    awk 'NR>1{ if (!/^#/) exit; sub(/^# ?/,""); print }' "$0"
  fi
  exit 2
}

# ---------- issue anchor ----------
# Ranked identically to `resolve_issue` in fn-preflight-cmds.sh, and that parity is
# the point: P4's trailer rule must fire on exactly the runs where
# `fn-preflight.sh validate-pr` blocks, or the convention and its two enforcers
# disagree. Duplicated rather than sourced because that library is a `set -u`
# ~1600-line prologue this script cannot pull into its own `set -euo pipefail`.
# Cached: the answer is per run, while scan_document runs per body.
ISSUE_ANCHOR=""
ISSUE_ANCHOR_RESOLVED=0
issue_anchor() {
  if [ "$ISSUE_ANCHOR_RESOLVED" = "1" ]; then
    printf '%s' "$ISSUE_ANCHOR"
    return 0
  fi
  local n=""
  if command -v jq > /dev/null 2>&1; then
    n=$(jq -r '.metadata.github_issue_url // empty' "$STATE_PATH" 2> /dev/null \
      | grep -oE '[0-9]+$' || true)
    if [ -z "$n" ]; then
      n=$(jq -r 'if .url then .url elif .number then (.number|tostring) else empty end' \
        "${CONTEXT_DIR}/gh-issue.json" 2> /dev/null | grep -oE '[0-9]+$' || true)
    fi
    if [ -z "$n" ]; then
      n=$(jq -r '.metadata.github_issue_number // empty' "$STATE_PATH" 2> /dev/null || true)
    fi
  fi
  # A ticket-less `feature/<slug-ending-in-digit>` branch must not resolve a bogus
  # number, so this is the `<type>/<NNN>-<slug>` shape, never a trailing integer.
  if [ -z "$n" ]; then
    n=$(git rev-parse --abbrev-ref HEAD 2> /dev/null \
      | sed -nE 's#^[a-zA-Z]+/([0-9]+)-.*#\1#p' || true)
  fi
  if [ -z "$n" ]; then
    n=$(git log --oneline -n 5 2> /dev/null | grep -oE '#[0-9]+' | head -1 | tr -d '#' || true)
  fi
  ISSUE_ANCHOR="$n"
  ISSUE_ANCHOR_RESOLVED=1
  printf '%s' "$ISSUE_ANCHOR"
}

# ---------- per-line rules (P1, P3) ----------
# One awk pass. Emits "<rule>\t<lineno>\t<text>" for each finding.
scan_lines() {
  # ENVIRON, not -v: BSD awk rewrites backslash escapes in -v values, and the
  # drive-letter ERE ends in one.
  CORPFLOW_HOST_PATH_ERE="$CORPFLOW_HOST_PATH_ERE" \
    CORPFLOW_DRIVE_PATH_ERE="$CORPFLOW_DRIVE_PATH_ERE" \
    LC_ALL=C awk '
    BEGIN {
      host_re = "(^|[[:space:]])" ENVIRON["CORPFLOW_HOST_PATH_ERE"]
      drive_re = "(^|[[:space:]])" ENVIRON["CORPFLOW_DRIVE_PATH_ERE"]
    }
    {
      # Backtick -> space, mirroring publish-pl-issue.sh sanitise_body pass 1.
      # A code span must not hide a leak from the reader-facing check either.
      probe = $0; gsub(/`/, " ", probe)

      if (probe ~ /(^|[[:space:]])\.context\//)                                  emit("P1", $0)
      else if (probe ~ host_re)                                                  emit("P1", $0)
      else if (probe ~ drive_re)                                                 emit("P1", $0)
      else if (probe ~ /(^|[[:space:]])~\//)                                     emit("P1", $0)
      else if (probe ~ /(^|[[:space:]])\.\.\//)                                  emit("P1", $0)
      else if (probe ~ /conductor\/workspaces\/[A-Za-z0-9_-]+/)                  emit("P1", $0)

      # P3: an image ref whose target is not an absolute https URL. Checked on
      # the raw line so a legitimately code-spanned example is still seen.
      if (match($0, /!\[[^]]*\]\([^)]*\)/)) {
        ref = substr($0, RSTART, RLENGTH)
        sub(/^!\[[^]]*\]\(/, "", ref); sub(/\)$/, "", ref)
        if (ref !~ /^https:\/\//) emit("P3", $0)
      }
    }
    function emit(rule, text) { printf "%s\t%d\t%s\n", rule, NR, text }
  ' "$1"
}

# ---------- whole-file rules (P2, P4) ----------
scan_document() {
  local f="$1" images

  # P2: a Visual evidence section that shows the reader nothing. Counted over the
  # whole body rather than the section, so a stray image elsewhere cannot mask it.
  if grep -E -i -q '^#{1,6}[[:space:]]+Visual evidence' "$f"; then
    images=$(grep -c -E '!\[[^]]*\]\(https://' "$f" || true)
    [ "$images" -eq 0 ] && printf 'P2\t0\tVisual evidence section present but no inline images reached the reader\n'
  fi

  # P4: required structure. `Test plan` mirrors fn-preflight-cmds.sh cmd_pr_body; the other
  # three come from git-conventions.md § Pull Request Format.
  local h
  for h in Motivation Changes "Test plan"; do
    grep -E -i -q "^#{1,6}[[:space:]]+${h}[[:space:]]*$" "$f" \
      || printf 'P4\t0\tmissing required section: ## %s\n' "$h"
  done
  # Two arms, per git-conventions.md § No issue anchor. With no anchor there is no
  # issue to close and a bare body is compliant; demanding a trailer anyway invites
  # an invented number, which closes an unrelated issue on merge.
  local anchor
  anchor=$(issue_anchor)
  if [ -n "$anchor" ]; then
    grep -E -q '(^|[[:space:]])(Closes|Fixes|Resolves)[[:space:]]+#[0-9]+' "$f" \
      || printf 'P4\t0\tno "Closes #<N>" trailer — the PR will not close its issue (anchor #%s)\n' "$anchor"
  fi
}

lint_body() {
  local f="$1" findings n
  findings=$(
    { scan_lines "$f"; scan_document "$f"; } || true
  )
  n=0
  if [ -n "$findings" ]; then
    while IFS="$(printf '\t')" read -r rule ln text; do
      [ -z "$rule" ] && continue
      n=$((n + 1))
      if [ "$ln" = "0" ]; then
        printf >&2 'warn: %s — %s\n' "$rule" "$text"
      else
        printf >&2 'warn: %s — line %s: %s\n' "$rule" "$ln" "$text"
      fi
    done <<EOF
$findings
EOF
  fi
  printf '%d' "$n"
}

cmd_lint() {
  [ -n "$BODY_FILE" ] && [ -f "$BODY_FILE" ] || {
    printf >&2 'pr-body-lint requires --body <path> to an existing file\n'
    exit 2
  }
  # The scope guard stays the first executed check, matching fn-preflight-cmds.sh cmd_pr_body.
  # Only consulted when a ledger exists, so the lint is still usable standalone
  # on an arbitrary file with no .context/ around it.
  if [ -f "$STATE_PATH" ] && fn_batch_scope 2> /dev/null; then
    printf 'pr-body-lint: skipped (%s)\n' "${SCOPE_REASON:-batch}"
    _audit skipped "$(meta_json reason "${SCOPE_REASON:-batch}")"
    return 0
  fi

  local n
  n=$(lint_body "$BODY_FILE")
  if [ "$n" -eq 0 ]; then
    printf 'pr-body-lint: clean\n'
    _audit ok "$(meta_json findings 0)"
    return 0
  fi
  if [ "$STRICT" = "1" ]; then
    printf >&2 'pr-body-lint: %d finding(s) — BLOCKED (--strict)\n' "$n"
    _audit blocked "$(meta_json findings "$n" strict 1)"
    return 1
  fi
  printf 'pr-body-lint: %d finding(s) — warn-only (re-run with --strict to block)\n' "$n"
  _audit warned "$(meta_json findings "$n" strict 0)"
  return 0
}

# audit_fn derives its fields from $STATE_PATH; with no ledger there is nothing
# to attribute a row to, so skip rather than emit a rootless one.
_audit() {
  [ -f "$STATE_PATH" ] || return 0
  # audit_fn also mkdir -p's this, but doing it here keeps --context meaningful
  # when the caller points at a non-default ledger directory.
  mkdir -p "${CONTEXT_DIR}/logs" 2> /dev/null || true
  audit_fn pr_body_lint "$1" "$2" 2> /dev/null || true
}

# ---------- dispatch ----------
MODE="lint"
while [ $# -gt 0 ]; do
  case "$1" in
    --body) shift; BODY_FILE="${1:-}"; shift ;;
    --state) shift; STATE_PATH="${1:-}"; shift ;;
    --context) shift; CONTEXT_DIR="${1:-}"; shift ;;
    --strict) STRICT=1; shift ;;
    --self-test) MODE="self-test"; shift ;;
    -h | --help) usage ;;
    *) printf >&2 'unknown argument: %s\n' "$1"; usage err ;;
  esac
done

case "$MODE" in
  self-test)
    # Sourced HERE, not at the top: the harness is test code the production path
    # never runs. `[ -r ]` first, not a bare `.`: sourcing a missing file with the
    # `.` builtin is a special-builtin error that exits the shell immediately,
    # bypassing an `if ! . …` guard entirely.
    SELFTEST_LIB_PATH="$(dirname "${BASH_SOURCE[0]}")/pr-body-lint-selftest.sh"
    if [ -r "$SELFTEST_LIB_PATH" ]; then
      # shellcheck source=pr-body-lint-selftest.sh
      # shellcheck disable=SC1090
      . "$SELFTEST_LIB_PATH"
    else
      printf >&2 'pr-body-lint: self-test harness unreachable at %s — plugin install broken\n' \
        "$SELFTEST_LIB_PATH"
      exit 2
    fi
    self_test
    ;;
  lint) cmd_lint ;;
esac
