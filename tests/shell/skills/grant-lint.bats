#!/usr/bin/env bats
# Contract tests for skills/shared/scripts/grant-lint.sh — the checker for the
# anchored script-grant shape and, with --invocations, the runnable-mention rule.
# Sourced-mode assertions cover the three library functions directly (no subprocess);
# CLI-mode assertions run the script as a subprocess against synthetic git trees, so
# `mk_git_fixture` stands in for a real agent/command/skill tree.
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/shared/scripts/grant-lint.sh"

setup() {
  WD="$(mk_tmpworkdir)"
}

# --- sourcing: defines, runs nothing -----------------------------------------

@test "sourcing defines the three functions and CORPFLOW_GRANT_TOKEN, runs nothing" {
  run bash -c '. "$1"; type -t corpflow_grant_script_path_ok corpflow_grant_rule_ok corpflow_grant_matches; printf "%s\n" "$CORPFLOW_GRANT_TOKEN"' \
    _ "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  assert_line --index 0 "function"
  assert_line --index 1 "function"
  assert_line --index 2 "function"
  # shellcheck disable=SC2016
  assert_line --index 3 '${CLAUDE_PLUGIN_ROOT}'
}

@test "the literal token text appears exactly once in this file" {
  run bash -c "grep -c '\\\${CLAUDE_PLUGIN_ROOT}' \"\$1\"" _ "$PLUGIN_ROOT/$SCRIPT"
  assert_output "1"
}

# --- corpflow_grant_script_path_ok -------------------------------------------

@test "path predicate: a well-formed skills/.../scripts/name.sh or .py passes" {
  run bash -c '. "$1"; corpflow_grant_script_path_ok "skills/worktask/scripts/state-patch.sh"' \
    _ "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  run bash -c '. "$1"; corpflow_grant_script_path_ok "skills/self-improvement/scripts/append-labels.py"' \
    _ "$PLUGIN_ROOT/$SCRIPT"
  assert_success
}

@test "path predicate: a traversal segment or an extra directory level fails" {
  run bash -c '. "$1"; corpflow_grant_script_path_ok "skills/worktask/scripts/../x.sh"' \
    _ "$PLUGIN_ROOT/$SCRIPT"
  assert_failure
  run bash -c '. "$1"; corpflow_grant_script_path_ok "skills/worktask/scripts/sub/x.sh"' \
    _ "$PLUGIN_ROOT/$SCRIPT"
  assert_failure
  run bash -c '. "$1"; corpflow_grant_script_path_ok "skills/worktask/x.sh"' \
    _ "$PLUGIN_ROOT/$SCRIPT"
  assert_failure
}

# --- corpflow_grant_rule_ok ---------------------------------------------------

@test "grant predicate: the anchored bash and python3 shapes pass" {
  # shellcheck disable=SC2016
  run bash -c '. "$1"; corpflow_grant_rule_ok "Bash(bash \${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/state-patch.sh *)"' \
    _ "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  # shellcheck disable=SC2016
  run bash -c '. "$1"; corpflow_grant_rule_ok "Bash(python3 \${CLAUDE_PLUGIN_ROOT}/skills/self-improvement/scripts/x.py *)"' \
    _ "$PLUGIN_ROOT/$SCRIPT"
  assert_success
}

@test "grant predicate: colon-star, a relative path, a quoted token and an interp/ext mismatch fail" {
  # shellcheck disable=SC2016
  run bash -c '. "$1"; corpflow_grant_rule_ok "Bash(bash \${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/x.sh:*)"' \
    _ "$PLUGIN_ROOT/$SCRIPT"
  assert_failure
  run bash -c '. "$1"; corpflow_grant_rule_ok "Bash(bash skills/worktask/scripts/x.sh *)"' \
    _ "$PLUGIN_ROOT/$SCRIPT"
  assert_failure
  run bash -c '. "$1"; corpflow_grant_rule_ok "Bash(bash \"\$PLUGIN_ROOT/skills/worktask/scripts/x.sh\":*)"' \
    _ "$PLUGIN_ROOT/$SCRIPT"
  assert_failure
  # shellcheck disable=SC2016
  run bash -c '. "$1"; corpflow_grant_rule_ok "Bash(bash \${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/x.py *)"' \
    _ "$PLUGIN_ROOT/$SCRIPT"
  assert_failure
}

@test "grant predicate: an argument-scoped anchored grant passes; its relative, colon-star and wildcard-arg forms fail" {
  # shellcheck disable=SC2016
  run bash -c '. "$1"; corpflow_grant_rule_ok "Bash(bash \${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/land-artifacts.sh --consumer *)"' \
    _ "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  # shellcheck disable=SC2016
  run bash -c '. "$1"; corpflow_grant_rule_ok "Bash(bash \${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/land-artifacts.sh --consumer:*)"' \
    _ "$PLUGIN_ROOT/$SCRIPT"
  assert_failure
  run bash -c '. "$1"; corpflow_grant_rule_ok "Bash(bash skills/worktask/scripts/land-artifacts.sh --consumer *)"' \
    _ "$PLUGIN_ROOT/$SCRIPT"
  assert_failure
  # A wildcard or expansion inside the argument prefix would widen the grant.
  # shellcheck disable=SC2016
  run bash -c '. "$1"; corpflow_grant_rule_ok "Bash(bash \${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/land-artifacts.sh --c* *)"' \
    _ "$PLUGIN_ROOT/$SCRIPT"
  assert_failure
  # shellcheck disable=SC2016
  run bash -c '. "$1"; corpflow_grant_rule_ok "Bash(bash \${CLAUDE_PLUGIN_ROOT}/skills/*/scripts/land-artifacts.sh --consumer *)"' \
    _ "$PLUGIN_ROOT/$SCRIPT"
  assert_failure
}

# --- corpflow_grant_matches ---------------------------------------------------

@test "matcher: an anchored rule matches the substituted command, bare or with args" {
  # shellcheck disable=SC2016
  run bash -c '. "$1"; corpflow_grant_matches "Bash(bash \${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/state-patch.sh *)" \
    "bash /opt/root/skills/worktask/scripts/state-patch.sh" "/opt/root"' \
    _ "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  # shellcheck disable=SC2016
  run bash -c '. "$1"; corpflow_grant_matches "Bash(bash \${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/state-patch.sh *)" \
    "bash /opt/root/skills/worktask/scripts/state-patch.sh --stage DR --prev DV" "/opt/root"' \
    _ "$PLUGIN_ROOT/$SCRIPT"
  assert_success
}

@test "matcher: a legacy :* rule is equivalent to a trailing space-star" {
  # shellcheck disable=SC2016
  run bash -c '. "$1"; corpflow_grant_matches "Bash(bash \${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/x.sh:*)" \
    "bash /r/skills/worktask/scripts/x.sh --flag" "/r"' \
    _ "$PLUGIN_ROOT/$SCRIPT"
  assert_success
}

@test "matcher: no star requires an exact match" {
  # shellcheck disable=SC2016
  run bash -c '. "$1"; corpflow_grant_matches "Bash(bash \${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/x.sh)" \
    "bash /r/skills/worktask/scripts/x.sh" "/r"' \
    _ "$PLUGIN_ROOT/$SCRIPT"
  assert_success
  # shellcheck disable=SC2016
  run bash -c '. "$1"; corpflow_grant_matches "Bash(bash \${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/x.sh)" \
    "bash /r/skills/worktask/scripts/x.sh --flag" "/r"' \
    _ "$PLUGIN_ROOT/$SCRIPT"
  assert_failure
}

@test "matcher: a star anywhere else than the trailing space-star fails closed" {
  # shellcheck disable=SC2016
  run bash -c '. "$1"; corpflow_grant_matches "Bash(bash \${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/*.sh *)" \
    "bash /r/skills/worktask/scripts/x.sh --flag" "/r"' \
    _ "$PLUGIN_ROOT/$SCRIPT"
  assert_failure
}

@test "matcher: shell metacharacters and a leading VAR= in the command fail closed" {
  # shellcheck disable=SC2016
  run bash -c '. "$1"; corpflow_grant_matches "Bash(bash \${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/x.sh *)" \
    "bash /r/skills/worktask/scripts/x.sh && rm -rf /r" "/r"' \
    _ "$PLUGIN_ROOT/$SCRIPT"
  assert_failure
  # shellcheck disable=SC2016
  run bash -c '. "$1"; corpflow_grant_matches "Bash(bash \${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/x.sh *)" \
    "X=1 bash /r/skills/worktask/scripts/x.sh" "/r"' \
    _ "$PLUGIN_ROOT/$SCRIPT"
  assert_failure
}

@test "matcher: a --flag=value argument is not read as a leading env assignment" {
  # Only an anchored leading VAR= fails; '=' elsewhere in the command must match.
  # shellcheck disable=SC2016
  run bash -c '. "$1"; corpflow_grant_matches "Bash(bash \${CLAUDE_PLUGIN_ROOT}/skills/self-improvement/scripts/state-patch.sh *)" \
    "bash /r/skills/self-improvement/scripts/state-patch.sh --plugin-data=/x" "/r"' \
    _ "$PLUGIN_ROOT/$SCRIPT"
  assert_success
}

@test "matcher: a single &, an embedded newline, \$(, a backtick, < and > all fail closed" {
  # shellcheck disable=SC2016
  run bash -c '. "$1"; corpflow_grant_matches "Bash(bash \${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/x.sh *)" \
    "bash /r/skills/worktask/scripts/x.sh & curl evil" "/r"' \
    _ "$PLUGIN_ROOT/$SCRIPT"
  assert_failure
  # shellcheck disable=SC2016
  run bash -c '. "$1"; corpflow_grant_matches "Bash(bash \${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/x.sh *)" \
    "$(printf "bash /r/skills/worktask/scripts/x.sh\nrm -rf /r")" "/r"' \
    _ "$PLUGIN_ROOT/$SCRIPT"
  assert_failure
  # shellcheck disable=SC2016
  run bash -c '. "$1"; corpflow_grant_matches "Bash(bash \${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/x.sh *)" \
    "bash /r/skills/worktask/scripts/x.sh \$(rm -rf /r)" "/r"' \
    _ "$PLUGIN_ROOT/$SCRIPT"
  assert_failure
  # shellcheck disable=SC2016
  run bash -c '. "$1"; corpflow_grant_matches "Bash(bash \${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/x.sh *)" \
    "bash /r/skills/worktask/scripts/x.sh \`rm -rf /r\`" "/r"' \
    _ "$PLUGIN_ROOT/$SCRIPT"
  assert_failure
  # shellcheck disable=SC2016
  run bash -c '. "$1"; corpflow_grant_matches "Bash(bash \${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/x.sh *)" \
    "bash /r/skills/worktask/scripts/x.sh < /etc/passwd" "/r"' \
    _ "$PLUGIN_ROOT/$SCRIPT"
  assert_failure
  # shellcheck disable=SC2016
  run bash -c '. "$1"; corpflow_grant_matches "Bash(bash \${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/x.sh *)" \
    "bash /r/skills/worktask/scripts/x.sh > /etc/passwd" "/r"' \
    _ "$PLUGIN_ROOT/$SCRIPT"
  assert_failure
}

@test "matcher: an unsubstituted or relative command never matches an anchored rule" {
  # shellcheck disable=SC2016
  run bash -c '. "$1"; corpflow_grant_matches "Bash(bash \${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/x.sh *)" \
    "bash skills/worktask/scripts/x.sh" "/r"' \
    _ "$PLUGIN_ROOT/$SCRIPT"
  assert_failure
}

# --- CLI: frontmatter grant scan ---------------------------------------------

mk_grant_tree() {
  local root="$1" grant="$2"
  mk_git_fixture --dir "$root" \
    --file "agents/a.md:---\ntools: Read, $grant\n---\n\nBody.\n" \
    --file 'skills/worktask/scripts/x.sh:#!/usr/bin/env bash\n' > /dev/null
}

@test "CLI: an anchored grant is clean — exit 0, no output" {
  # shellcheck disable=SC2016
  mk_grant_tree "$WD/r" 'Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/x.sh *)'
  run bash "$PLUGIN_ROOT/$SCRIPT" --root "$WD/r"
  assert_success
  assert_output ""
}

@test "CLI: an argument-scoped anchored grant is clean" {
  # shellcheck disable=SC2016
  mk_grant_tree "$WD/r" 'Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/x.sh --consumer *)'
  run bash "$PLUGIN_ROOT/$SCRIPT" --root "$WD/r"
  assert_success
  assert_output ""
}

@test "CLI: an argument-scoped relative grant is named relative" {
  mk_grant_tree "$WD/r" 'Bash(bash skills/worktask/scripts/x.sh --consumer *)'
  run bash "$PLUGIN_ROOT/$SCRIPT" --root "$WD/r"
  assert_failure 1
  assert_output --partial "agents/a.md:2: relative: Bash(bash skills/worktask/scripts/x.sh --consumer *)"
}

@test "CLI: an argument-scoped colon-star grant is named colon-star, anchored or relative" {
  # shellcheck disable=SC2016
  mk_grant_tree "$WD/r" 'Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/x.sh --consumer:*)'
  run bash "$PLUGIN_ROOT/$SCRIPT" --root "$WD/r"
  assert_failure 1
  assert_output --partial ": colon-star: "
  rm -rf "$WD/r"
  mk_grant_tree "$WD/r" 'Bash(bash skills/worktask/scripts/x.sh --consumer:*)'
  run bash "$PLUGIN_ROOT/$SCRIPT" --root "$WD/r"
  assert_failure 1
  assert_output --partial ": colon-star: "
}

@test "CLI: a non-script grant is ignored" {
  mk_git_fixture --dir "$WD/r" \
    --file 'agents/a.md:---\ntools: Read, Bash(git:*), Bash(mkdir:*)\n---\n\nx\n' > /dev/null
  run bash "$PLUGIN_ROOT/$SCRIPT" --root "$WD/r"
  assert_success
  assert_output ""
}

@test "CLI: a relative grant is named — class, file and line" {
  mk_grant_tree "$WD/r" 'Bash(bash skills/worktask/scripts/x.sh *)'
  run bash "$PLUGIN_ROOT/$SCRIPT" --root "$WD/r"
  assert_failure 1
  assert_output --partial "agents/a.md:2: relative: Bash(bash skills/worktask/scripts/x.sh *)"
}

@test "CLI: a colon-star anchored grant is named colon-star" {
  # shellcheck disable=SC2016
  mk_grant_tree "$WD/r" 'Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/x.sh:*)'
  run bash "$PLUGIN_ROOT/$SCRIPT" --root "$WD/r"
  assert_failure 1
  assert_output --partial ": colon-star: "
}

@test "CLI: a quoted \$PLUGIN_ROOT grant is named quoted" {
  # shellcheck disable=SC2016
  mk_grant_tree "$WD/r" 'Bash(bash "$PLUGIN_ROOT/skills/worktask/scripts/x.sh":*)'
  run bash "$PLUGIN_ROOT/$SCRIPT" --root "$WD/r"
  assert_failure 1
  assert_output --partial ": quoted: "
}

@test "CLI: an unquoted \$PLUGIN_ROOT grant is named shell-var" {
  # shellcheck disable=SC2016
  mk_grant_tree "$WD/r" 'Bash(bash $PLUGIN_ROOT/skills/worktask/scripts/x.sh *)'
  run bash "$PLUGIN_ROOT/$SCRIPT" --root "$WD/r"
  assert_failure 1
  assert_output --partial ": shell-var: "
}

@test "CLI: a bare script-name grant with no path is named bare-name" {
  mk_grant_tree "$WD/r" 'Bash(bash x.sh *)'
  run bash "$PLUGIN_ROOT/$SCRIPT" --root "$WD/r"
  assert_failure 1
  assert_output --partial ": bare-name: "
}

@test "CLI: an interpreter-less path grant is named no-interpreter" {
  mk_grant_tree "$WD/r" 'Bash(skills/worktask/scripts/x.sh *)'
  run bash "$PLUGIN_ROOT/$SCRIPT" --root "$WD/r"
  assert_failure 1
  assert_output --partial ": no-interpreter: "
}

@test "CLI: an anchored grant with an extra directory level is named malformed" {
  # shellcheck disable=SC2016
  mk_grant_tree "$WD/r" 'Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/sub/x.sh *)'
  run bash "$PLUGIN_ROOT/$SCRIPT" --root "$WD/r"
  assert_failure 1
  assert_output --partial ": malformed: "
}

@test "CLI: nested skills/<plugin>/<name>/SKILL.md grants are scanned" {
  # shellcheck disable=SC2016
  mk_git_fixture --dir "$WD/r" \
    --file 'skills/plugin/subskill/SKILL.md:---\nallowed-tools: Read, Bash(bash skills/worktask/scripts/x.sh *)\n---\n\nx\n' \
    --file 'skills/worktask/scripts/x.sh:#!/usr/bin/env bash\n' > /dev/null
  run bash "$PLUGIN_ROOT/$SCRIPT" --root "$WD/r"
  assert_failure 1
  assert_output --partial "skills/plugin/subskill/SKILL.md:2: relative:"
}

@test "CLI: a grant outside frontmatter (line 1 not ---) is not scanned" {
  mk_git_fixture --dir "$WD/r" \
    --file 'agents/a.md:# no frontmatter\n\ntools: Read, Bash(bash skills/worktask/scripts/x.sh *)\n' > /dev/null
  run bash "$PLUGIN_ROOT/$SCRIPT" --root "$WD/r"
  assert_success
  assert_output ""
}

@test "CLI: usage error on an unknown flag exits 2" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --bogus
  assert_failure 2
}

@test "CLI: --root pointing at a non-directory exits 2" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --root "$WD/does-not-exist"
  assert_failure 2
}

@test "CLI: --root pointing at a non-git directory exits 2 with a stderr message" {
  # An empty/unavailable scan set (no git work tree here) fails closed,
  # never a silent clean 0 — the guard a "no widening" claim depends on.
  mkdir -p "$WD/nongit"
  run bash "$PLUGIN_ROOT/$SCRIPT" --root "$WD/nongit"
  assert_failure 2
  assert_output --partial "grant-lint.sh:"
}

# --- CLI: --invocations (body-mention scan) -------------------------------

mk_invocation_tree() {
  local root="$1" body="$2"
  # shellcheck disable=SC2016
  mk_git_fixture --dir "$root" \
    --file "agents/a.md:---\ntools: Read, Bash(bash \${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/x.sh *)\n---\n\n${body}\n" \
    --file 'skills/worktask/scripts/x.sh:#!/usr/bin/env bash\n' > /dev/null
}

@test "--invocations: the anchored invocation prefix is clean" {
  # shellcheck disable=SC2016
  mk_invocation_tree "$WD/r" 'Run `bash ${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/x.sh --flag`.'
  run bash "$PLUGIN_ROOT/$SCRIPT" --invocations --root "$WD/r"
  assert_success
  assert_output ""
}

@test "--invocations: an argument-scoped grant checks the anchored script prefix" {
  # shellcheck disable=SC2016
  mk_git_fixture --dir "$WD/r" \
    --file "agents/a.md:---\ntools: Read, Bash(bash \${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/x.sh --consumer *)\n---\n\nRun \`bash skills/worktask/scripts/x.sh --consumer y\`.\n" \
    --file 'skills/worktask/scripts/x.sh:#!/usr/bin/env bash\n' > /dev/null
  run bash "$PLUGIN_ROOT/$SCRIPT" --invocations --root "$WD/r"
  assert_failure 1
  assert_output --partial ": relative: "
}

@test "--invocations: a bare script-name mention is named bare-name" {
  mk_invocation_tree "$WD/r" 'Run `x.sh --flag`.'
  run bash "$PLUGIN_ROOT/$SCRIPT" --invocations --root "$WD/r"
  assert_failure 1
  assert_output --partial ": bare-name: "
}

@test "--invocations: a relative bash invocation is named relative" {
  mk_invocation_tree "$WD/r" 'Run `bash skills/worktask/scripts/x.sh --flag`.'
  run bash "$PLUGIN_ROOT/$SCRIPT" --invocations --root "$WD/r"
  assert_failure 1
  assert_output --partial ": relative: "
}

@test "--invocations: a \$HELPER indirection is named shell-var" {
  mk_invocation_tree "$WD/r" 'Run `bash $HELPER/skills/worktask/scripts/x.sh --flag`.'
  run bash "$PLUGIN_ROOT/$SCRIPT" --invocations --root "$WD/r"
  assert_failure 1
  assert_output --partial ": shell-var: "
}

@test "--invocations: an interpreter-less fenced mention is named no-interpreter" {
  mk_invocation_tree "$WD/r" '```bash
skills/worktask/scripts/x.sh --flag
```'
  run bash "$PLUGIN_ROOT/$SCRIPT" --invocations --root "$WD/r"
  assert_failure 1
  assert_output --partial ": no-interpreter: "
}

@test "--invocations: a fenced block line that never mentions the granted script is clean" {
  mk_invocation_tree "$WD/r" '```bash
echo hello
```'
  run bash "$PLUGIN_ROOT/$SCRIPT" --invocations --root "$WD/r"
  assert_success
  assert_output ""
}

@test "--invocations: a descriptive (non-runnable) mention is exempt" {
  mk_invocation_tree "$WD/r" 'The `x.sh check_sweep_ledger` helper fails when the ledger is stale.'
  run bash "$PLUGIN_ROOT/$SCRIPT" --invocations --root "$WD/r"
  assert_success
  assert_output ""
}

@test "--invocations: a file with no anchored grant is not scanned" {
  mk_git_fixture --dir "$WD/r" \
    --file 'agents/a.md:---\ntools: Read\n---\n\nRun `x.sh --flag`.\n' > /dev/null
  run bash "$PLUGIN_ROOT/$SCRIPT" --invocations --root "$WD/r"
  assert_success
  assert_output ""
}
