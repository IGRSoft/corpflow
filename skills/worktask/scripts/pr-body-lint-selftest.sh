#!/usr/bin/env bash
# pr-body-lint-selftest.sh — the `--self-test` harness for pr-body-lint.sh.
#
# SOURCED, never executed: pr-body-lint.sh loads this file only on the `--self-test`
# path, so the production path never pays for it. Sourcing leaves the caller's
# `$0` and every function it has already defined in scope — this file reads the
# caller's helpers and is not standalone.
#
# Contract: defines `self_test`, returning 0 when every case passes.

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
  # One case per mount convention the P1 prefix list claims.
  local p
  for p in /Users/me /home/me /tmp/w /var/w /opt/w /etc/w /root/w \
    /Volumes/internal/Projects /mnt/data /mnt/c/Users/me /media/usb \
    /private/tmp/w /srv/www; do
    _expect "p1-abs${p//\//-}" P1 "$CLEAN""Ref \`$p/x.md\`
"
  done
  _expect p1-drive-letter       P1   "$CLEAN"'Ref `C:\Users\me\x.md`
'
  # Over-match guard: repo-relative paths and prose reusing those words stay clean.
  _expect nomatch-relative-path ""   "$CLEAN"'Edit `skills/worktask/scripts/pr-body-lint.sh`
'
  _expect nomatch-prose         ""   "$CLEAN"'Deployed under srv and media naming; the var name is opt_in.
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

  # Usage error: nothing on stdout. A piped caller treats stdout as the run's output,
  # so help text there reads as "ran, nothing to report" over an exit-2 argument error.
  local u_out u_rc
  set +e
  # `$0`, not BASH_SOURCE: this file is sourced, so BASH_SOURCE[0] names the
  # harness. Both arms re-invoke the caller, pr-body-lint.sh.
  u_out=$(bash "${SCRIPT_DIR}/$(basename "$0")" --not-a-flag 2> "$td/uerr.txt")
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
  u_out=$(bash "${SCRIPT_DIR}/$(basename "$0")" --help 2> /dev/null)
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
