#!/usr/bin/env bash
# changelog-from-git-selftest.sh — the `--self-test` harness for changelog-from-git.sh.
#
# SOURCED, never executed: changelog-from-git.sh loads this file only on the `--self-test`
# path, so the production path never pays for it. Sourcing leaves the caller's
# `$0` and every function it has already defined in scope — this file reads the
# caller's helpers and is not standalone.
#
# Contract: defines `run_self_test`, returning 0 when every case passes.

# ---------------------------------------------------------------------------
# Self-test — spins up a temp git repo, no network, no external deps
# ---------------------------------------------------------------------------
run_self_test() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  # Note: EXIT trap is registered by init_buckets; we add our own cleanup here
  # by nesting inside a subshell so the outer EXIT trap is not clobbered.
  # We use a flag + explicit cleanup instead.
  local test_cleanup_done=0
  trap '
    [[ "$test_cleanup_done" -eq 0 ]] && rm -rf "$tmpdir"
    test_cleanup_done=1
  ' EXIT

  # `$0`, not BASH_SOURCE: this file is sourced, so BASH_SOURCE[0] names the
  # harness, which has no entry point. `$0` is still the caller.
  local script="$0"

  # Init repo
  git -C "$tmpdir" init -q
  git -C "$tmpdir" config user.email "test@example.com"
  git -C "$tmpdir" config user.name "Test"

  # Base commit + tag to form the lower bound of our range
  git -C "$tmpdir" commit -q --allow-empty -m "chore: init"
  git -C "$tmpdir" tag v0.0.0

  # Seed all 10 conventional types + a breaking feat + a non-conventional commit
  git -C "$tmpdir" commit -q --allow-empty -m "feat(auth): add OAuth2 login"
  git -C "$tmpdir" commit -q --allow-empty -m "fix: resolve crash on empty input"
  git -C "$tmpdir" commit -q --allow-empty -m "docs: update README"
  git -C "$tmpdir" commit -q --allow-empty -m "style: reformat with prettier"
  git -C "$tmpdir" commit -q --allow-empty -m "refactor(api): extract helper module"
  git -C "$tmpdir" commit -q --allow-empty -m "perf: cache DB results"
  git -C "$tmpdir" commit -q --allow-empty -m "test: add unit tests for parser"
  git -C "$tmpdir" commit -q --allow-empty -m "chore: bump dependency versions"
  git -C "$tmpdir" commit -q --allow-empty -m "ci: update GitHub Actions workflow"
  git -C "$tmpdir" commit -q --allow-empty -m "build: switch to esbuild"
  git -C "$tmpdir" commit -q --allow-empty -m "feat!: remove legacy v1 endpoints"
  git -C "$tmpdir" commit -q --allow-empty \
    -m "fix: drop the compat shim" -m "BREAKING CHANGE: callers must migrate."
  git -C "$tmpdir" commit -q --allow-empty \
    -m "chore: retire the shim" -m "BREAKING CHANGE: callers must migrate."
  git -C "$tmpdir" commit -q --allow-empty -m "Non-conventional commit message"

  local fail=0

  # --- Test 1: standard range run via --repo ---
  local output
  output="$(bash "$script" "v0.0.0..HEAD" --repo "$tmpdir" --version "1.0.0" --date "2024-01-15" 2> /dev/null)"

  grep -q 'auth.*OAuth2 login' <<< "$output" || {
    printf >&2 'FAIL: feat(auth) not in Added\n'
    fail=1
  }
  grep -q 'BREAKING.*legacy v1 endpoints' <<< "$output" || {
    printf >&2 'FAIL: breaking feat! not marked BREAKING\n'
    fail=1
  }
  grep -q 'crash on empty input' <<< "$output" || {
    printf >&2 'FAIL: fix not in Fixed\n'
    fail=1
  }
  grep -q 'BREAKING.*drop the compat shim' <<< "$output" || {
    printf >&2 'FAIL: BREAKING CHANGE footer not marked BREAKING\n'
    fail=1
  }
  grep -q 'BREAKING.*retire the shim' <<< "$output" || {
    printf >&2 'FAIL: breaking commit of a silent type was suppressed\n'
    fail=1
  }
  grep -q 'extract helper module' <<< "$output" || {
    printf >&2 'FAIL: refactor not in Changed\n'
    fail=1
  }
  grep -q 'cache DB results' <<< "$output" || {
    printf >&2 'FAIL: perf not in Changed\n'
    fail=1
  }
  local suppressed
  for suppressed in "update README" "reformat with prettier" "add unit tests" \
    "bump dependency" "update GitHub Actions" "switch to esbuild"; do
    if grep -q "$suppressed" <<< "$output"; then
      printf >&2 'FAIL: suppressed type appeared in output: %s\n' "$suppressed"
      fail=1
    fi
  done
  grep -q 'Non-conventional commit message' <<< "$output" || {
    printf >&2 'FAIL: non-conventional commit dropped (should be Other)\n'
    fail=1
  }
  grep -q '\[1\.0\.0\].*2024-01-15' <<< "$output" || {
    printf >&2 'FAIL: version header not found\n'
    fail=1
  }

  # --- Test 2: empty range emits "no changelog-worthy" notice ---
  local empty_out
  empty_out="$(bash "$script" "HEAD..HEAD" --repo "$tmpdir" 2> /dev/null)"
  grep -q 'no changelog-worthy' <<< "$empty_out" || {
    printf >&2 'FAIL: empty range did not emit no-content notice\n'
    fail=1
  }

  # --- Test 3: --file bypasses git entirely; blank lines are skipped ---
  local subjects_file="$tmpdir/subjects.txt"
  printf '%s\n' "feat: from file entry" "   " "" "fix: also from file" > "$subjects_file"
  local file_out
  file_out="$(bash "$script" --file "$subjects_file" 2> /dev/null)"
  grep -q 'from file entry' <<< "$file_out" || {
    printf >&2 'FAIL: --file feat not in Added\n'
    fail=1
  }
  grep -q 'also from file' <<< "$file_out" || {
    printf >&2 'FAIL: --file fix not in Fixed\n'
    fail=1
  }

  # --- Test 4: uppercase type normalised; scope parentheses stripped ---
  local scope_file="$tmpdir/scope.txt"
  printf '%s\n' "FEAT(dashboard): uppercase type" > "$scope_file"
  local scope_out
  scope_out="$(bash "$script" --file "$scope_file" 2> /dev/null)"
  grep -q 'dashboard.*uppercase type' <<< "$scope_out" || {
    printf >&2 'FAIL: uppercase type or scope not handled\n'
    fail=1
  }

  test_cleanup_done=1
  rm -rf "$tmpdir"

  if [[ "$fail" -eq 0 ]]; then
    printf 'self-test: PASS\n'
    exit 0
  else
    printf >&2 'self-test: FAIL\n'
    exit 1
  fi
}
