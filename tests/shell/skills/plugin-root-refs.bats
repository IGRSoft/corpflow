#!/usr/bin/env bats
# Contract test for skills/shared/plugin-root-resolution.md — freezes the
# CLAUDE_PLUGIN_ROOT reference grammar so provider-agnostic paths cannot
# silently regress:
#   - markdown may compose a path after the closing brace only under arm H (a
#     CC-native hook command, hooks/<name>.sh, in a `command:` declaration or a
#     backticked verbatim quote of one) or arm S (a granted script path,
#     skills/<skill>/scripts/<name>.sh|.py, in the grant or invocation shape
#     § Granted-script invocation shape describes) — each occurrence judged on
#     its own, so one line can mix a legal and an illegal composition;
#   - the shell default-value form (colon-dash) is script-only;
#   - scripts reading the env var must be the known env-first fallbacks.
# Scope: tracked files only (git ls-files) — .context/ runtime artifacts and
# untracked scratch are exempt; plugin.json is JSON, outside the .md glob.
#
# The grammar is expressed as a predicate over each composed occurrence rather
# than as a frozen file list or a frozen `wc -l`. Both of those forms went red on
# any doc edit — adding a paragraph, a doc file or an agent broke them without
# any regression in the property they claimed to protect. The fixture tests below
# drive the same checker the repo test drives, so the checker itself is
# falsifiable: several of them plant a violation and require it to be named.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

GRANT_LINT="skills/shared/scripts/grant-lint.sh"
# Sourced once, at file scope, so arm S's path rule is defined exactly here — never
# re-derived — matching plugin-root-resolution.md's "that rule is defined once" claim.
# shellcheck source=skills/shared/scripts/grant-lint.sh
. "$PLUGIN_ROOT/$GRANT_LINT"

# _arm_h_path_ok <path> — arm H's path shape: a bundled hook script.
_arm_h_path_ok() {
  case "$1" in
    hooks/*.sh) return 0 ;;
    *) return 1 ;;
  esac
}

# _arm_h_line_ok <line> — arm H's line-level gate (unchanged): the composition must sit
# in CC-native config or a verbatim backtick/quote of one.
_arm_h_line_ok() {
  case "$1" in
    *command:\ *)                return 0 ;;
    *'"command":'*)              return 0 ;;
    *'`${CLAUDE_PLUGIN_ROOT}/'*) return 0 ;;
    *'"${CLAUDE_PLUGIN_ROOT}/'*) return 0 ;;
  esac
  return 1
}

# _arm_s_grant_ok <before> <after> <path> — the anchored grant shape: token immediately after
# `Bash(bash ` / `Bash(python3 `, immediately before ` *)`.
_arm_s_grant_ok() {
  local before="$1" after="$2" path="$3" interp
  case "$before" in
    *'Bash(bash ') interp=bash ;;
    *'Bash(python3 ') interp=python3 ;;
    *) return 1 ;;
  esac
  case "$after" in
    ' *)'*) : ;;
    *) return 1 ;;
  esac
  case "$interp:$path" in
    bash:*.sh | python3:*.py) return 0 ;;
    *) return 1 ;;
  esac
}

# _arm_s_invocation_ok <before> <path> — the anchored invocation shape: token immediately after
# `bash ` / `python3 ` sitting at line start or right after a backtick, a space, `(` or
# `$(` (the trailing `(` of `$(` is what the `*'('` arm below actually matches on) — never
# after `"`.
_arm_s_invocation_ok() {
  local before="$1" path="$2" interp head
  case "$before" in
    *'bash ') interp=bash; head="${before%bash }" ;;
    *'python3 ') interp=python3; head="${before%python3 }" ;;
    *) return 1 ;;
  esac
  case "$head" in
    '' | *'`' | *' ' | *'(') : ;;
    *) return 1 ;;
  esac
  case "$interp:$path" in
    bash:*.sh | python3:*.py) return 0 ;;
    *) return 1 ;;
  esac
}

# _arm_s_occurrence_ok <before> <path> <after> — arm S: a well-formed grant-lint script
# path AND (the grant shape OR the invocation shape). Judged per occurrence, independent
# of every other composition on the same line.
_arm_s_occurrence_ok() {
  local before="$1" path="$2" after="$3"
  corpflow_grant_script_path_ok "$path" || return 1
  _arm_s_grant_ok "$before" "$after" "$path" && return 0
  _arm_s_invocation_ok "$before" "$path"
}

# True when every composed occurrence on $1 is legal under arm H or arm S. A hook-path
# occurrence still needs arm H's line-level gate (checked once, after the walk, exactly as
# before); an arm-S occurrence certifies itself and never touches that gate.
_composed_token_line_ok() {
  local line="$1" prefix="" rest="$1" seg path tail head saw_hook=0
  while [ "$rest" != "${rest#*\$\{CLAUDE_PLUGIN_ROOT\}/}" ]; do
    head="$prefix${rest%%\$\{CLAUDE_PLUGIN_ROOT\}/*}"
    rest="${rest#*\$\{CLAUDE_PLUGIN_ROOT\}/}"
    seg="$rest"
    path="${seg%%[\` \",\)\;]*}"
    tail="${seg#"$path"}"
    if _arm_h_path_ok "$path"; then
      saw_hook=1
    elif _arm_s_occurrence_ok "$head" "$path" "$tail"; then
      :
    else
      return 1
    fi
    prefix="$head"'${CLAUDE_PLUGIN_ROOT}/'"$path"
  done
  if [ "$saw_hook" -eq 1 ]; then
    _arm_h_line_ok "$line" || return 1
  fi
  return 0
}

# Prints `path:lineno: <line>` for every illegal composed occurrence under $1.
_composed_token_violations() {
  local root="$1" f line n
  ( cd "$root" && git ls-files -z -- '*.md' 2>/dev/null ) \
  | while IFS= read -r -d '' f; do
      # git ls-files reports the INDEX, not the working tree: a tracked file
      # deleted locally is still listed while absent from disk, and the redirect
      # below would abort the whole walk on it. Whether a deletion is staged is
      # not this checker's business, so skip and keep walking.
      [ -f "$root/$f" ] || continue
      n=0
      while IFS= read -r line || [ -n "$line" ]; do
        n=$((n + 1))
        case "$line" in *'${CLAUDE_PLUGIN_ROOT}/'*) ;; *) continue ;; esac
        _composed_token_line_ok "$line" \
          || printf '%s:%s: %s\n' "$f" "$n" "$line"
      done < "$root/$f"
    done
}

# Counts the tracked *.md actually readable under $1 — i.e. what the walk above
# really visits after the skip guard.
_composed_token_visited() {
  local root="$1" f c=0
  while IFS= read -r -d '' f; do
    [ -f "$root/$f" ] && c=$((c + 1))
  done < <( cd "$root" && git ls-files -z -- '*.md' 2>/dev/null )
  printf '%s\n' "$c"
}

# Exit 1 (naming each offender) when the tree under $1 violates the grammar.
composed_token_check() {
  local out visited
  # Non-vacuity: the skip guard can only ever shrink the file list, so without
  # this an empty walk would satisfy the contract by inspecting nothing.
  visited="$(_composed_token_visited "$1")"
  if [ "${visited:-0}" -lt 1 ]; then
    printf 'composed-token walk visited 0 readable markdown files under %s\n' "$1"
    return 1
  fi
  out="$(_composed_token_violations "$1")"
  if [ -n "$out" ]; then
    printf '%s\n' "$out"
    return 1
  fi
  return 0
}

@test "contract: every composed markdown token satisfies arm H or arm S" {
  run composed_token_check "$PLUGIN_ROOT"
  assert_success
  assert_output ""
}

@test "contract: the CC-native hook wiring the grammar exists for is present" {
  # Positive-presence guard: the grammar must not pass a tree that has quietly
  # dropped every hook declaration it was written to permit.
  run bash -c 'cd "$PLUGIN_ROOT" && git ls-files -z -- "*.md" \
    | xargs -0 grep -c "command: \${CLAUDE_PLUGIN_ROOT}/hooks/agent-stop.sh" 2>/dev/null \
    | grep -vc ":0$"'
  assert_success
  [ "${output}" -ge 1 ]
}

@test "checker: a composed non-hook path in prose is reported with file and line" {
  local repo
  repo="$(mk_git_fixture \
    --file 'docs/ok.md:# ok\n\nNo tokens here.\n' \
    --file 'docs/bad.md:# bad\n\nSee ${CLAUDE_PLUGIN_ROOT}/skills/shared/x.md for detail.\n')"
  run composed_token_check "$repo"
  assert_failure
  assert_output --partial "docs/bad.md:3:"
  refute_output --partial "docs/ok.md"
}

@test "checker: a bare hook path outside config or a quote is reported" {
  local repo
  repo="$(mk_git_fixture \
    --file 'docs/bare.md:Run ${CLAUDE_PLUGIN_ROOT}/hooks/agent-stop.sh after each stage.\n')"
  run composed_token_check "$repo"
  assert_failure
  assert_output --partial "docs/bare.md:1:"
}

@test "checker: a NEW agent file declaring a frontmatter hook stays clean" {
  # Direct replacement for the deleted frozen whitelist: growth in the number of
  # files carrying a legal token must not turn the contract red.
  local repo
  repo="$(mk_git_fixture \
    --file 'agents/new-agent.md:---\nhooks:\n  Stop:\n    - type: command\n      command: ${CLAUDE_PLUGIN_ROOT}/hooks/agent-stop.sh\n---\n\nBody.\n')"
  run composed_token_check "$repo"
  assert_success
  assert_output ""
}

@test "checker: added documentation lines quoting hook config stay clean" {
  # Direct replacement for the deleted `wc -l` freeze at 5: the occurrence count
  # is not part of the contract, so three quoted references pass just as one did.
  local repo
  repo="$(mk_git_fixture \
    --file 'docs/handoff.md:The PostToolUse entry invokes `${CLAUDE_PLUGIN_ROOT}/hooks/anchor-preflight.sh`.\n\n    { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/anchor-preflight.sh" }\n\nThe Stop entry invokes `${CLAUDE_PLUGIN_ROOT}/hooks/agent-stop.sh`.\n')"
  run composed_token_check "$repo"
  assert_success
  assert_output ""
}

@test "checker: a tracked-but-locally-deleted .md is skipped, not fatal" {
  # Regression: git ls-files lists the index, so an UNSTAGED deletion leaves a
  # path listed but absent from disk and the reader died on it — turning the
  # contract red for anyone with a locally deleted tracked .md, and going green
  # again the moment the deletion was staged. The violation in the surviving
  # sibling must still be reported, proving the guard skipped one file rather
  # than aborting the walk.
  local repo
  repo="$(mk_git_fixture \
    --file 'docs/gone.md:# placeholder\n' \
    --file 'docs/bad.md:See ${CLAUDE_PLUGIN_ROOT}/skills/shared/x.md for detail.\n')"
  rm "$repo/docs/gone.md"
  run composed_token_check "$repo"
  assert_failure
  assert_output --partial "docs/bad.md:1:"
  refute_output --partial "No such file or directory"
}

@test "checker: a clean tree with a locally deleted .md still passes" {
  # The other direction of the same guard: skipping must not manufacture a
  # violation, and the walk must still visit the surviving file.
  local repo
  repo="$(mk_git_fixture \
    --file 'docs/gone.md:# placeholder\n' \
    --file 'agents/a.md:---\nhooks:\n  Stop:\n    - type: command\n      command: ${CLAUDE_PLUGIN_ROOT}/hooks/agent-stop.sh\n---\n')"
  rm "$repo/docs/gone.md"
  run composed_token_check "$repo"
  assert_success
  assert_output ""
}

@test "checker: arm S — a legal frontmatter grant composition stays clean" {
  local repo
  repo="$(mk_git_fixture \
    --file 'agents/a.md:---\ntools: Read, Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/x.sh *)\n---\n\nBody.\n')"
  run composed_token_check "$repo"
  assert_success
  assert_output ""
}

@test "checker: arm S — a legal backticked invocation composition stays clean" {
  local repo
  repo="$(mk_git_fixture \
    --file 'agents/a.md:---\ntools: Read, Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/x.sh *)\n---\n\nRun `bash ${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/x.sh --flag`.\n')"
  run composed_token_check "$repo"
  assert_success
  assert_output ""
}

@test "checker: arm S — a quoted script-path composition is reported" {
  local repo
  repo="$(mk_git_fixture \
    --file 'docs/quoted.md:HELPER="${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/x.sh"\n')"
  run composed_token_check "$repo"
  assert_failure
  assert_output --partial "docs/quoted.md:1:"
}

@test "checker: arm S — a composed references/ doc path is still illegal, not a script grant" {
  local repo
  repo="$(mk_git_fixture \
    --file 'docs/refs.md:See ${CLAUDE_PLUGIN_ROOT}/skills/shared/references/notes.md for detail.\n')"
  run composed_token_check "$repo"
  assert_failure
  assert_output --partial "docs/refs.md:1:"
}

@test "checker: a walk that visits no readable markdown fails instead of passing" {
  # Guards the guard: if every tracked .md vanished, the contract must not pass
  # by inspecting nothing.
  local repo
  repo="$(mk_git_fixture --file 'docs/only.md:# placeholder\n')"
  rm "$repo/docs/only.md"
  run composed_token_check "$repo"
  assert_failure
  assert_output --partial "visited 0 readable markdown files"
}

@test "contract: default-value (colon-dash) token form never appears in markdown" {
  run bash -c 'cd "$PLUGIN_ROOT" && git ls-files -z -- "*.md" \
    | xargs -0 grep -n "CLAUDE_PLUGIN_ROOT:-" 2>/dev/null; true'
  assert_output ""
}

# Files that only ever SET the variable for a child process, never resolve from
# it. `grep -l` cannot tell a write from a read, so they are carved out by name;
# the setter-only arm below is what keeps the carve-out honest.
_setter_only_files() {
  printf '%s\n' \
    'benchmark/run-benchmark.sh' \
    'skills/worktask/scripts/hook-install-selftest.sh'
}

# skills/shared/scripts/grant-lint.sh mentions the name once, as the literal single-quoted
# CORPFLOW_GRANT_TOKEN pattern arm S sources — never a `$`/`${` read of the environment
# variable (grant-lint.bats asserts this directly on that file). A plain-substring `grep -l`
# cannot tell a read from a pattern any more than it can tell a read from a write, so this
# is carved out the same way _setter_only_files is; without it arm S's new dependency would
# silently grow the exact-6 list below to 7.
_pattern_only_files() {
  printf '%s\n' 'skills/shared/scripts/grant-lint.sh'
}

# Prints every tracked *.sh that mentions the env var, minus the carve-outs.
_env_var_reader_files() {
  cd "$PLUGIN_ROOT" || return 1
  git ls-files -z -- '*.sh' \
    | xargs -0 grep -l 'CLAUDE_PLUGIN_ROOT' 2>/dev/null \
    | { grep -vxF "$(_setter_only_files)" || true; } \
    | { grep -vxF "$(_pattern_only_files)" || true; } \
    | LC_ALL=C sort
}

@test "contract: scripts reading the env var are the 6 known env-first fallbacks" {
  # The benchmark runner exports the variable for dispatched stages; the
  # hook-install harness passes it per invocation of the script under test.
  # cache-lint.sh joined the list when prefix mode gained the section [4b] canon
  # check, which has to read skills/shared/model-prompting.md from the plugin
  # root rather than from whatever directory the lint was invoked in.
  run _env_var_reader_files
  assert_output "hooks/anchor-preflight.sh
hooks/state-merge.sh
skills/dv-screenshot-capture/scripts/apple-canvas.sh
skills/self-improvement/scripts/build-context-set.sh
skills/worktask/scripts/cache-lint.sh
skills/worktask/scripts/hook-install.sh"
}

@test "contract: the benchmark runner exports the env var instead of resolving from it" {
  # Unset, dispatched stages scan the filesystem for the plugin root, which distorts
  # both the behaviour under test and its measured cost.
  run bash -c 'cd "$PLUGIN_ROOT" && grep -c "^export CLAUDE_PLUGIN_ROOT=" benchmark/run-benchmark.sh'
  assert_output "1"
}

@test "contract: the carved-out files stay setter-only and stay relevant" {
  # The carve-out is by filename, so without this either file could grow a real
  # env-first fallback and silently vanish from the list it then belongs on.
  # Also fails when a carve-out stops mentioning the variable at all, which
  # would leave a stale name masking a future reader at the same path.
  local f hits reads
  while IFS= read -r f; do
    [ -f "$PLUGIN_ROOT/$f" ] || fail "carved-out file is missing: $f"
    hits="$(grep -c 'CLAUDE_PLUGIN_ROOT' "$PLUGIN_ROOT/$f" || true)"
    [ "${hits:-0}" -ge 1 ] || fail "carve-out no longer mentions the variable: $f"
    # A read is any expansion of the name; an assignment or `export NAME=` is not.
    reads="$(grep -nE '\$\{?CLAUDE_PLUGIN_ROOT' "$PLUGIN_ROOT/$f" || true)"
    [ -z "$reads" ] || fail "carved-out file reads the variable: $f
$reads"
  done < <(_setter_only_files)
}

@test "contract: the pattern-only carve-out mentions the variable exactly once, as a literal" {
  # Guards the same failure mode as the setter-only guard above, from the other direction:
  # grant-lint.sh's header claims CORPFLOW_GRANT_TOKEN is its only spelling of the
  # placeholder (grant-lint.bats pins this on that file directly) — this re-checks it here,
  # which is the reason the carve-out is safe to keep off the reader list at all.
  local f hits
  while IFS= read -r f; do
    [ -f "$PLUGIN_ROOT/$f" ] || fail "carved-out file is missing: $f"
    hits="$(grep -c 'CLAUDE_PLUGIN_ROOT' "$PLUGIN_ROOT/$f" || true)"
    [ "${hits:-0}" -eq 1 ] \
      || fail "pattern-only carve-out's mention count changed (want exactly 1): $f has ${hits:-0}"
  done < <(_pattern_only_files)
}
