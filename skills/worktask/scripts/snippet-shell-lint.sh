#!/usr/bin/env bash
# @description snippet-shell-lint.sh — flag shell snippets that do not declare bash.
#
#   Scoped to markdown sections, not whole files, so it can enforce the seed path without
#   colliding with sibling edits elsewhere in the same documents.
#
#   Rules, applied inside the section only:
#     a  outside fences, a line indented 4+ spaces or a tab after a blank line (an
#        indented code block). One report per block. Limitation: a list continuation
#        paragraph indented 4+ spaces after a blank line is flagged too, so scoped
#        sections keep continuations at 3 spaces or fewer.
#     b  a fence labelled sh/shell/zsh/console/shell-session, or an unlabelled fence whose
#        body looks like shell. Labelled non-shell fences (json, yaml, text) are exempt.
#     c  inside bash fences, a command whose first word ends in .sh (run it as `bash x.sh`).
#        `.`/`source` of a library is fine. Continuation lines are skipped; no heredoc
#        awareness.
#
# Usage:
#   bash "$PLUGIN_ROOT/skills/worktask/scripts/snippet-shell-lint.sh"
#   bash "$PLUGIN_ROOT/skills/worktask/scripts/snippet-shell-lint.sh" --target '<path>::<heading prefix>' [--target ...]
#   bash "$PLUGIN_ROOT/skills/worktask/scripts/snippet-shell-lint.sh" --self-test | -h | --help
#
# @arg --target <path>::<prefix>  Split on the first `::`. A relative path resolves against
#   the plugin root, never cwd. The section starts at the first heading outside a fence
#   that begins with the prefix and ends before the next heading of the same or a higher
#   level. No --target means the default seed-path targets (listed by --help).
#
# stdout: `<path>:<line>: rule-<a|b|c>: <message>` per violation, then one
#   `snippet-shell-lint: <path>::<prefix>: ok|<n> violation(s)` line per target.
#
# @exitcode 0 Clean.
# @exitcode 1 At least one violation.
# @exitcode 2 Usage error, unreadable file, heading not found, or an unterminated fence
#   in a section.
#
# Minimum shell: bash 3.2+; POSIX awk (BWK and mawk).

set -Eeuo pipefail
IFS=$'\n\t'

_SSL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"

_SSL_DEFAULT_TARGETS=(
  "commands/worktask.md::## Phase 1: Planning"
  "skills/worktask/references/initialization-patterns.md::## PL0 state.json Initialization"
  "skills/worktask/references/handoff-protocol.md::### PL0 seed (initial state)"
  "skills/megatask/SKILL.md::### Seeding a track's PL"
)

# Byte-oriented on purpose (LC_ALL=C at the call site); the prefix arrives via ENVIRON
# because -v would expand backslash escapes in it.
# shellcheck disable=SC2016 # awk program: $0 and friends belong to awk
_SSL_AWK='
function hashes(s,   n) { n = 0; while (substr(s, n + 1, 1) == "#") n++; return n }
function is_heading(s,   n, c) {
  n = hashes(s)
  if (n < 1 || n > 6) return 0
  c = substr(s, n + 1, 1)
  return c == " " || c == "\t" || c == ""
}
function ltrim(s) { sub(/^[ \t]+/, "", s); return s }
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function report(ln, rule, msg) {
  printf "%s:%d: rule-%s: %s\n", path, ln, rule, msg
  nviol++
}
function fence_open(s,   sp, ch, n, rest, i) {
  sp = 0
  while (sp < 4 && substr(s, sp + 1, 1) == " ") sp++
  if (sp > 3) return 0
  ch = substr(s, sp + 1, 1)
  if (ch != "`" && ch != "~") return 0
  n = 0
  while (substr(s, sp + n + 1, 1) == ch) n++
  if (n < 3) return 0
  rest = trim(substr(s, sp + n + 1))
  i = index(rest, " "); if (i) rest = substr(rest, 1, i - 1)
  i = index(rest, "\t"); if (i) rest = substr(rest, 1, i - 1)
  fch = ch; flen = n; finfo = rest
  return 1
}
function fence_close(s,   sp, n) {
  sp = 0
  while (sp < 4 && substr(s, sp + 1, 1) == " ") sp++
  if (sp > 3) return 0
  n = 0
  while (substr(s, sp + n + 1, 1) == fch) n++
  if (n < flen) return 0
  return trim(substr(s, sp + n + 1)) == ""
}
function open_in_section(ln) {
  open_ln = ln; kind = "other"; shellish = 0; cont = 0
  if (finfo == "bash") kind = "bash"
  else if (finfo == "") kind = "bare"
  else if (finfo ~ shlabelre) report(ln, "b", "fence labelled " finfo " holds shell; label it bash")
}
function bare_line(s,   t) {
  t = trim(s)
  if (t == "" || substr(t, 1, 1) == "#") return
  if (t ~ shre || substr(t, 1, 2) == ". " || t ~ asgre || t ~ dotshre) shellish = 1
}
function bash_line(s,   t, was) {
  was = cont
  cont = (s ~ /\\$/)
  if (was) return
  t = trim(s)
  if (t == "" || substr(t, 1, 1) == "#") return
  scan(t)
}
function first_word(s,   i, n, c, sq, dq) {
  n = length(s); sq = 0; dq = 0
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (sq) { if (c == q) sq = 0; continue }
    if (c == "\\") { i++; continue }
    if (dq) { if (c == "\"") dq = 0; continue }
    if (c == q) { sq = 1; continue }
    if (c == "\"") { dq = 1; continue }
    if (c == " " || c == "\t") break
  }
  return substr(s, 1, i - 1)
}
function check(seg,   w, u, c) {
  while (1) {
    seg = ltrim(seg)
    if (seg == "") return
    c = substr(seg, 1, 1)
    if (c == "(" || c == "{" || c == "!") { seg = substr(seg, 2); continue }
    w = first_word(seg)
    if (w ~ kwre || w ~ asgre) { seg = substr(seg, length(w) + 1); continue }
    break
  }
  u = w
  gsub(/"/, "", u)
  gsub(q, "", u)
  if (u ~ /[.]sh$/) report(NR, "c", "bare " u " run; invoke it as bash " u)
}
# Quote-aware split on ; && || | $( ) and backticks; a $( inside double quotes starts a
# fresh unquoted context that its ) restores.
function scan(t,   i, n, c, c2, seg, sq, dq, depth) {
  n = length(t); seg = ""; sq = 0; dq = 0; depth = 0
  for (i = 1; i <= n; i++) {
    c = substr(t, i, 1); c2 = substr(t, i, 2)
    if (sq) { if (c == q) sq = 0; seg = seg c; continue }
    if (c == "\\") { seg = seg c2; i++; continue }
    if (c2 == "$(") { check(seg); seg = ""; dstack[++depth] = dq; dq = 0; i++; continue }
    if (c == "`") { check(seg); seg = ""; continue }
    if (dq) { if (c == "\"") dq = 0; seg = seg c; continue }
    if (c == q) { sq = 1; seg = seg c; continue }
    if (c == "\"") { dq = 1; seg = seg c; continue }
    if (c == "#" && (i == 1 || substr(t, i - 1, 1) == " " || substr(t, i - 1, 1) == "\t")) break
    if (c == "(") { dstack[++depth] = 0; seg = seg c; continue }
    if (c == ")") { check(seg); seg = ""; if (depth > 0) { dq = dstack[depth]; depth-- } continue }
    if (c2 == "&&" || c2 == "||") { check(seg); seg = ""; i++; continue }
    if (c == ";" || c == "|") { check(seg); seg = ""; continue }
    seg = seg c
  }
  check(seg)
}
BEGIN {
  prefix = ENVIRON["SSL_PREFIX"]; path = ENVIRON["SSL_PATH"]; label = path "::" prefix
  q = sprintf("%c", 39)
  shlabelre = "^(sh|shell|zsh|console|shell-session)$"
  shre = "^(bash|sh|zsh|jq|git|gh|mkdir|cd|export|source|set|if|for|while)( |$)"
  asgre = "^[A-Za-z_][A-Za-z0-9_]*="
  dotshre = "[.]sh([ \"" q "]|$)"
  kwre = "^(if|then|else|elif|do|while|until|time|exec|command|nohup|env)$"
  state = 0; infence = 0; nviol = 0; open_ln = 0
}
{
  line = $0
  sub(/\r$/, "", line)
  if (state == 0) {
    if (infence) { if (fence_close(line)) infence = 0; next }
    if (fence_open(line)) { infence = 1; next }
    if (index(line, prefix) == 1) { state = 1; level = hashes(line); prevblank = 0; inblock = 0 }
    next
  }
  if (infence) {
    if (fence_close(line)) {
      if (kind == "bare" && shellish) report(open_ln, "b", "unlabelled fence holds shell; label it bash")
      infence = 0; prevblank = 0; inblock = 0
      next
    }
    if (kind == "bash") bash_line(line)
    else if (kind == "bare") bare_line(line)
    next
  }
  if (fence_open(line)) { infence = 1; open_in_section(NR); prevblank = 0; inblock = 0; next }
  if (is_heading(line) && hashes(line) <= level) { state = 2; exit }
  if (line ~ /^[ \t]*$/) { prevblank = 1; next }
  if (line ~ /^(    |\t)/) {
    if (prevblank && !inblock) { report(NR, "a", "indented code block; use a bash fence"); inblock = 1 }
    prevblank = 0
    next
  }
  prevblank = 0; inblock = 0
}
END {
  if (state == 0) {
    print "snippet-shell-lint: " label ": heading not found" | "cat 1>&2"
    close("cat 1>&2")
    exit 2
  }
  if (infence) {
    print "snippet-shell-lint: " label ": unterminated fence opened at line " open_ln | "cat 1>&2"
    close("cat 1>&2")
    exit 2
  }
  if (nviol > 0) {
    printf "snippet-shell-lint: %s: %d violation(s)\n", label, nviol
    exit 1
  }
  printf "snippet-shell-lint: %s: ok\n", label
  exit 0
}
'

usage() {
  local t
  sed -n '2,/^[^#]/s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"
  printf '\nDefault targets:\n'
  for t in "${_SSL_DEFAULT_TARGETS[@]}"; do
    printf '  %s\n' "$t"
  done
}

err() {
  printf >&2 'snippet-shell-lint: %s\n' "$1"
}

usage_error() {
  err "$1 (see --help)"
  exit 2
}

lint_target() {
  local spec=$1 path prefix file rc=0
  case $spec in
    *::*) ;;
    *)
      err "target must be <path>::<heading prefix>: $spec"
      return 2
      ;;
  esac
  path=${spec%%::*}
  prefix=${spec#*::}
  if [ -z "$path" ] || [ -z "$prefix" ]; then
    err "target has an empty path or heading prefix: $spec"
    return 2
  fi
  case $path in
    /*) file=$path ;;
    *) file="$_SSL_ROOT/$path" ;;
  esac
  if [ ! -f "$file" ] || [ ! -r "$file" ]; then
    err "$path: cannot read $file"
    return 2
  fi
  SSL_PATH=$path SSL_PREFIX=$prefix LC_ALL=C awk "$_SSL_AWK" "$file" || rc=$?
  case $rc in
    0 | 1) return "$rc" ;;
  esac
  return 2
}

main() {
  local n=0 i=0 rc worst=0
  local -a targets=()

  if [ "${1:-}" = "--self-test" ]; then
    [ $# -eq 1 ] || usage_error "--self-test takes no other arguments"
    local lib
    lib="$(dirname "${BASH_SOURCE[0]}")/snippet-shell-lint-selftest.sh"
    if [ ! -r "$lib" ]; then
      err "self-test harness unreadable at $lib"
      exit 2
    fi
    # shellcheck source-path=SCRIPTDIR source=snippet-shell-lint-selftest.sh
    . "$lib"
    if self_test; then
      exit 0
    fi
    exit 1
  fi

  while [ $# -gt 0 ]; do
    case $1 in
      -h | --help)
        usage
        exit 0
        ;;
      --target)
        [ $# -ge 2 ] || usage_error "missing value for --target"
        targets[n]=$2
        n=$((n + 1))
        shift 2
        ;;
      *) usage_error "unknown argument: $1" ;;
    esac
  done

  if [ "$n" -eq 0 ]; then
    targets=("${_SSL_DEFAULT_TARGETS[@]}")
    n=${#_SSL_DEFAULT_TARGETS[@]}
  fi

  while [ "$i" -lt "$n" ]; do
    rc=0
    lint_target "${targets[i]}" || rc=$?
    if [ "$rc" -eq 2 ]; then
      worst=2
    elif [ "$rc" -eq 1 ] && [ "$worst" -eq 0 ]; then
      worst=1
    fi
    i=$((i + 1))
  done
  exit "$worst"
}

main "$@"
