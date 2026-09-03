#!/usr/bin/env bats
# Contract test for skills/shared/plugin-root-resolution.md — freezes the
# CLAUDE_PLUGIN_ROOT reference grammar so provider-agnostic paths cannot
# silently regress:
#   - markdown may compose a path after the closing brace ONLY to spell a
#     CC-native hook command (hooks/<name>.sh), and only where that is either a
#     `command:` declaration or a backticked verbatim quote of one;
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
# falsifiable: two of them plant a violation and require it to be named.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

# True when every composed occurrence on $1 is a legal hook-command reference.
_composed_token_line_ok() {
  local line="$1" rest="$line" seg path
  # (1) every composed occurrence must spell hooks/<name>.sh
  while [ "$rest" != "${rest#*\$\{CLAUDE_PLUGIN_ROOT\}/}" ]; do
    rest="${rest#*\$\{CLAUDE_PLUGIN_ROOT\}/}"
    seg="$rest"
    path="${seg%%[\` \",\)\;]*}"
    case "$path" in
      hooks/*.sh) ;;
      *) return 1 ;;
    esac
  done
  # (2) and it must sit in CC-native config or a verbatim quote of it
  case "$line" in
    *command:\ *)                    return 0 ;;
    *'"command":'*)                  return 0 ;;
    *'`${CLAUDE_PLUGIN_ROOT}/'*)     return 0 ;;
    *'"${CLAUDE_PLUGIN_ROOT}/'*)     return 0 ;;
  esac
  return 1
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

@test "contract: every composed markdown token spells a hook command path" {
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

@test "contract: scripts reading the env var are the 5 known env-first fallbacks" {
  # The benchmark runner is excluded because it sets the variable for dispatched
  # stages rather than resolving from it; the test below pins that role.
  run bash -c 'cd "$PLUGIN_ROOT" && git ls-files -z -- "*.sh" \
    | xargs -0 grep -l "CLAUDE_PLUGIN_ROOT" 2>/dev/null \
    | grep -v "^benchmark/run-benchmark.sh$" | LC_ALL=C sort; true'
  assert_output "hooks/anchor-preflight.sh
hooks/state-merge.sh
skills/dv-screenshot-capture/scripts/apple-canvas.sh
skills/self-improvement/scripts/build-context-set.sh
skills/worktask/scripts/hook-install.sh"
}

@test "contract: the benchmark runner exports the env var instead of resolving from it" {
  # Unset, dispatched stages scan the filesystem for the plugin root, which distorts
  # both the behaviour under test and its measured cost.
  run bash -c 'cd "$PLUGIN_ROOT" && grep -c "^export CLAUDE_PLUGIN_ROOT=" benchmark/run-benchmark.sh'
  assert_output "1"
}
