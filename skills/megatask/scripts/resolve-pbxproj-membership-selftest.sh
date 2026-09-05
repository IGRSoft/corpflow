#!/usr/bin/env bash
# resolve-pbxproj-membership-selftest.sh — the `--self-test` harness for resolve-pbxproj-membership.sh.
#
# SOURCED, never executed: resolve-pbxproj-membership.sh loads this file only on the `--self-test`
# path, so the production path never pays for it. Sourcing leaves the caller's
# `$0` and every function it has already defined in scope — this file reads the
# caller's helpers and is not standalone.
#
# Contract: defines `self_test`, returning 0 when every fixture passes.

# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------
self_test() {
  require_tools

  local failures=0 pass_count=0 td
  td=$(mktemp -d -t resolve-pbxproj-selftest.XXXXXX)
  # shellcheck disable=SC2064
  trap "rm -rf '$td'; cleanup_tmp" EXIT
  local RESOLVE_TMPDIR="$td"
  export RESOLVE_TMPDIR

  st_pass() {
    pass_count=$((pass_count + 1))
    printf 'PASS: %s\n' "$1"
  }
  st_fail() {
    failures=$((failures + 1))
    printf 'FAIL: %s\n' "$1"
  }
  st_check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then st_pass "$desc"; else
      st_fail "$desc -- expected $(printf '%q' "$expected") got $(printf '%q' "$actual")"
    fi
  }

  # Fixture writers. Heredocs, not printf, so the conflict markers are literal.
  local clean="${td}/clean.pbxproj"
  cat > "$clean" << 'EOF'
		membershipExceptions = (
			Alpha.swift,
			Beta.swift,
		);
EOF

  local conflicted="${td}/conflicted.pbxproj"
  cat > "$conflicted" << 'EOF'
		membershipExceptions = (
<<<<<<< HEAD
			Beta.swift,
			Shared.swift,
=======
			Alpha.swift,
			Shared.swift,
>>>>>>> feature/x
		);
EOF

  # --- accept: sorted, deduplicated union -------------------------------
  local out rc
  out=$(run_resolve "$conflicted" 0 2>&1) && rc=0 || rc=$?
  st_check "accept: exit 0" "0" "$rc"
  if ! grep -q '<<<<<<<\|=======\|>>>>>>>' "$conflicted"; then
    st_pass "accept: no conflict markers remain"
  else
    st_fail "accept: markers still present"
  fi
  st_check "accept: sorted union body" \
    "$(printf '\t\t\tAlpha.swift,\n\t\t\tBeta.swift,\n\t\t\tShared.swift,')" \
    "$(sed -n '2,4p' "$conflicted")"
  st_check "accept: shared entry appears once" "1" \
    "$(grep -c 'Shared.swift' "$conflicted")"
  st_check "accept: list structure preserved" "		);" "$(sed -n '5p' "$conflicted")"

  # --- the target's mode survives the write -------------------------------
  local moded="${td}/moded.pbxproj"
  cat > "$moded" << 'EOF'
		membershipExceptions = (
<<<<<<< HEAD
			Beta.swift,
=======
			Alpha.swift,
>>>>>>> feature/x
		);
EOF
  chmod 640 "$moded"

  # Platform guard: a stat probe that prints to stdout while failing (GNU `-f`
  # given a format) yields a multi-line or non-numeric token, which chmod then
  # rejects. Assert the token's shape so that break is local, not Linux-only.
  local probe
  probe=$(stat -f%Lp "$moded" 2> /dev/null || stat -c%a "$moded" 2> /dev/null || printf '644')
  if [[ "$probe" =~ ^[0-7]+$ ]] && [[ "$(printf '%s' "$probe" | wc -l | tr -d ' ')" == "0" ]]; then
    st_pass "mode probe yields a single numeric token"
  else
    st_fail "mode probe yields an unusable token: $(printf '%q' "$probe")"
  fi

  run_resolve "$moded" 0 > /dev/null
  st_check "accept: file mode preserved" "640" \
    "$(stat -f%Lp "$moded" 2> /dev/null || stat -c%a "$moded" 2> /dev/null || printf '?')"

  # --- no-conflict input is a no-op --------------------------------------
  local before after
  before=$(cksum < "$clean")
  out=$(run_resolve "$clean" 0)
  after=$(cksum < "$clean")
  st_check "no-op: file byte-identical" "$before" "$after"
  case "$out" in
    *"no conflict found"*) st_pass "no-op: reports nothing to do" ;;
    *) st_fail "no-op: unexpected output: $out" ;;
  esac

  # --- dry-run writes nothing --------------------------------------------
  local dryfix="${td}/dry.pbxproj"
  cat > "$dryfix" << 'EOF'
		membershipExceptions = (
<<<<<<< HEAD
			Beta.swift,
=======
			Alpha.swift,
>>>>>>> feature/x
		);
EOF
  before=$(cksum < "$dryfix")
  out=$(run_resolve "$dryfix" 1 2> /dev/null)
  after=$(cksum < "$dryfix")
  st_check "dry-run: file untouched" "$before" "$after"
  case "$out" in
    *Alpha.swift*Beta.swift*) st_pass "dry-run: prints the resolved result" ;;
    *) st_fail "dry-run: result not printed" ;;
  esac

  # --- refusals: each leaves the file byte-identical ----------------------
  st_refuse() {
    local desc="$1" fixture="$2" want="$3" b a rc msg
    b=$(cksum < "$fixture")
    # `&& … || …` keeps the ERR trap quiet: a refusal here is the expected
    # outcome, and the trap's diagnostic would read like a self-test failure.
    msg=$(run_resolve "$fixture" 0 2>&1) && rc=0 || rc=$?
    a=$(cksum < "$fixture")
    if [[ "$rc" -eq 1 ]]; then st_pass "$desc: exit 1"; else st_fail "$desc: exit $rc"; fi
    case "$msg" in
      *"refusing: ${want}"*) st_pass "$desc: reason '$want'" ;;
      *) st_fail "$desc: wrong reason: $msg" ;;
    esac
    st_check "$desc: file byte-identical" "$b" "$a"
  }

  local outside="${td}/outside.pbxproj"
  cat > "$outside" << 'EOF'
		buildSettings = {
<<<<<<< HEAD
			SWIFT_VERSION = 6.0;
=======
			SWIFT_VERSION = 5.9;
>>>>>>> feature/x
		};
EOF
  st_refuse "outside" "$outside" "conflict outside membershipExceptions"

  local diff3="${td}/diff3.pbxproj"
  cat > "$diff3" << 'EOF'
		membershipExceptions = (
<<<<<<< HEAD
			Beta.swift,
||||||| base
			Gamma.swift,
=======
			Alpha.swift,
>>>>>>> feature/x
		);
EOF
  st_refuse "diff3" "$diff3" "diff3 base section present"

  local commented="${td}/commented.pbxproj"
  cat > "$commented" << 'EOF'
		membershipExceptions = (
<<<<<<< HEAD
			/* added by #12 */
			Beta.swift,
=======
			Alpha.swift,
>>>>>>> feature/x
		);
EOF
  st_refuse "comment" "$commented" "non-entry line in conflict side"

  # A single-line `membershipExceptions = ( );` must not latch in_list on, or a
  # later conflict in an unrelated ( ) list would be accepted as in-class.
  local latch="${td}/latch.pbxproj"
  cat > "$latch" << 'EOF'
		membershipExceptions = ( );
		children = (
<<<<<<< HEAD
			Beta.swift,
=======
			Alpha.swift,
>>>>>>> feature/x
		);
EOF
  st_refuse "single-line list" "$latch" "conflict outside membershipExceptions"

  local nested="${td}/nested.pbxproj"
  cat > "$nested" << 'EOF'
		membershipExceptions = (
<<<<<<< HEAD
			Beta.swift,
<<<<<<< HEAD
			Gamma.swift,
=======
			Alpha.swift,
>>>>>>> feature/x
		);
EOF
  st_refuse "nested" "$nested" "nested conflict start"

  local unterminated="${td}/unterminated.pbxproj"
  cat > "$unterminated" << 'EOF'
		membershipExceptions = (
<<<<<<< HEAD
			Beta.swift,
=======
			Alpha.swift,
EOF
  st_refuse "unterminated" "$unterminated" "unterminated conflict"

  local spanning="${td}/spanning.pbxproj"
  cat > "$spanning" << 'EOF'
		membershipExceptions = (
<<<<<<< HEAD
			Beta.swift,
		);
=======
			Alpha.swift,
		);
>>>>>>> feature/x
EOF
  st_refuse "spanning" "$spanning" "list close inside conflict"

  # All-or-nothing: one in-class conflict plus one out-of-class refuses both.
  local mixed="${td}/mixed.pbxproj"
  cat > "$mixed" << 'EOF'
		membershipExceptions = (
<<<<<<< HEAD
			Beta.swift,
=======
			Alpha.swift,
>>>>>>> feature/x
		);
		buildSettings = {
<<<<<<< HEAD
			SWIFT_VERSION = 6.0;
=======
			SWIFT_VERSION = 5.9;
>>>>>>> feature/x
		};
EOF
  st_refuse "all-or-nothing" "$mixed" "conflict outside membershipExceptions"

  trap - EXIT
  rm -rf "$td"

  if [[ "$failures" -eq 0 ]]; then
    printf 'resolve-pbxproj-membership: self-test OK (%d checks passed)\n' "$pass_count"
    return 0
  else
    printf 'resolve-pbxproj-membership: self-test FAILED (%d/%d checks failed)\n' \
      "$failures" "$((failures + pass_count))"
    return 1
  fi
}
