#!/usr/bin/env bats
# Contract tests for skills/worktask/scripts/fn-stream-merge.sh and the per-stream mode of
# fn-preflight.sh continuity.
#   - plan: multi only when DV rows span >=2 physical trees
#   - commit: one commit per stream tree, landed paths excluded, facts= line printed
#   - merge: one two-parent --no-ff merge per stream; foreign commits and conflicts block
#     with no ref moved beyond the new merges
#   - continuity: merged streams never write diverged_cherry_pick; an unmerged one exits 1
load "${BATS_TEST_DIRNAME}/../../lib/test_helper.bash"
bats_require_minimum_version 1.5.0

SCRIPT="skills/worktask/scripts/fn-stream-merge.sh"
PREFLIGHT="skills/worktask/scripts/fn-preflight.sh"
COMBINED="feature/398-combined"

setup() {
  WD="$(mk_tmpworkdir)"
  WD="$(cd "$WD" && pwd -P)"
  export HOME="$WD" GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  unset FN_BASE_REF
  git init -q -b develop "$WD/repo"
  printf 'base\n' > "$WD/repo/svc.txt"
  printf 'base\n' > "$WD/repo/web.txt"
  printf 'base\n' > "$WD/repo/landed.md"
  git -C "$WD/repo" add -A
  git -C "$WD/repo" commit -qm base
  git init -q --bare "$WD/origin.git"
  git -C "$WD/repo" remote add origin "$WD/origin.git"
  git -C "$WD/repo" push -q origin develop
  git -C "$WD/repo" fetch -q origin
  git -C "$WD/repo" worktree add -q -b feature/s-service "$WD/wt-service" develop
  git -C "$WD/repo" worktree add -q -b feature/s-web "$WD/wt-web" develop
  mkdir -p "$WD/ledger/.context/logs"
  L="$WD/ledger/.context/state.json"
  jq --arg s "$WD/wt-service" --arg w "$WD/wt-web" --arg c "$COMBINED" \
    '.tasks.DV0.metadata.workspace_path = $s | .tasks.DV1.metadata.workspace_path = $w
     | .metadata = {base_ref: "develop"} | .facts.branch = $c' \
    "$FIXTURES/worktask/dv-fanout/state.two-stream.json" > "$L"
  printf 'feat: stream work\n' > "$WD/msg.txt"
}

stream_edits() {
  printf 'svc change\n' >> "$WD/wt-service/svc.txt"
  printf 'web change\n' >> "$WD/wt-web/web.txt"
}

record_branches() {
  jq '.facts.stream_branches = {service: "feature/s-service", web: "feature/s-web"}' "$L" > "$L.tmp"
  mv "$L.tmp" "$L"
}

commit_both() {
  bash "$PLUGIN_ROOT/$SCRIPT" --state "$L" commit --task DV0 --message-file "$WD/msg.txt"
  bash "$PLUGIN_ROOT/$SCRIPT" --state "$L" commit --task DV1 --message-file "$WD/msg.txt"
}

refs_snapshot() {
  git -C "$WD/repo" for-each-ref --format='%(refname) %(objectname)' | shasum
}

@test "plan: two rows in two trees select the multi arm, rows in task-id order" {
  run --separate-stderr bash "$PLUGIN_ROOT/$SCRIPT" --state "$L" plan
  assert_success
  assert_line --index 0 "arm=multi streams=2"
  assert_line --index 1 "$(printf 'DV0\tservice\t%s' "$WD/wt-service")"
  assert_line --index 2 "$(printf 'DV1\tweb\t%s' "$WD/wt-web")"
}

@test "plan: rows sharing one tree stay on the single arm (shared_tree)" {
  jq --arg s "$WD/wt-service" '.tasks.DV1.metadata.workspace_path = $s' "$L" > "$L.tmp" && mv "$L.tmp" "$L"
  run --separate-stderr bash "$PLUGIN_ROOT/$SCRIPT" --state "$L" plan
  assert_success
  assert_output "arm=single reason=shared_tree"
}

@test "plan: one DV row stays on the single arm (one_dv_row)" {
  jq 'del(.tasks.DV1)' "$L" > "$L.tmp" && mv "$L.tmp" "$L"
  run --separate-stderr bash "$PLUGIN_ROOT/$SCRIPT" --state "$L" plan
  assert_success
  assert_output "arm=single reason=one_dv_row"
}

@test "commit and merge refuse the single arm, moving nothing" {
  jq 'del(.tasks.DV1)' "$L" > "$L.tmp" && mv "$L.tmp" "$L"
  stream_edits
  local before; before=$(refs_snapshot)
  run --separate-stderr bash "$PLUGIN_ROOT/$SCRIPT" --state "$L" commit --task DV0 --message-file "$WD/msg.txt"
  assert_failure 1
  assert_output "blocked reason=arm_single task=DV0 stream=-"
  run --separate-stderr bash -c "cd '$WD/repo' && bash '$PLUGIN_ROOT/$SCRIPT' --state '$L' merge"
  assert_failure 1
  assert_output --partial "blocked reason=arm_single"
  [ "$(refs_snapshot)" = "$before" ]
}

@test "commit: one commit per stream and a facts line state-patch accepts" {
  stream_edits
  run --separate-stderr bash "$PLUGIN_ROOT/$SCRIPT" --state "$L" commit --task DV0 --message-file "$WD/msg.txt"
  assert_success
  assert_line --index 0 --regexp '^committed task=DV0 stream=service branch=feature/s-service sha=[0-9a-f]+ excluded=0 untracked=0$'
  assert_line --index 1 'facts={"stream_branches":{"service":"feature/s-service"}}'
  run git -C "$WD/wt-service" rev-list --count develop..HEAD
  assert_output "1"
  run --separate-stderr bash "$PLUGIN_ROOT/$SCRIPT" --state "$L" commit --task DV0 --message-file "$WD/msg.txt"
  assert_success
  assert_line --index 0 --partial "already_committed task=DV0"
}

@test "commit: a landed path is excluded from the stream commit" {
  local svc_real
  svc_real="$(cd -P "$WD/wt-service" && pwd -P)"
  jq --arg s "$svc_real" \
    '.tasks.DV0.metadata.landed_paths = ["artifact.yaml"] | .tasks.DV0.metadata.landed_roots = [$s]' \
    "$L" > "$L.tmp" && mv "$L.tmp" "$L"
  stream_edits
  # A new, staged path (git add -u never stages an untracked file): its diff
  # status is Added, so --diff-filter=A still excludes it.
  printf 'landed change\n' > "$WD/wt-service/artifact.yaml"
  git -C "$WD/wt-service" add artifact.yaml
  run --separate-stderr bash "$PLUGIN_ROOT/$SCRIPT" --state "$L" commit --task DV0 --message-file "$WD/msg.txt"
  assert_success
  assert_line --index 0 --partial "excluded=1"
  run git -C "$WD/wt-service" show --name-only --format= HEAD
  assert_output "svc.txt"
}

@test "commit: a landed-set entry matching a tracked modification is still committed, not unstaged" {
  # landed.md is already tracked from the base commit; declaring it landed
  # here is a forged/stale entry — land-artifacts.sh itself never overwrites
  # tracked content (dest_tracked refuses that), so a real landing is always
  # an add. --diff-filter=A must leave this genuine modification staged.
  local svc_real
  svc_real="$(cd -P "$WD/wt-service" && pwd -P)"
  jq --arg s "$svc_real" \
    '.tasks.DV0.metadata.landed_paths = ["landed.md"] | .tasks.DV0.metadata.landed_roots = [$s]' \
    "$L" > "$L.tmp" && mv "$L.tmp" "$L"
  stream_edits
  printf 'landed change\n' >> "$WD/wt-service/landed.md"
  run --separate-stderr bash "$PLUGIN_ROOT/$SCRIPT" --state "$L" commit --task DV0 --message-file "$WD/msg.txt"
  assert_success
  assert_line --index 0 --partial "excluded=0"
  run git -C "$WD/wt-service" show --name-only --format= HEAD
  assert_line "landed.md"
  assert_line "svc.txt"
}

@test "commit: a same-named staged path lands only in one stream's tree, excluded only there" {
  printf 'shared\n' > "$WD/wt-service/shared.yaml"
  printf 'shared\n' > "$WD/wt-web/shared.yaml"
  git -C "$WD/wt-service" add shared.yaml
  git -C "$WD/wt-web" add shared.yaml

  local web_real
  web_real="$(cd -P "$WD/wt-web" && pwd -P)"
  jq --arg w "$web_real" \
    '.tasks.DV1.metadata.landed_paths = ["shared.yaml"] | .tasks.DV1.metadata.landed_roots = [$w]' \
    "$L" > "$L.tmp" && mv "$L.tmp" "$L"

  stream_edits
  run --separate-stderr bash "$PLUGIN_ROOT/$SCRIPT" --state "$L" commit --task DV0 --message-file "$WD/msg.txt"
  assert_success
  assert_line --index 0 --partial "excluded=0"
  run git -C "$WD/wt-service" show --name-only --format= HEAD
  assert_line "shared.yaml"

  run --separate-stderr bash "$PLUGIN_ROOT/$SCRIPT" --state "$L" commit --task DV1 --message-file "$WD/msg.txt"
  assert_success
  assert_line --index 0 --partial "excluded=1"
  run git -C "$WD/wt-web" show --name-only --format= HEAD
  refute_line "shared.yaml"
}

@test "commit: an unsafe landed-set entry scoped to the stream's own tree blocks landed_path_unsafe" {
  local svc_real
  svc_real="$(cd -P "$WD/wt-service" && pwd -P)"
  jq --arg s "$svc_real" \
    '.tasks.DV0.metadata.landed_paths = ["../escape"] | .tasks.DV0.metadata.landed_roots = [$s]' \
    "$L" > "$L.tmp" && mv "$L.tmp" "$L"
  stream_edits
  local head_before
  head_before=$(git -C "$WD/wt-service" rev-parse HEAD)
  run --separate-stderr bash "$PLUGIN_ROOT/$SCRIPT" --state "$L" commit --task DV0 --message-file "$WD/msg.txt"
  assert_failure 1
  assert_output "blocked reason=landed_path_unsafe task=DV0 stream=service"
  [ "$(git -C "$WD/wt-service" rev-parse HEAD)" = "$head_before" ]
}

@test "commit: untracked= excludes an untracked landed file but counts an unrelated untracked file" {
  local svc_real
  svc_real="$(cd -P "$WD/wt-service" && pwd -P)"
  jq --arg s "$svc_real" \
    '.tasks.DV0.metadata.landed_paths = ["landed.txt"] | .tasks.DV0.metadata.landed_roots = [$s]' \
    "$L" > "$L.tmp" && mv "$L.tmp" "$L"
  stream_edits
  printf 'x\n' > "$WD/wt-service/landed.txt"
  printf 'y\n' > "$WD/wt-service/other.txt"
  run --separate-stderr bash "$PLUGIN_ROOT/$SCRIPT" --state "$L" commit --task DV0 --message-file "$WD/msg.txt"
  assert_success
  assert_line --index 0 --partial "untracked=1"
}

@test "merge: exactly one two-parent --no-ff merge per stream, then continuity passes (AC4)" {
  stream_edits
  commit_both
  record_branches
  run --separate-stderr bash -c "cd '$WD/repo' && bash '$PLUGIN_ROOT/$SCRIPT' --state '$L' merge"
  assert_success
  assert_line --index 0 --regexp '^merged stream=service branch=feature/s-service sha=[0-9a-f]+$'
  assert_line --index 1 --regexp '^merged stream=web branch=feature/s-web sha=[0-9a-f]+$'
  assert_line --index 2 --regexp "^combined=${COMBINED} head=[0-9a-f]+ base=develop$"
  run git -C "$WD/repo" rev-list --merges --count "origin/develop..${COMBINED}"
  assert_output "2"
  run bash -c "git -C '$WD/repo' rev-list --merges --parents 'origin/develop..${COMBINED}' | awk '{ print NF - 1 }' | sort -u"
  assert_output "2"
  run git -C "$WD/repo" log --merges --format=%s "origin/develop..${COMBINED}"
  assert_output "$(printf "Merge branch 'feature/s-web' into %s\nMerge branch 'feature/s-service' into %s" "$COMBINED" "$COMBINED")"
  run --separate-stderr bash -c "cd '$WD/repo' && bash '$PLUGIN_ROOT/$PREFLIGHT' --state '$L' --context '$WD/ledger/.context' continuity"
  assert_success
  run bash -c "grep -c diverged_cherry_pick '$WD/ledger/.context/logs/audit.jsonl' || true"
  assert_output "0"
  run jq -r 'select(.action == "branch_continuity") | .result' "$WD/ledger/.context/logs/audit.jsonl"
  assert_output "$(printf 'stream_merged\nstream_merged')"
}

@test "merge: a re-run is idempotent (already_merged, no new commit)" {
  stream_edits
  commit_both
  record_branches
  bash -c "cd '$WD/repo' && bash '$PLUGIN_ROOT/$SCRIPT' --state '$L' merge"
  local head; head=$(git -C "$WD/repo" rev-parse "$COMBINED")
  run --separate-stderr bash -c "cd '$WD/repo' && bash '$PLUGIN_ROOT/$SCRIPT' --state '$L' merge"
  assert_success
  assert_line --index 0 --partial "already_merged stream=service"
  [ "$(git -C "$WD/repo" rev-parse "$COMBINED")" = "$head" ]
}

@test "merge: a pre-existing combined branch with a foreign commit blocks, refs unmoved" {
  stream_edits
  commit_both
  record_branches
  git -C "$WD/repo" switch -q -c "$COMBINED" develop
  printf 'foreign\n' > "$WD/repo/foreign.txt"
  git -C "$WD/repo" add foreign.txt
  git -C "$WD/repo" commit -qm "chore: foreign"
  local before; before=$(refs_snapshot)
  run --separate-stderr bash -c "cd '$WD/repo' && bash '$PLUGIN_ROOT/$SCRIPT' --state '$L' merge"
  assert_failure 1
  assert_output "blocked reason=combined_foreign_commits task=- stream=-"
  [ "$(refs_snapshot)" = "$before" ]
}

@test "merge: a conflict aborts, blocks naming the stream, and leaves no merge in progress" {
  printf 'svc side\n' >> "$WD/wt-service/web.txt"
  printf 'web side\n' >> "$WD/wt-web/web.txt"
  commit_both
  record_branches
  run --separate-stderr bash -c "cd '$WD/repo' && bash '$PLUGIN_ROOT/$SCRIPT' --state '$L' merge"
  assert_failure 1
  assert_output --partial "blocked reason=merge_conflict task=- stream=web"
  run git -C "$WD/repo" rev-parse --verify --quiet MERGE_HEAD
  assert_failure
  run git -C "$WD/repo" rev-list --merges --count "origin/develop..${COMBINED}"
  assert_output "1"
}

@test "merge: landed_path_in_stream blocks only the stream whose own tree holds the landing" {
  # A same-named path committed on BOTH stream branches, landed only in web's tree —
  # service's identical commit must not trip the check meant for web alone.
  printf 'x\n' > "$WD/wt-service/shared.yaml"
  git -C "$WD/wt-service" add shared.yaml
  git -C "$WD/wt-service" commit -qm "chore: shared service"
  printf 'y\n' > "$WD/wt-web/shared.yaml"
  git -C "$WD/wt-web" add shared.yaml
  git -C "$WD/wt-web" commit -qm "chore: shared web"

  stream_edits
  commit_both

  # Landed AFTER commit, like the real flow: cmd_commit runs this same landed-path check
  # on HEAD, so recording it earlier would trip commit_both on web before merge is reached.
  local web_real
  web_real="$(cd -P "$WD/wt-web" && pwd -P)"
  jq --arg w "$web_real" \
    '.tasks.DV1.metadata.landed_paths = ["shared.yaml"] | .tasks.DV1.metadata.landed_roots = [$w]' \
    "$L" > "$L.tmp" && mv "$L.tmp" "$L"

  record_branches
  run --separate-stderr bash -c "cd '$WD/repo' && bash '$PLUGIN_ROOT/$SCRIPT' --state '$L' merge"
  assert_failure 1
  assert_output "blocked reason=landed_path_in_stream task=DV1 stream=web"
}

@test "merge: a stream missing from facts.stream_branches blocks before any ref moves" {
  stream_edits
  commit_both
  jq '.facts.stream_branches = {service: "feature/s-service"}' "$L" > "$L.tmp" && mv "$L.tmp" "$L"
  local before; before=$(refs_snapshot)
  run --separate-stderr bash -c "cd '$WD/repo' && bash '$PLUGIN_ROOT/$SCRIPT' --state '$L' merge"
  assert_failure 1
  assert_output "blocked reason=stream_branch_missing task=DV1 stream=web"
  [ "$(refs_snapshot)" = "$before" ]
}

@test "commit and merge block a stream sitting on facts.branch, moving no ref" {
  git -C "$WD/wt-service" switch -q -c "$COMBINED"
  stream_edits
  local before; before=$(refs_snapshot)
  run --separate-stderr bash "$PLUGIN_ROOT/$SCRIPT" --state "$L" commit --task DV0 --message-file "$WD/msg.txt"
  assert_failure 1
  assert_output "blocked reason=stream_is_combined task=DV0 stream=service"
  [ "$(refs_snapshot)" = "$before" ]
  run git -C "$WD/wt-service" diff --cached --quiet
  assert_success
  jq --arg c "$COMBINED" '.facts.stream_branches = {service: $c, web: "feature/s-web"}' "$L" > "$L.tmp" && mv "$L.tmp" "$L"
  run --separate-stderr bash -c "cd '$WD/repo' && bash '$PLUGIN_ROOT/$SCRIPT' --state '$L' merge"
  assert_failure 1
  assert_output "blocked reason=stream_is_combined task=DV0 stream=service"
  [ "$(refs_snapshot)" = "$before" ]
  run git -C "$WD/repo" symbolic-ref --short HEAD
  assert_output "develop"
}

@test "continuity: an unmerged stream branch exits 1 and never writes diverged_cherry_pick" {
  stream_edits
  commit_both
  record_branches
  git -C "$WD/repo" switch -q -c "$COMBINED" develop
  git -C "$WD/repo" merge -q --no-ff --no-edit feature/s-service
  run --separate-stderr bash -c "cd '$WD/repo' && bash '$PLUGIN_ROOT/$PREFLIGHT' --state '$L' --context '$WD/ledger/.context' continuity"
  assert_failure 1
  [[ "$stderr" == *"stream web branch feature/s-web is not an ancestor of HEAD"* ]]
  run bash -c "grep -c diverged_cherry_pick '$WD/ledger/.context/logs/audit.jsonl' || true"
  assert_output "0"
}

@test "usage: unknown subcommand, missing --message-file, bad --task exit 2" {
  run --separate-stderr bash "$PLUGIN_ROOT/$SCRIPT" --state "$L" rebase
  assert_failure 2
  run --separate-stderr bash "$PLUGIN_ROOT/$SCRIPT" --state "$L" commit --task DV0
  assert_failure 2
  run --separate-stderr bash "$PLUGIN_ROOT/$SCRIPT" --state "$L" commit --task QA0 --message-file "$WD/msg.txt"
  assert_failure 2
  run --separate-stderr bash "$PLUGIN_ROOT/$SCRIPT" --state "$WD/none.json" plan
  assert_failure 3
}

@test "help: -h prints the header on stdout and exits 0" {
  run --separate-stderr bash "$PLUGIN_ROOT/$SCRIPT" -h
  assert_success
  assert_output --partial "stream_is_combined"
}

@test "the script names no forbidden git verb" {
  run bash -c "grep -vE '^[[:space:]]*#' '$PLUGIN_ROOT/$SCRIPT' \
    | grep -nE 'git [^|]*(push|reset|rebase|--amend|branch -[dD]|update-ref|stash|--no-verify|checkout|tag )'"
  assert_failure
}
