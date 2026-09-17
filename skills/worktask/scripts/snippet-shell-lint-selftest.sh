#!/usr/bin/env bash
# snippet-shell-lint-selftest.sh — the `--self-test` harness for snippet-shell-lint.sh.
#
# Sourced, never executed. Cases run the lint as a child so each exit code is observed
# directly; self_test runs inside an `if`, so every step checks its own status.
#
# Contract: defines `self_test`, returning 0 only when every case passes.

_SLT_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/snippet-shell-lint.sh"
_SLT_TD=""
_SLT_OUT=""
_SLT_RC=0
_SLT_FAILS=0

_slt_run() {
  _SLT_RC=0
  _SLT_OUT=$(bash "$_SLT_SCRIPT" "$@" 2> "$_SLT_TD/stderr") || _SLT_RC=$?
}

_slt_has() {
  case $_SLT_OUT in
    *"$1"*) return 0 ;;
  esac
  return 1
}

_slt_count() {
  printf '%s\n' "$_SLT_OUT" | grep -c -- ': rule-' || true
}

_slt_case() {
  if "$2"; then
    printf 'snippet-shell-lint self-test: ok   %s\n' "$1"
  else
    printf 'snippet-shell-lint self-test: FAIL %s (rc=%s)\n' "$1" "$_SLT_RC"
    _SLT_FAILS=$((_SLT_FAILS + 1))
  fi
}

# shellcheck disable=SC2016,SC1003 # fixtures are literal shell text, never expanded
_slt_fixtures() {
  local fence='```' tab
  tab=$(printf '\t')
  printf '%s\n' '## Target A' 'prose' '' '    indented.sh --flag' '    second' '' \
    '    same block' 'back to prose' '' "${tab}tab-indented.sh" > "$_SLT_TD/a.md"
  printf '%s\n' '## Target B' "${fence}sh" 'echo hi' "$fence" '' "$fence" 'git status' \
    "$fence" "${fence}json" '{"run": "x.sh"}' "$fence" > "$_SLT_TD/b.md"
  printf '%s\n' '## Target C' "${fence}bash" 'foo.sh --flag' 'if check.sh; then' \
    '  echo ok' 'fi' 'a || "$R/b.sh"' "$fence" > "$_SLT_TD/c.md"
  printf '%s\n' '# Doc' '## Target N' 'Prose line.' "   ${fence}bash" '   . lib.sh' \
    '   source lib.sh' '       indented body stays in the fence' '   X="$P/a.sh"' \
    '   out=$(bash a.sh)' '   V=1 bash a.sh' "   $fence" "${fence}json" '{"run": "x.sh"}' \
    "$fence" "${fence}bash" 'cmd --flag \' '  next.sh' 'echo "a; b.sh"' "$fence" \
    > "$_SLT_TD/n.md"
  printf '%s\n' "${fence}text" '## Target S' "$fence" '## Target S' "${fence}bash" \
    '## not a heading' "$fence" "${fence}bash" 'inside.sh' "$fence" '## Next' \
    "${fence}bash" 'after.sh' "$fence" > "$_SLT_TD/s.md"
  printf '%s\n' '## Target U' "${fence}bash" 'bash a.sh' > "$_SLT_TD/u.md"
}

_slt_rule_a() {
  _slt_run --target "$_SLT_TD/a.md::## Target A"
  [ "$_SLT_RC" -eq 1 ] && _slt_has "a.md:4: rule-a:" && _slt_has "a.md:10: rule-a:" \
    && [ "$(_slt_count)" -eq 2 ]
}

_slt_rule_b() {
  _slt_run --target "$_SLT_TD/b.md::## Target B"
  [ "$_SLT_RC" -eq 1 ] && _slt_has "b.md:2: rule-b:" && _slt_has "b.md:6: rule-b:" \
    && [ "$(_slt_count)" -eq 2 ]
}

_slt_rule_c() {
  _slt_run --target "$_SLT_TD/c.md::## Target C"
  [ "$_SLT_RC" -eq 1 ] && _slt_has "c.md:3: rule-c:" && _slt_has "c.md:4: rule-c:" \
    && _slt_has "c.md:7: rule-c:" && [ "$(_slt_count)" -eq 3 ]
}

_slt_negatives() {
  _slt_run --target "$_SLT_TD/n.md::## Target N"
  [ "$_SLT_RC" -eq 0 ] && _slt_has "n.md::## Target N: ok" && [ "$(_slt_count)" -eq 0 ]
}

_slt_boundary() {
  _slt_run --target "$_SLT_TD/s.md::## Target S"
  [ "$_SLT_RC" -eq 1 ] && _slt_has "s.md:9: rule-c:" && [ "$(_slt_count)" -eq 1 ]
}

_slt_errors() {
  _slt_run --target "$_SLT_TD/a.md::## No Such Heading"
  [ "$_SLT_RC" -eq 2 ] || return 1
  _slt_run --target "$_SLT_TD/missing.md::## Target A"
  [ "$_SLT_RC" -eq 2 ] || return 1
  _slt_run --target "$_SLT_TD/a.md"
  [ "$_SLT_RC" -eq 2 ] || return 1
  _slt_run --bogus
  [ "$_SLT_RC" -eq 2 ] || return 1
  _slt_run --target
  [ "$_SLT_RC" -eq 2 ] || return 1
  _slt_run --target "$_SLT_TD/u.md::## Target U"
  [ "$_SLT_RC" -eq 2 ]
}

self_test() {
  _SLT_TD=$(mktemp -d "${TMPDIR:-/tmp}/snippet-shell-lint.XXXXXX") || return 1
  trap 'rm -rf "$_SLT_TD"' EXIT
  _SLT_FAILS=0
  _slt_fixtures || return 1

  _slt_case "rule a: indented blocks, one report per block" _slt_rule_a
  _slt_case "rule b: shell label and unlabelled shell body" _slt_rule_b
  _slt_case "rule c: bare .sh runs in bash fences" _slt_rule_c
  _slt_case "negatives: sourcing, assignments, bash runs, json" _slt_negatives
  _slt_case "section boundary and fenced heading lookalikes" _slt_boundary
  _slt_case "errors exit 2" _slt_errors

  if [ "$_SLT_FAILS" -eq 0 ]; then
    printf 'snippet-shell-lint self-test: ALL PASS\n'
    return 0
  fi
  printf 'snippet-shell-lint self-test: %s case(s) failed\n' "$_SLT_FAILS"
  return 1
}
