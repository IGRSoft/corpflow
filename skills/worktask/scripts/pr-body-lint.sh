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
#     P1  local-path leak — .context/, /Users|home|tmp|var|opt|etc|root/, ~/,
#         ../, conductor/workspaces/. Matched on a BACKTICK-NEUTRALISED copy of
#         the line, because a code span used to defeat the sanitiser's own
#         (^|[[:space:]]) anchors and that is precisely how a `.context/` path
#         reached a published PR.
#     P2  a "Visual evidence" section with zero inline images — captures were
#         taken and the reader cannot see any of them.
#     P3  an image reference that is not an absolute https:// URL (relative and
#         local paths never resolve in a PR/issue body).
#     P4  a missing required section (Motivation / Changes / Test plan) or a
#         missing `Closes #<N>` trailer.
#     P5  an AI-attribution footer, which git-conventions.md forbids.
#
#   Warn-only by DEFAULT: findings print and the exit status stays 0, so this
#   can land without breaking in-flight worktasks. --strict (or
#   COMPANY_WORKFLOW_PR_BODY_STRICT=1) turns findings into exit 1. The strict path is
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
# @env COMPANY_WORKFLOW_PR_BODY_STRICT  1 => same as --strict.
# @env MILESTONE_MODE          1 => batch routing; the lint self-disables.
# @env INCIDENT_MODE           1 => incident routing; same self-disable.
#
# @exitcode 0   Clean, or findings in warn-only mode, or scope-disabled.
# @exitcode 1   Findings while --strict is in effect.
# @exitcode 2   Usage error (no --body, unknown flag) or --self-test failure.
# @exitcode 3   branch-lib.sh unreachable — no dispatch runs (plugin install broken).
#
# Minimum shell: bash 3.2+ (macOS default). Mirrors fn-preflight.sh conventions.

set -euo pipefail
IFS=$'\n\t'

STATE_PATH=".context/state.json"
CONTEXT_DIR=".context"
BODY_FILE=""
STRICT="${COMPANY_WORKFLOW_PR_BODY_STRICT:-0}"

# See fn-preflight.sh:62-78 for why this is a readlink loop with CDPATH= and
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

# ---------- per-line rules (P1, P3, P5) ----------
# One awk pass. Emits "<rule>\t<lineno>\t<text>" for each finding.
scan_lines() {
  LC_ALL=C awk '
    {
      # Backtick -> space, mirroring publish-pl-issue.sh sanitise_body pass 1.
      # A code span must not hide a leak from the reader-facing check either.
      probe = $0; gsub(/`/, " ", probe)

      if (probe ~ /(^|[[:space:]])\.context\//)                                  emit("P1", $0)
      else if (probe ~ /(^|[[:space:]])\/(Users|home|tmp|var|opt|etc|root)\//)   emit("P1", $0)
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

      if ($0 ~ /Generated with/ || $0 ~ /Co-Authored-By:[[:space:]]*Claude/ || $0 ~ /🤖/) emit("P5", $0)
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

  # P4: required structure. `Test plan` mirrors fn-preflight.sh:258; the other
  # three come from git-conventions.md § Pull Request Format.
  local h
  for h in Motivation Changes "Test plan"; do
    grep -E -i -q "^#{1,6}[[:space:]]+${h}[[:space:]]*$" "$f" \
      || printf 'P4\t0\tmissing required section: ## %s\n' "$h"
  done
  grep -E -q '(^|[[:space:]])(Closes|Fixes|Resolves)[[:space:]]+#[0-9]+' "$f" \
    || printf 'P4\t0\tno "Closes #<N>" trailer — the PR will not close its issue\n'
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
  # The scope guard stays the first executed check, matching fn-preflight.sh:220.
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

# ---------- self-test ----------
# The backticks in the fixtures below are LITERAL markdown code spans, not command
# substitution — that shape is the entire point of the P1 cases.
# shellcheck disable=SC2016
self_test() {
  local td rc=0
  td=$(mktemp -d -t pr-body-lint-XXXXXX)
  # shellcheck disable=SC2064
  trap "rm -rf '$td'" EXIT

  _expect() { # name, expected-rule-or-empty, body-content
    local name="$1" want="$2" body="$3" got
    printf '%s' "$body" > "$td/b.md"
    got=$(lint_body "$td/b.md" 2> "$td/err.txt")
    if [ -n "$want" ]; then
      if grep -q "warn: $want" "$td/err.txt"; then
        printf 'pr-body-lint: self-test %s PASS\n' "$name"
      else
        printf 'pr-body-lint: self-test %s FAIL (expected %s; findings=%s)\n' "$name" "$want" "$got" >&2
        rc=1
      fi
    else
      if [ "$got" = "0" ]; then
        printf 'pr-body-lint: self-test %s PASS\n' "$name"
      else
        printf 'pr-body-lint: self-test %s FAIL (expected clean, got %s)\n' "$name" "$got" >&2
        cat "$td/err.txt" >&2
        rc=1
      fi
    fi
  }

  local CLEAN='## Motivation
Because.
## Changes
- did a thing
## Test plan
- ran tests
Closes #12
'
  _expect clean-body            ""   "$CLEAN"
  # The exact shape that shipped: a code-spanned local path the sanitiser missed.
  _expect p1-context-codespan   P1   "$CLEAN"'Manifest: `.context/images/x/screenshots.md`
'
  _expect p1-context-bare       P1   "$CLEAN"'See .context/images/x/screenshots.md
'
  _expect p1-abs-host-path      P1   "$CLEAN"'Ref `/Users/me/secret/x.md`
'
  _expect p1-tilde              P1   "$CLEAN"'Ref `~/private/x.md`
'
  # A capture run whose images never reached the reader.
  _expect p2-no-images          P2   "$CLEAN"'## Visual evidence
Screenshots persisted on disk; inline hosting unavailable.
'
  # ...and the same section WITH images must stay clean.
  _expect p2-with-images        ""   "$CLEAN"'## Visual evidence
![dv-01 shot](https://github.com/user-attachments/assets/abc)
'
  _expect p3-relative-image     P3   "$CLEAN"'![shot](images/x.png)
'
  _expect p4-missing-test-plan  P4   '## Motivation
x
## Changes
- y
Closes #1
'
  _expect p4-missing-closes     P4   '## Motivation
x
## Changes
- y
## Test plan
- z
'
  _expect p5-attribution        P5   "$CLEAN"'Co-Authored-By: Claude <noreply@anthropic.com>
'

  # Usage error: nothing on stdout. A piped caller treats stdout as the run's output,
  # so help text there reads as "ran, nothing to report" over an exit-2 argument error.
  local u_out u_rc
  set +e
  u_out=$(bash "${SCRIPT_DIR}/$(basename "${BASH_SOURCE[0]:-$0}")" --not-a-flag 2> "$td/uerr.txt")
  u_rc=$?
  set -e
  if [ "$u_rc" -eq 2 ] && [ -z "$u_out" ] && grep -q 'unknown argument' "$td/uerr.txt"; then
    printf 'pr-body-lint: self-test usage-error-stderr-only PASS\n'
  else
    printf 'pr-body-lint: self-test usage-error-stderr-only FAIL (rc=%s stdout=%s)\n' "$u_rc" "$(printf '%s' "$u_out" | head -1)" >&2
    rc=1
  fi

  # -h/--help keeps stdout: an explicit help request is output, not a diagnostic.
  set +e
  u_out=$(bash "${SCRIPT_DIR}/$(basename "${BASH_SOURCE[0]:-$0}")" --help 2> /dev/null)
  u_rc=$?
  set -e
  if [ "$u_rc" -eq 2 ] && [ -n "$u_out" ]; then
    printf 'pr-body-lint: self-test help-on-stdout PASS\n'
  else
    printf 'pr-body-lint: self-test help-on-stdout FAIL (rc=%s)\n' "$u_rc" >&2
    rc=1
  fi

  if [ "$rc" -eq 0 ]; then
    printf 'pr-body-lint self-test: ALL PASS\n'
  else
    printf 'pr-body-lint self-test: FAIL\n' >&2
    exit 2
  fi
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
  self-test) self_test ;;
  lint) cmd_lint ;;
esac
