#!/usr/bin/env bash
# @description land-artifacts-selftest.sh — the `--self-test` harness for
#   land-artifacts.sh, execed as a standalone process (never sourced) so the
#   reviewed script stays short. Builds two real git worktrees plus a temp
#   ledger and drives the CLI exactly as the orchestrator would.
#
# @exitcode 0  Every case passed ("ALL PASS" printed last).
# @exitcode 1  A case failed; the failing case is named on stderr.
#
# Minimum shell: bash 3.2+ (macOS default).

set -euo pipefail
IFS=$'\n\t'

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
LAND="$SELF_DIR/land-artifacts.sh"

TD=""
# shellcheck disable=SC2329 # invoked only through the EXIT/INT/TERM trap below
cleanup() {
  [ -n "$TD" ] && [ -d "$TD" ] && rm -rf -- "$TD"
}
trap cleanup EXIT INT TERM

fail() {
  printf >&2 'land-artifacts-selftest: FAIL: %s\n' "$*"
  exit 1
}

TD=$(mktemp -d -t land-artifacts-selftest-XXXXXX)

# ---------- shared fixture: one bare-ish main repo, two worktrees ----------
MAIN="$TD/main"
mkdir -p "$MAIN"
(
  cd "$MAIN"
  git init -q .
  git config user.email t@t.t
  git config user.name t
  printf 'seed\n' > seed.txt
  git add seed.txt
  git commit -qm init
)

PROD="$TD/producer"
CONS="$TD/consumer"
git -C "$MAIN" worktree add -q -b dv0-branch "$PROD" > /dev/null
git -C "$MAIN" worktree add -q -b dv1-branch "$CONS" > /dev/null

printf 'name: demo\n' > "$PROD/contract.yaml"
git -C "$PROD" add contract.yaml
git -C "$PROD" commit -qm 'stage contract.yaml' > /dev/null

# state.json: workspace_path on each row short-circuits workspace-root-banner.sh's
# banner resolution straight to these two worktrees (no orchestrator ledger needed).
LEDGER="$TD/state.json"
jq -n --arg prod "$PROD" --arg cons "$CONS" '{
  tasks: {
    DV0: {status: "completed", metadata: {workspace_path: $prod, produces: ["contract.yaml"]}},
    DV1: {status: "pending", blocked_by: ["DV0"],
          metadata: {workspace_path: $cons, consumes: [{from: "DV0", paths: ["contract.yaml"]}]}}
  }
}' > "$LEDGER"

run_land() {
  bash "$LAND" --state "$LEDGER" "$@"
}

# ---------- S1: happy path ----------
set +e
out=$(run_land --consumer DV1 2>&1)
rc=$?
set -e
[ "$rc" -eq 0 ] || fail "S1 happy path: expected exit 0, got $rc: $out"
[ -f "$CONS/contract.yaml" ] || fail "S1 happy path: dest not landed"
expect_sha=$(git -C "$PROD" cat-file blob "$(git -C "$PROD" rev-parse HEAD:contract.yaml)" | sha256sum | awk '{print $1}')
dest_sha=$(sha256sum < "$CONS/contract.yaml" | awk '{print $1}')
[ "$expect_sha" = "$dest_sha" ] || fail "S1 happy path: sha mismatch on landed file"
landed=$(jq -r '.tasks.DV1.metadata.landed_paths // [] | .[]?' "$LEDGER")
[ "$landed" = "contract.yaml" ] || fail "S1 happy path: landed_paths not recorded (got: $landed)"
rows=$(jq -c 'select(.action=="contract_landed" and .result=="ok")' "$TD/logs/audit.jsonl" 2> /dev/null | wc -l | tr -d ' ')
[ "$rows" = "1" ] || fail "S1 happy path: expected exactly one ok row, got $rows"
printf 'S1 happy path: ok\n'

# ---------- S2: sha mismatch (corrupted `git cat-file` stdout) ----------
S2_ROOT="$TD/s2"
mkdir -p "$S2_ROOT/producer" "$S2_ROOT/consumer"
git -C "$MAIN" worktree add -q -b dv0-s2 "$S2_ROOT/producer" > /dev/null
git -C "$MAIN" worktree add -q -b dv1-s2 "$S2_ROOT/consumer" > /dev/null
printf 'name: demo2\n' > "$S2_ROOT/producer/contract.yaml"
git -C "$S2_ROOT/producer" add contract.yaml
git -C "$S2_ROOT/producer" commit -qm 'stage contract.yaml' > /dev/null

S2_LEDGER="$TD/s2-state.json"
jq -n --arg prod "$S2_ROOT/producer" --arg cons "$S2_ROOT/consumer" '{
  tasks: {
    DV0: {status: "completed", metadata: {workspace_path: $prod, produces: ["contract.yaml"]}},
    DV1: {status: "pending", blocked_by: ["DV0"],
          metadata: {workspace_path: $cons, consumes: [{from: "DV0", paths: ["contract.yaml"]}]}}
  }
}' > "$S2_LEDGER"

# A `git` shim earlier on PATH: every subcommand passes through to the real git
# except `cat-file`, whose stdout is corrupted. write_blob anchors on git's own
# object id, so this proves a corrupted read cannot vouch for itself.
SHIMDIR="$TD/shimbin"
mkdir -p "$SHIMDIR"
REAL_GIT=$(command -v git)
cat > "$SHIMDIR/git" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "cat-file" ]; then
  "$REAL_GIT" "\$@" | sed 's/demo2/corrupted/'
  exit \${PIPESTATUS[0]}
fi
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$SHIMDIR/git"

set +e
out=$(PATH="$SHIMDIR:$PATH" bash "$LAND" --state "$S2_LEDGER" --consumer DV1 2>&1)
rc=$?
set -e
[ "$rc" -eq 1 ] || fail "S2 sha mismatch: expected exit 1, got $rc: $out"
[ -e "$S2_ROOT/consumer/contract.yaml" ] && fail "S2 sha mismatch: dest must not exist"
cstat=$(jq -r '.tasks.DV1.status' "$S2_LEDGER")
[ "$cstat" = "blocked" ] || fail "S2 sha mismatch: DV1 must be blocked, got $cstat"
reason=$(jq -r '.tasks.DV1.metadata.landing_error.reason // ""' "$S2_LEDGER")
[ "$reason" = "sha256_mismatch" ] || fail "S2 sha mismatch: expected sha256_mismatch, got $reason"
printf 'S2 sha mismatch: ok\n'

# ---------- S3: traversal refusal ----------
S3_ROOT="$TD/s3"
mkdir -p "$S3_ROOT/producer" "$S3_ROOT/consumer"
git -C "$MAIN" worktree add -q -b dv0-s3 "$S3_ROOT/producer" > /dev/null
git -C "$MAIN" worktree add -q -b dv1-s3 "$S3_ROOT/consumer" > /dev/null
mkdir -p "$S3_ROOT/producer/sub"
printf 'x\n' > "$S3_ROOT/producer/sub/x.txt"
git -C "$S3_ROOT/producer" add sub/x.txt
git -C "$S3_ROOT/producer" commit -qm 'stage sub/x.txt' > /dev/null

S3_LEDGER="$TD/s3-state.json"
jq -n --arg prod "$S3_ROOT/producer" --arg cons "$S3_ROOT/consumer" '{
  tasks: {
    DV0: {status: "completed", metadata: {workspace_path: $prod, produces: ["../x.txt"]}},
    DV1: {status: "pending", blocked_by: ["DV0"],
          metadata: {workspace_path: $cons, consumes: [{from: "DV0", paths: ["../x.txt"]}]}}
  }
}' > "$S3_LEDGER"

set +e
out=$(bash "$LAND" --state "$S3_LEDGER" --consumer DV1 2>&1)
rc=$?
set -e
[ "$rc" -eq 1 ] || fail "S3 traversal refusal: expected exit 1, got $rc: $out"
[ -e "$S3_ROOT/consumer/x.txt" ] && fail "S3 traversal refusal: nothing must be written outside consumes[]"
find "$S3_ROOT/consumer" -mindepth 1 -not -path '*/.git*' | grep -q . \
  && fail "S3 traversal refusal: consumer tree must stay empty"
reason=$(jq -r '.tasks.DV1.metadata.landing_error.reason // ""' "$S3_LEDGER")
[ "$reason" = "dotdot" ] || fail "S3 traversal refusal: expected dotdot, got $reason"
printf 'S3 traversal refusal: ok\n'

printf 'land-artifacts-selftest: ALL PASS\n'
exit 0
