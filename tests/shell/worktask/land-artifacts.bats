#!/usr/bin/env bats
# Contract tests for skills/worktask/scripts/land-artifacts.sh.
#
# Contracts covered:
#   - happy path: --producer boundary lands a staged producer artifact into a
#     cross-tree consumer; one ok contract_landed row; landed_paths recorded;
#     consumer status untouched.
#   - sha256_mismatch: a PATH `git` shim (tests/fixtures/worktask/land-artifacts/bin/git)
#     corrupts `cat-file` output; the run fails closed, blocks the consumer, and the
#     SKILL.md readiness filter stops listing it.
#   - preconditions: not_staged, staged_then_modified, not_produced,
#     consumer_already_dispatched, producer_not_completed, not_blocked_on_producer,
#     self_consume, bad_declaration.
#   - path-safety ladder: one case per refusal reason reachable from a real tree.
#   - same_tree: physically-equal roots copy nothing, ok row mode same_tree.
#   - row cardinality: idempotent re-run, gate no-op after boundary, gate into a
#     freshly re-pinned tree, boundary skip of a `blocked` consumer.
#   - --list-landed, --dry-run, usage exit 2.
#   - parity: the exclusion expression is byte-identical across every transport.
#   - readers (fn-preflight-cmds.sh base-sanity, the density hook, DR, FN,
#     SKILL.md Step 4.7a) do not flag/count an untracked landed path.
#   - --self-test reaches ALL PASS (dv-tree-preflight.sh convention).
#
# Reader paths named literally for L1 selection reachability:
#   skills/worktask/scripts/land-artifacts.sh
#   skills/worktask/scripts/land-artifacts-selftest.sh
#   skills/worktask/scripts/fn-preflight-cmds.sh
#   hooks/dv-comment-density-gate.sh
#   agents/technical-lead.md
#   agents/project-manager.md
#   skills/worktask/SKILL.md
#   skills/shared/state-ledger.md
#   skills/worktask/references/handoff-protocol.md
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"

SCRIPT="skills/worktask/scripts/land-artifacts.sh"
FIXDIR="${FIXTURES}/worktask/land-artifacts"

# D8: the one exclusion expression, mirrored here only for the parity assertions
# below — never sourced, so a drift in any transport is a diff, not a silent pass.
D8_JQ='[(.tasks // {})[] | .metadata.landed_paths // [] | arrays | .[] | strings] | unique | .[]'

phys() { (cd -P "$1" 2>/dev/null && pwd -P); }

setup() {
  WD="$(mk_tmpworkdir)"
  BASE="$WD/base"
  mkdir -p "$BASE"
  git -C "$BASE" init -q
  git -C "$BASE" config user.email t@t.t
  git -C "$BASE" config user.name t
  printf 'seed\n' > "$BASE/seed.txt"
  git -C "$BASE" add seed.txt
  git -C "$BASE" commit -q -m seed

  git -C "$BASE" worktree add -q -b p-branch "$WD/P" > /dev/null
  git -C "$BASE" worktree add -q -b c-branch "$WD/C" > /dev/null
  P_REAL="$(phys "$WD/P")"
  C_REAL="$(phys "$WD/C")"
  git -C "$P_REAL" config user.email t@t.t
  git -C "$P_REAL" config user.name t
  git -C "$C_REAL" config user.email t@t.t
  git -C "$C_REAL" config user.name t

  printf 'k: v\n' > "$P_REAL/contract.yaml"
  git -C "$P_REAL" add contract.yaml

  CTX="$WD/.context"
  mkdir -p "$CTX/logs"
  STATE="$CTX/state.json"
  jq --arg p "$P_REAL" --arg c "$C_REAL" \
    '(.tasks.DV0.metadata.workspace_path) = $p
     | (.tasks.DV1.metadata.workspace_path) = $c
     | (.tasks.DV2.metadata.workspace_path) = $p' \
    "$FIXDIR/state.land.json" > "$STATE"
  AUDIT="$CTX/logs/audit.jsonl"
}

teardown() {
  _test_helper_cleanup
}

run_land() {
  run bash "$PLUGIN_ROOT/$SCRIPT" --state "$STATE" "$@"
}

# Overrides DV0.produces and DV1.consumes to a single path, replacing the default.
set_pair_path() {
  local p="$1"
  jq --arg p "$p" \
    '(.tasks.DV0.metadata.produces) = [$p]
     | (.tasks.DV1.metadata.consumes) = [{"from": "DV0", "paths": [$p]}]' \
    "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
}

patch_state() {
  jq "$1" "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
}

reason_of() { jq -r '.tasks.DV1.metadata.landing_error.reason' "$STATE"; }

# One case per D5/D4 refusal reachable purely from the ledger (no P/C filesystem
# fixture needed): lexical_check runs before any git/filesystem touch.
assert_refused() {
  local reason="$1" path="$2"
  run_land --producer DV0
  assert_equal "$status" 1
  assert_equal "$(reason_of)" "$reason"
  [ ! -e "$C_REAL/$path" ]
  assert_audit_row contract_landed --file "$AUDIT" --subject DV1 --result fail \
    --meta reason="$reason" --count 1
}

# ---------------------------------------------------------------------------
# AC1 / AC2
# ---------------------------------------------------------------------------

@test "contract: AC1 happy path lands the producer artifact into the consumer tree" {
  run_land --producer DV0
  assert_equal "$status" 0
  [ -f "$C_REAL/contract.yaml" ]

  local oid dest_sha src_sha
  oid=$(git -C "$P_REAL" ls-files -s -- contract.yaml | awk '{print $2}')
  src_sha=$(git -C "$P_REAL" cat-file blob "$oid" | shasum -a 256 | awk '{print $1}')
  dest_sha=$(shasum -a 256 < "$C_REAL/contract.yaml" | awk '{print $1}')
  assert_equal "$dest_sha" "$src_sha"

  assert_audit_row contract_landed --file "$AUDIT" --subject DV1 --result ok --count 1
  assert_equal "$(jq -r '.tasks.DV1.metadata.landed_paths | index("contract.yaml") != null' "$STATE")" 'true'
  assert_equal "$(jq -r '.tasks.DV1.status' "$STATE")" 'pending'
}

@test "contract: AC2 a corrupted cat-file read fails closed with sha256_mismatch" {
  LAND_REAL_GIT="$(command -v git)"
  export LAND_REAL_GIT
  local old_path="$PATH"
  PATH="$FIXDIR/bin:$PATH"
  run_land --producer DV0
  PATH="$old_path"

  assert_equal "$status" 1
  [ ! -e "$C_REAL/contract.yaml" ]
  assert_equal "$(jq -r '.tasks.DV1.metadata.landed_paths // [] | length' "$STATE")" 0
  assert_equal "$(jq -r '.tasks.DV1.status' "$STATE")" 'blocked'
  assert_equal "$(reason_of)" 'sha256_mismatch'
  assert_audit_row contract_landed --file "$AUDIT" --subject DV1 --result fail \
    --meta reason=sha256_mismatch --count 1

  # The SKILL.md readiness filter (canonical jq, § Readiness is mechanical)
  # must no longer offer a `blocked` DV1.
  run jq -r '.tasks as $t | $t | to_entries[]
    | select(.value.status == "pending")
    | select([(.value.blocked_by // [])[] | $t[.].status] | all(. == "completed"))
    | .key' "$STATE"
  refute_line 'DV1'
}

# ---------------------------------------------------------------------------
# D5 path-safety ladder — lexical (no filesystem needed)
# ---------------------------------------------------------------------------

@test "contract: D5 absolute_path is refused" {
  set_pair_path "/etc/passwd"
  assert_refused absolute_path "/etc/passwd"
}

@test "contract: D5 dotdot is refused" {
  set_pair_path "a/../b.yaml"
  assert_refused dotdot "a/../b.yaml"
}

@test "contract: D5 reserved_segment is refused (.GIT case-fold variant)" {
  set_pair_path ".GIT/x"
  assert_refused reserved_segment ".GIT/x"
}

@test "contract: D5 control_char is refused" {
  local p
  p=$'bad\x01name.yaml'
  set_pair_path "$p"
  assert_refused control_char "$p"
}

@test "contract: D5 leading_dash is refused" {
  set_pair_path "-bad.yaml"
  assert_refused leading_dash "-bad.yaml"
}

@test "contract: D5 unsafe_char is refused" {
  set_pair_path "bad name.yaml"
  assert_refused unsafe_char "bad name.yaml"
}

# ---------------------------------------------------------------------------
# D5 path-safety ladder — needs a real tree
# ---------------------------------------------------------------------------

@test "contract: D5 symlink_source is refused for a staged symlink (mode 120000)" {
  ln -s /nonexistent "$P_REAL/linkfile.yaml"
  git -C "$P_REAL" add linkfile.yaml
  set_pair_path "linkfile.yaml"
  assert_refused symlink_source "linkfile.yaml"
}

@test "contract: D5 symlink_source is refused via a symlinked intermediate dir in P" {
  mkdir -p "$WD/real_target"
  printf 'inner\n' > "$WD/real_target/inner.txt"
  ln -s "$WD/real_target" "$P_REAL/sdir"
  git -C "$P_REAL" add sdir/inner.txt
  set_pair_path "sdir/inner.txt"
  assert_refused symlink_source "sdir/inner.txt"
}

@test "contract: D5 symlink_segment is refused for a symlinked dir in C" {
  mkdir -p "$P_REAL/seg"
  printf 'inner\n' > "$P_REAL/seg/inner.yaml"
  git -C "$P_REAL" add seg/inner.yaml
  ln -s "$WD" "$C_REAL/seg"
  set_pair_path "seg/inner.yaml"
  assert_refused symlink_segment "seg/inner.yaml"
}

@test "contract: D5 symlink_dest is refused when the destination is already a symlink" {
  ln -s /nonexistent "$C_REAL/contract.yaml"
  assert_refused symlink_dest "contract.yaml"
}

@test "contract: D5 dest_escape vector actually classifies as symlink_segment (ladder order)" {
  # A parent segment symlinked outside C's root is caught by dest_walk's per-segment
  # -L check BEFORE the phys_parent/dest_escape comparison is ever reached, so this
  # vector's observed reason is symlink_segment, not dest_escape — pinned here rather
  # than asserted as unreachable so a ladder reorder shows up as a test failure.
  mkdir -p "$P_REAL/outside"
  printf 'inner\n' > "$P_REAL/outside/thing.yaml"
  git -C "$P_REAL" add outside/thing.yaml
  ln -s "$WD" "$C_REAL/outside"
  set_pair_path "outside/thing.yaml"
  assert_refused symlink_segment "outside/thing.yaml"
}

@test "contract: D5 dest_tracked is refused when C already tracks different content" {
  printf 'different\n' > "$C_REAL/contract.yaml"
  git -C "$C_REAL" add contract.yaml
  git -C "$C_REAL" commit -q -m seed-tracked
  assert_refused dest_tracked "contract.yaml"
}

@test "contract: D5 dest_exists is refused for an untracked file with different content" {
  printf 'different\n' > "$C_REAL/contract.yaml"
  assert_refused dest_exists "contract.yaml"
}

@test "contract: D5 not_dir is refused when a parent segment is a regular file" {
  mkdir -p "$P_REAL/blocker"
  printf 'inner\n' > "$P_REAL/blocker/contract2.yaml"
  git -C "$P_REAL" add blocker/contract2.yaml
  printf 'i am a file\n' > "$C_REAL/blocker"
  set_pair_path "blocker/contract2.yaml"
  assert_refused not_dir "blocker/contract2.yaml"
}

@test "contract: D5 gitlink (mode 160000) is refused" {
  local head_sha
  head_sha=$(git -C "$P_REAL" rev-parse HEAD)
  git -C "$P_REAL" update-index --add --cacheinfo "160000,${head_sha},sub.git"
  set_pair_path "sub.git"
  assert_refused gitlink "sub.git"
}

@test "contract: D5 filtered_path is refused for a filter=lfs attribute" {
  printf 'lfs.bin filter=lfs\n' > "$P_REAL/.gitattributes"
  git -C "$P_REAL" add .gitattributes
  git -C "$P_REAL" commit -q -m attrs
  printf 'binary-ish\n' > "$P_REAL/lfs.bin"
  git -C "$P_REAL" add lfs.bin
  set_pair_path "lfs.bin"
  assert_refused filtered_path "lfs.bin"
}

# ---------------------------------------------------------------------------
# D4 preconditions
# ---------------------------------------------------------------------------

@test "contract: D4 not_staged is refused when the path was never git add'ed" {
  set_pair_path "never-staged.yaml"
  assert_refused not_staged "never-staged.yaml"
}

@test "contract: D4 staged_then_modified is refused for a post-stage edit" {
  printf 'a\n' > "$P_REAL/mod.yaml"
  git -C "$P_REAL" add mod.yaml
  printf 'b\n' > "$P_REAL/mod.yaml"
  set_pair_path "mod.yaml"
  assert_refused staged_then_modified "mod.yaml"
}

@test "contract: D4 not_produced is refused when the path is absent from producer.produces" {
  patch_state '(.tasks.DV1.metadata.consumes) = [{"from": "DV0", "paths": ["other.yaml"]}]'
  assert_refused not_produced "other.yaml"
}

@test "contract: D4 consumer_already_dispatched is refused when C is not pending" {
  patch_state '(.tasks.DV1.status) = "in_progress"'
  assert_refused consumer_already_dispatched "contract.yaml"
}

@test "contract: D4 producer_not_completed is refused when P has not completed" {
  patch_state '(.tasks.DV0.status) = "pending"'
  assert_refused producer_not_completed "contract.yaml"
}

@test "contract: D4 not_blocked_on_producer is refused when C.blocked_by omits P" {
  patch_state '(.tasks.DV1.blocked_by) = []'
  assert_refused not_blocked_on_producer "contract.yaml"
}

@test "contract: D4 self_consume is refused when a row consumes from itself" {
  patch_state '(.tasks.DV1.metadata.consumes) = [{"from": "DV1", "paths": ["contract.yaml"]}]
    | (.tasks.DV1.blocked_by) = ["DV1"]'
  run_land --consumer DV1
  assert_equal "$status" 1
  assert_equal "$(reason_of)" 'self_consume'
}

@test "contract: D4 bad_declaration is refused for a malformed consumes shape" {
  patch_state '(.tasks.DV1.metadata.consumes) = [{"from": "DV0"}]'
  run_land --producer DV0
  assert_equal "$status" 1
  assert_equal "$(reason_of)" 'bad_declaration'
  assert_audit_row contract_landed --file "$AUDIT" --subject DV1 --result fail \
    --meta reason=bad_declaration --count 1
}

# ---------------------------------------------------------------------------
# D6 same tree / D7 row cardinality
# ---------------------------------------------------------------------------

@test "contract: D6 same_tree writes an ok row and records no landed_paths" {
  run_land --producer DV0
  assert_equal "$status" 0
  assert_audit_row contract_landed --file "$AUDIT" --subject DV2 --result ok \
    --meta mode=same_tree --count 1
  assert_equal "$(jq -r '.tasks.DV2.metadata.landed_paths // [] | length' "$STATE")" 0
}

@test "contract: idempotent boundary re-run does not duplicate landed_paths" {
  run_land --producer DV0
  assert_equal "$status" 0
  run_land --producer DV0
  assert_equal "$status" 0
  local n
  n=$(jq -r '[.tasks.DV1.metadata.landed_paths[] | select(. == "contract.yaml")] | length' "$STATE")
  assert_equal "$n" 1
}

@test "contract: the dispatch gate after a boundary pass is a no-op (no new row)" {
  run_land --producer DV0
  assert_equal "$status" 0
  local before
  before=$(wc -l < "$AUDIT" | tr -d ' ')
  run_land --consumer DV1
  assert_equal "$status" 0
  local after
  after=$(wc -l < "$AUDIT" | tr -d ' ')
  assert_equal "$after" "$before"
}

@test "contract: the dispatch gate into a freshly re-pinned tree adds one copied row" {
  run_land --producer DV0
  assert_equal "$status" 0

  git -C "$BASE" worktree add -q -b c2-branch "$WD/C2" > /dev/null
  local C2_REAL
  C2_REAL="$(phys "$WD/C2")"
  git -C "$C2_REAL" config user.email t@t.t
  git -C "$C2_REAL" config user.name t
  jq --arg c2 "$C2_REAL" '.tasks.DV1.metadata.workspace_path = $c2' "$STATE" > "$STATE.tmp" \
    && mv "$STATE.tmp" "$STATE"

  run_land --consumer DV1
  assert_equal "$status" 0
  [ -f "$C2_REAL/contract.yaml" ]
  assert_audit_row contract_landed --file "$AUDIT" --subject DV1 --result ok \
    --meta mode=copied --count 1
}

@test "contract: a boundary pass skips a blocked consumer, keeping its landing_error" {
  patch_state '(.tasks.DV1.status) = "blocked"
    | (.tasks.DV1.metadata.landing_error) = {"reason": "sha256_mismatch", "path": "contract.yaml", "producer": "DV0"}'
  run_land --producer DV0
  assert_equal "$status" 0
  assert_equal "$(reason_of)" 'sha256_mismatch'
  assert_audit_row contract_landed --file "$AUDIT" --subject DV1 --absent
}

# ---------------------------------------------------------------------------
# --list-landed / --dry-run / usage
# ---------------------------------------------------------------------------

@test "contract: --list-landed prints the sorted unique union across rows" {
  patch_state '(.tasks.DV1.metadata.landed_paths) = ["b.yaml", "a.yaml"]
    | (.tasks.DV2.metadata.landed_paths) = ["a.yaml", "c.yaml"]'
  run bash "$PLUGIN_ROOT/$SCRIPT" --list-landed --state "$STATE"
  assert_equal "$status" 0
  assert_equal "$output" "$(printf 'a.yaml\nb.yaml\nc.yaml')"
}

@test "contract: --list-landed on an empty ledger prints nothing and exits 0" {
  local empty="$WD/empty-state.json"
  printf '{"tasks":{}}' > "$empty"
  run bash "$PLUGIN_ROOT/$SCRIPT" --list-landed --state "$empty"
  assert_equal "$status" 0
  assert_equal "$output" ""
}

@test "contract: --dry-run writes nothing to disk, the ledger or the audit log" {
  local before_sum after_sum
  before_sum=$(shasum -a 256 < "$STATE")
  run_land --producer DV0 --dry-run
  assert_equal "$status" 0
  [ ! -e "$C_REAL/contract.yaml" ]
  after_sum=$(shasum -a 256 < "$STATE")
  assert_equal "$after_sum" "$before_sum"
  [ ! -s "$AUDIT" ]
}

@test "contract: no selector at all exits 2" {
  run_land
  assert_equal "$status" 2
}

@test "contract: a malformed task id exits 2" {
  run_land --consumer DVx
  assert_equal "$status" 2
}

@test "contract: an unknown task id exits 2" {
  run_land --consumer DV9
  assert_equal "$status" 2
}

# ---------------------------------------------------------------------------
# --self-test
# ---------------------------------------------------------------------------

@test "contract: --self-test reaches ALL PASS" {
  run bash "$PLUGIN_ROOT/$SCRIPT" --self-test
  assert_equal "$status" 0
  assert_output --partial "ALL PASS"
}

# ---------------------------------------------------------------------------
# D8 parity — the exclusion expression is byte-identical at every transport
# ---------------------------------------------------------------------------

@test "contract: D8 exclusion expression is byte-identical in every transport" {
  grep -F -- "$D8_JQ" "$PLUGIN_ROOT/skills/worktask/scripts/land-artifacts.sh"
  grep -F -- "$D8_JQ" "$PLUGIN_ROOT/hooks/dv-comment-density-gate.sh"
  grep -F -- "$D8_JQ" "$PLUGIN_ROOT/agents/technical-lead.md"
  grep -F -- "$D8_JQ" "$PLUGIN_ROOT/agents/project-manager.md"
  grep -F -- "$D8_JQ" "$PLUGIN_ROOT/skills/shared/state-ledger.md"
}

# ---------------------------------------------------------------------------
# AC4 — reader exclusion (D8 transports (a)/(b)/(c))
# ---------------------------------------------------------------------------

@test "contract: fn-preflight-cmds.sh and the selftest harness name the D8 union" {
  grep -qE -- '--list-landed|landed_paths' \
    "$PLUGIN_ROOT/skills/worktask/scripts/fn-preflight-cmds.sh"
  [ -e "$PLUGIN_ROOT/skills/worktask/scripts/land-artifacts-selftest.sh" ]
}

@test "contract: the canonical D8 jq matches an untracked-landed-path exclusion on a fixture tree" {
  local repo
  repo="$(mk_git_fixture --branch main --file 'README.md:seed\n' --commit init)"
  printf 'k: v\n' > "$repo/contract.yaml"
  local ledger="$WD/reader-state.json"
  jq -n --arg p contract.yaml \
    '{tasks: {DV1: {status: "pending", metadata: {landed_paths: [$p]}}}}' > "$ledger"

  local landed untracked
  landed=$(jq -r "$D8_JQ" "$ledger" | LC_ALL=C sort)
  untracked=$(git -C "$repo" status --porcelain --untracked-files=all \
    | awk '/^\?\? /{print substr($0,4)}' | LC_ALL=C sort)
  # Every untracked path in the fixture tree is accounted for by the landed set.
  local remainder
  remainder=$(comm -23 <(printf '%s\n' "$untracked") <(printf '%s\n' "$landed") | grep -v '^$' || true)
  assert_equal "$remainder" ""
}

@test "contract: DR, FN and SKILL.md 4.7a name the D8 exclusion" {
  grep -qE -- "landed_paths|--list-landed" "$PLUGIN_ROOT/agents/technical-lead.md"
  grep -qE -- "landed_paths|--list-landed" "$PLUGIN_ROOT/agents/project-manager.md"
  grep -qE -- "landed_paths|--list-landed" "$PLUGIN_ROOT/skills/worktask/SKILL.md"
}

@test "contract: handoff-protocol.md documents the ledger-task fan-out land-artifacts.sh resolves through" {
  [ -e "$PLUGIN_ROOT/skills/worktask/references/handoff-protocol.md" ]
  grep -q "workspace_path" "$PLUGIN_ROOT/skills/worktask/references/handoff-protocol.md"
}
