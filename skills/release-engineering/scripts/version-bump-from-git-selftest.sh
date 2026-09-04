#!/usr/bin/env bash
# version-bump-from-git-selftest.sh — the `--self-test` harness for version-bump-from-git.sh.
#
# SOURCED, never executed: version-bump-from-git.sh loads this file only on the `--self-test`
# path, so the production path never pays for it. Sourcing leaves the caller's
# `$0` and every function it has already defined in scope — this file reads the
# caller's helpers and is not standalone.
#
# Contract: defines `run_self_test`, returning 0 when every case passes.

# ---------------------------------------------------------------------------
# Self-test — temp git repo, no network, no external deps
# ---------------------------------------------------------------------------
run_self_test() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT

  # `$0`, not BASH_SOURCE: this file is sourced, so BASH_SOURCE[0] names the
  # harness, which has no entry point. `$0` is still the caller.
  local script="$0"
  local G=(git -C "$tmpdir")
  "${G[@]}" init -q
  "${G[@]}" config user.email "test@example.com"
  "${G[@]}" config user.name "Test"
  "${G[@]}" commit -q --allow-empty -m "chore: init"
  "${G[@]}" tag v0.0.0

  local fail=0

  # expect_bump <expected> <label> <args...>
  expect_bump() {
    local expected="$1" label="$2"
    shift 2
    local got
    got="$(bash "$script" "$@" 2> /dev/null)" || {
      printf >&2 'FAIL: %s — exited non-zero\n' "$label"
      fail=1
      return 0
    }
    if [[ "$got" != "$expected" ]]; then
      printf >&2 'FAIL: %s — expected %s, got %s\n' "$label" "$expected" "$got"
      fail=1
    fi
  }

  # from_subjects <expected> <label> <subject>...
  from_subjects() {
    local expected="$1" label="$2"
    shift 2
    local f="$tmpdir/subjects.$$.txt"
    printf '%s\n' "$@" > "$f"
    expect_bump "$expected" "$label" --file "$f"
    rm -f "$f"
  }

  # --- aggregation: highest severity wins, not last-commit-wins ---
  from_subjects minor "mixed 3x fix + 1x feat" \
    "fix: one" "fix: two" "feat: add thing" "fix: three"
  from_subjects patch "fix-only range" "fix: one" "fix: two"
  from_subjects none "silent types only" \
    "docs: readme" "chore: deps" "test: coverage" "ci: pipeline"
  from_subjects patch "refactor and perf are patch" \
    "refactor: tidy" "perf: cache"

  # --- breaking is independent of commit type ---
  from_subjects major "header ! on feat" "fix: one" "feat!: drop v1"
  from_subjects major "header ! on fix" "fix!: change return type"
  from_subjects none "non-conventional alone does not bump" \
    "Merge branch 'main'" "wip"

  # --- footer form, which needs a multi-line record ---
  local nulfile="$tmpdir/records.bin"
  printf 'chore: retire the shim\n\nBREAKING CHANGE: callers must migrate.\n\0' \
    > "$nulfile"
  expect_bump major "BREAKING CHANGE footer on chore" --file "$nulfile"

  printf 'feat: add thing\n\nbut this is a breaking change: not really\n\0' \
    > "$nulfile"
  expect_bump minor "lowercase prose is not a footer" --file "$nulfile"

  # --- git range: empty, single-commit, and mixed ---
  expect_bump none "empty range" "HEAD..HEAD" --repo "$tmpdir"

  "${G[@]}" commit -q --allow-empty -m "fix: single commit range"
  expect_bump patch "single-commit range" "v0.0.0..HEAD" --repo "$tmpdir"

  "${G[@]}" commit -q --allow-empty -m "feat(api): add endpoint"
  "${G[@]}" commit -q --allow-empty -m "docs: mention it"
  expect_bump minor "multi-commit range aggregates" "v0.0.0..HEAD" --repo "$tmpdir"

  "${G[@]}" commit -q --allow-empty \
    -m "chore: retire shim" -m "BREAKING CHANGE: callers must migrate."
  expect_bump major "footer via real git range" "v0.0.0..HEAD" --repo "$tmpdir"

  # --- the two scripts must agree on which commits are breaking ---
  local changelog cl_out
  changelog="$(dirname "$script")/changelog-from-git.sh"
  cl_out="$(bash "$changelog" "v0.0.0..HEAD" --repo "$tmpdir" 2> /dev/null)"
  if ! grep -q 'BREAKING' <<< "$cl_out"; then
    printf >&2 'FAIL: bump says major but changelog marked nothing BREAKING\n'
    fail=1
  fi

  # --- usage errors ---
  if bash "$script" > /dev/null 2>&1; then
    printf >&2 'FAIL: no range and no --file should exit 1\n'
    fail=1
  fi
  if bash "$script" --file "/tmp/does-not-exist-xy12" > /dev/null 2>&1; then
    printf >&2 'FAIL: unreadable --file should exit 1\n'
    fail=1
  fi

  rm -rf "$tmpdir"
  trap - EXIT

  if [[ "$fail" -eq 0 ]]; then
    printf 'self-test: PASS\n'
    exit 0
  fi
  printf >&2 'self-test: FAIL\n'
  exit 1
}
