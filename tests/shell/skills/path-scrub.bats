#!/usr/bin/env bats
# Contract tests for skills/shared/scripts/path-scrub.sh — the one host-path pattern
# and the token scrub that issue and PR bodies both run last.
#   - executable: stdin -> stdout, exit 0; usage error exit 2; --self-test exit 0
#   - sourced: defines corpflow_path_scrub and the two exported EREs, runs nothing
#   - roots rebase to repo-relative; every other host path becomes [local-path]
#   - root matching is literal; the scrub is idempotent
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/shared/scripts/path-scrub.sh"

setup() {
  WD="$(mk_tmpworkdir)"
  mkdir -p "$WD/outside" "$WD/wt/skills"
}

# <input-file> [VAR=value]... — runs outside any repository, so only the roots a
# test declares can rebase.
_exec() {
  local in="$1"
  shift
  (cd "$WD/outside" && env GIT_CEILING_DIRECTORIES="$WD" "$@" bash "$PLUGIN_ROOT/$SCRIPT" < "$in")
}

_sourced() {
  local in="$1"
  shift
  (cd "$WD/outside" && env GIT_CEILING_DIRECTORIES="$WD" "$@" \
    bash -c '. "$1"; corpflow_path_scrub' _ "$PLUGIN_ROOT/$SCRIPT" < "$in")
}

@test "--self-test passes" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_success
  assert_output --partial "0 failed"
}

@test "a host path becomes [local-path]; a root path and .context/ stay readable" {
  printf 'See /Users/me/notes.md and %s/skills/a.sh and .context/planning-0.md\n' "$WD/wt" > "$WD/in.md"
  run _exec "$WD/in.md" "WORKSPACE_ROOT=$WD/wt"
  assert_success
  assert_output "See [local-path] and skills/a.sh and .context/planning-0.md"
  refute_output --partial "/Users/"
  refute_output --partial "$WD"
}

@test "executing and sourcing produce identical bytes" {
  cat > "$WD/in.md" <<EOF
Glued (/Volumes/x/y), "/tmp/z", a=/srv/q and file:///Users/me/f.md
Root $WD/wt/skills/a.sh and bare $WD/wt
Keep https://example.com/tmp/x, skills/b.sh and /usr/bin/env
EOF
  local a b
  a="$(_exec "$WD/in.md" "WORKSPACE_ROOT=$WD/wt")"
  b="$(_sourced "$WD/in.md" "WORKSPACE_ROOT=$WD/wt")"
  [ -n "$a" ]
  [ "$a" = "$b" ] || fail "exec and sourced differ: [$a] vs [$b]"
}

@test "usage: an unknown flag or an extra argument exits 2; -h prints the header" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --bogus
  assert_failure 2
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test extra
  assert_failure 2
  run bash "$PLUGIN_ROOT/$SCRIPT" -h
  assert_success
  assert_output --partial "@exitcode 2"
}

@test "sourcing runs nothing: stdin untouched, caller options and IFS unchanged" {
  run bash -c '
    set -euo pipefail
    IFS=$'"'"'\n\t'"'"'
    before="$(set -o; printf "%q" "$IFS")"
    . "$1"
    after="$(set -o; printf "%q" "$IFS")"
    [ "$before" = "$after" ] || { echo "caller state changed"; exit 1; }
    [ "$(type -t corpflow_path_scrub)" = "function" ] || { echo "no function"; exit 1; }
    env | grep -q "^CORPFLOW_HOST_PATH_ERE=" || { echo "host ERE not exported"; exit 1; }
    env | grep -q "^CORPFLOW_DRIVE_PATH_ERE=" || { echo "drive ERE not exported"; exit 1; }
    cat
  ' _ "$PLUGIN_ROOT/$SCRIPT" <<< "untouched"
  assert_success
  assert_output "untouched"
}

@test "the function works under a strict caller with a newline-tab IFS" {
  printf 'Ref (/home/me/x) ok\n' > "$WD/in.md"
  run bash -c '
    set -euo pipefail
    IFS=$'"'"'\n\t'"'"'
    . "$1"
    corpflow_path_scrub < "$2"
  ' _ "$PLUGIN_ROOT/$SCRIPT" "$WD/in.md"
  assert_success
  assert_output "Ref ([local-path]) ok"
}

@test "an unset HOME still scrubs" {
  printf 'Ref /home/me/x and skills/b.sh\n' > "$WD/in.md"
  run bash -c 'cd "$1" && env -u HOME -u TMPDIR GIT_CEILING_DIRECTORIES="$2" bash "$3" < "$4"' \
    _ "$WD/outside" "$WD" "$PLUGIN_ROOT/$SCRIPT" "$WD/in.md"
  assert_success
  assert_output "Ref [local-path] and skills/b.sh"
}

@test "a root with regex metacharacters matches itself literally and nothing else" {
  local meta="$WD/a+b[1].c"
  mkdir -p "$meta"
  # Read as a regex, the root would also match aab1xc and rebase it to skills/x.sh.
  printf 'A %s/skills/x.sh B %s/aab1xc/skills/x.sh\n' "$meta" "$WD" > "$WD/in.md"
  run _exec "$WD/in.md" "WORKSPACE_ROOT=$meta"
  assert_success
  assert_output "A skills/x.sh B [local-path]"
  # Outside every mount the look-alike has nothing to match, so it stays verbatim.
  printf 'B /nonexistent-cf/aab1xc/skills/x.sh\n' > "$WD/in2.md"
  run _exec "$WD/in2.md" "WORKSPACE_ROOT=/nonexistent-cf/a+b[1].c"
  assert_success
  assert_output "B /nonexistent-cf/aab1xc/skills/x.sh"
}

@test "the git toplevel and the main worktree both rebase, logical and physical" {
  local repo wt phys
  repo="$(mk_git_fixture --dir "$WD/repo" --file 'a.txt:hi' --commit init)"
  wt="$WD/linked"
  git -C "$repo" -c user.name=t -c user.email=t@t worktree add -q "$wt" -b lb 2> /dev/null \
    || skip "git worktree unavailable"
  phys="$(cd "$repo" && pwd -P)"
  printf 'main %s/a.txt phys %s/a.txt own %s/b.txt\n' "$repo" "$phys" "$wt" > "$WD/in.md"
  run bash -c 'cd "$1" && GIT_CEILING_DIRECTORIES="$2" bash "$3" < "$4"' \
    _ "$wt" "$WD" "$PLUGIN_ROOT/$SCRIPT" "$WD/in.md"
  assert_success
  assert_output "main a.txt phys a.txt own b.txt"
}

@test "scrubbing is idempotent over a mixed corpus" {
  cat > "$WD/in.md" <<EOF
See /Users/me/notes.md, ($WD/wt/skills/a.sh) $WD/wt//Users/q $WD/wt/$WD/wt/x
file:///tmp/y \`C:\\x\` [/Volumes/v] https://h/tmp/z $WD/wt **/srv/bold**
EOF
  local once twice
  once="$(_exec "$WD/in.md" "WORKSPACE_ROOT=$WD/wt")"
  printf '%s\n' "$once" > "$WD/once.md"
  twice="$(_exec "$WD/once.md" "WORKSPACE_ROOT=$WD/wt")"
  [ "$once" = "$twice" ] || fail "second pass changed bytes: [$once] -> [$twice]"
  [[ "$once" != *"/Users/"* && "$once" != *"/Volumes/"* && "$once" != *"/srv/"* ]] \
    || fail "host path survived: $once"
}

@test "empty input yields empty output" {
  : > "$WD/in.md"
  run _exec "$WD/in.md"
  assert_success
  assert_output ""
}
