#!/usr/bin/env bash
# control-byte-lint.sh — report raw C0 control bytes in text files, by path or by staged index blob.
#
# Usage:
#   control-byte-lint.sh [--] <path>...
#       Lint each path whose extension is on the text allowlist; any other path is skipped.
#   control-byte-lint.sh --staged
#       Lint the INDEX bytes of every staged, non-deleted text file in the cwd repository.
#       Gitlinks, symlinks, vendored paths and paths whose attributes set `binary` or unset
#       `text` are skipped. An unmerged path is an error: its index holds no single blob.
#   control-byte-lint.sh --self-test
#   control-byte-lint.sh -h | --help
#
# Flags 0x00-0x08, 0x0B, 0x0C, 0x0E-0x1F; tab, LF, CR, DEL and bytes 0x80+ pass.
# A hit prints `<path>:<offset>:0x<HH>` on stdout (0-based offset, at most 20 per file) and
# one count line on stderr. Every error line starts `control-byte-lint: ` on stderr.
#
# Exit: 0 clean, 1 at least one hit, 2 usage error, unreadable file, not a git repository,
# unmerged path, git failure or library unreachable. 2 wins over 1: a partial scan is no verdict.
#
# Minimum shell: bash 3.2+ (macOS default).

set -euo pipefail

usage() {
  if [ "${1:-2}" -eq 0 ]; then
    sed -n '2,/^$/s/^# \{0,1\}//p' "$0"
  else
    sed -n '2,/^$/s/^# \{0,1\}//p' "$0" >&2
  fi
  exit "${1:-2}"
}

err() {
  printf >&2 'control-byte-lint: %s\n' "$*"
}

_CB_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/control-byte-lib.sh"
if [ -r "$_CB_LIB" ]; then
  # shellcheck source=control-byte-lib.sh
  . "$_CB_LIB"
fi
if ! command -v cb_scan_file > /dev/null 2>&1; then
  err "control-byte-lib.sh unreachable at $_CB_LIB — plugin install broken"
  exit 2
fi

HIT_FILES=0
SCAN_ERR=0

# scan_one <file> <label> — accumulates into HIT_FILES / SCAN_ERR.
scan_one() {
  local rc=0
  cb_scan_file "$1" "$2" || rc=$?
  case "$rc" in
    0) ;;
    1) HIT_FILES=$((HIT_FILES + 1)) ;;
    *)
      err "cannot scan $2"
      SCAN_ERR=1
      ;;
  esac
}

finish() {
  if [ "$HIT_FILES" -gt 0 ]; then
    err "control bytes in $HIT_FILES file(s)"
  fi
  [ "$SCAN_ERR" -eq 0 ] || exit 2
  [ "$HIT_FILES" -eq 0 ] || exit 1
  exit 0
}

lint_paths() {
  local p
  for p in "$@"; do
    cb_is_lintable "$p" || continue
    scan_one "$p" "$p"
  done
  finish
}

# attr_opted_out <path> — rc 0 when the index's attributes declare the path binary.
attr_opted_out() {
  local attr val out
  # Only attr and val matter; the path field is the one just asked about.
  out=$(git check-attr --cached -z binary text -- "$1" | tr '\000' '\n') || return 1
  while IFS= read -r _ && IFS= read -r attr && IFS= read -r val; do
    case "$attr:$val" in
      binary:set | text:unset) return 0 ;;
    esac
  done <<< "$out"
  return 1
}

lint_staged() {
  git rev-parse --git-dir > /dev/null 2>&1 || {
    err "not a git repository"
    exit 2
  }

  TMPD=$(mktemp -d "${TMPDIR:-/tmp}/control-byte-lint.XXXXXX")
  trap 'rm -rf "$TMPD"' EXIT
  trap 'exit 130' INT TERM

  # To a file, never `< <(...)`: process substitution discards git's exit status.
  if ! git diff --cached --raw -z --no-abbrev --no-renames --diff-filter=d > "$TMPD/raw"; then
    err "git diff --cached failed"
    exit 2
  fi

  # Valued on purpose: bash 4+ leaves a bare `local` unset, and an empty index never enters the loop.
  local meta='' p='' dstmode='' dstsha='' status=''
  while IFS= read -r -d '' meta && IFS= read -r -d '' p; do
    read -r _ dstmode _ dstsha status <<< "${meta#:}"
    case "$status" in
      U*)
        err "unmerged path $p — resolve the conflict before linting the index"
        exit 2
        ;;
    esac
    case "$dstmode" in 160000 | 120000) continue ;; esac
    cb_is_lintable "$p" || continue
    ! attr_opted_out "$p" || continue
    # By SHA, never `:<path>`: a path shaped `N:name` parses as a merge-stage spec.
    if ! git cat-file blob "$dstsha" > "$TMPD/blob" 2> /dev/null; then
      err "cannot read the index blob of $p"
      SCAN_ERR=1
      continue
    fi
    scan_one "$TMPD/blob" "$p"
  done < "$TMPD/raw"
  finish
}

self_test() {
  local td out rc
  td=$(mktemp -d "${TMPDIR:-/tmp}/control-byte-lint-selftest.XXXXXX")
  # shellcheck disable=SC2064  # the path is fixed at set time on purpose
  trap "rm -rf '$td'" EXIT

  printf 'ab\000c\n' > "$td/nul.md"
  printf 'tab\tcr\r\ndel\177 utf8 \303\251 literal \\0 \\x00 ^@\n' > "$td/clean.md"
  printf 'x\033y\n' > "$td/esc.png"

  rc=0
  out=$(bash "$0" -- "$td/nul.md" 2> /dev/null) || rc=$?
  [ "$rc" -eq 1 ] && [ "$out" = "$td/nul.md:2:0x00" ] || {
    printf >&2 'control-byte-lint: self-test FAIL (NUL: rc=%s out=%s)\n' "$rc" "$out"
    exit 1
  }
  rc=0
  bash "$0" -- "$td/clean.md" "$td/esc.png" > /dev/null 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || {
    printf >&2 'control-byte-lint: self-test FAIL (clean text or skipped binary: rc=%s)\n' "$rc"
    exit 1
  }
  printf 'control-byte-lint: self-test OK\n'
}

[ $# -gt 0 ] || usage 2
case "$1" in
  -h | --help) usage 0 ;;
  --self-test)
    [ $# -eq 1 ] || usage 2
    self_test
    ;;
  --staged)
    [ $# -eq 1 ] || usage 2
    lint_staged
    ;;
  --)
    shift
    [ $# -gt 0 ] || usage 2
    lint_paths "$@"
    ;;
  -*)
    err "unknown option: $1"
    usage 2
    ;;
  *) lint_paths "$@" ;;
esac
