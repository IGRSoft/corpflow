#!/usr/bin/env bash
# adhoc-visual-evidence-selftest.sh — the `--self-test` harness for adhoc-visual-evidence.sh.
#
# SOURCED, never executed: adhoc-visual-evidence.sh loads this file only on the `--self-test`
# path, so the production path never pays for it. Sourcing leaves the caller's
# `$0` and every function it has already defined in scope — this file reads the
# caller's helpers and is not standalone.
#
# Contract: defines `run_self_tests`, returning 0 when every case passes.

# ---------- self-test -------------------------------------------------------
run_self_tests() {
  local pass=0 fail=0 self="$0"
  _ok()   { echo "adhoc-visual-evidence: $1 PASS"; pass=$((pass+1)); }
  _fail() { echo "adhoc-visual-evidence: $1 FAIL${2:+ — $2}"; fail=$((fail+1)); }

  # A repo with one commit on master and a checked-out feature branch, so
  # `master...HEAD` is a real PR-shaped diff rather than an empty one.
  _mk_repo() {
    local td; td=$(mktemp -d)
    git -C "$td" init -q -b master >/dev/null 2>&1
    git -C "$td" config user.email t@t; git -C "$td" config user.name t
    mkdir -p "$td/Views"
    printf 'a\n' > "$td/README.md"
    git -C "$td" add -A >/dev/null 2>&1
    git -C "$td" commit -qm base >/dev/null 2>&1
    git -C "$td" checkout -q -b feature >/dev/null 2>&1
    printf '%s' "$td"
  }

  # ---- t1: a docs-only diff emits nothing (the false-positive gate)
  local d1; d1=$(_mk_repo)
  printf 'b\n' >> "$d1/README.md"
  git -C "$d1" commit -qam docs >/dev/null 2>&1
  local o1; o1=$(WORKSPACE_ROOT="$d1" BASE_REF="master" bash "$self" --emit pr 2>/dev/null)
  if [ -z "$o1" ] && grep -q '"reason":"no_ui_surface"' "$d1/.context/logs/audit.jsonl" 2>/dev/null; then
    _ok "t1-docs-only-silent"
  else
    _fail "t1-docs-only-silent" "out='${o1:0:60}'"
  fi
  rm -rf "$d1"

  # ---- t2/t3/t4: capture-dependent arms.
  # cli-fallback's floor no longer writes a .txt placeholder, so on a host with no image
  # tool there is NOTHING to manifest and these arms have no capture to assert against.
  # Splitting them this way is the point of the fix: the un-migrated version read the
  # floor's exit 2 as a capture and manifested a .png that was never written.
  _has_image_tool() {
    command -v silicon > /dev/null 2>&1 || command -v magick > /dev/null 2>&1 \
      || command -v convert > /dev/null 2>&1
  }

  local d2; d2=$(_mk_repo)
  printf 'body { color: red }\n' > "$d2/Views/app.css"
  git -C "$d2" add -A >/dev/null 2>&1; git -C "$d2" commit -qm ui >/dev/null 2>&1
  local o2
  o2=$(WORKSPACE_ROOT="$d2" BASE_REF="master" ASSET_HOST_MODE=none DRY_RUN=1 \
       bash "$self" --emit pr 2>/dev/null)

  if _has_image_tool; then
    if printf '%s' "$o2" | grep -q '^## Visual evidence' \
       && ! printf '%s' "$o2" | grep -qE '\]\(\)|\]\(\.context/'; then
      _ok "t2-ui-emits-block"
    else
      _fail "t2-ui-emits-block" "$(printf '%s' "$o2" | head -6 | tr '\n' '~')"
    fi

    # ---- t3: rerun replays the cache instead of stacking a second capture
    local o3 caps
    o3=$(WORKSPACE_ROOT="$d2" BASE_REF="master" ASSET_HOST_MODE=none DRY_RUN=1 \
         bash "$self" --emit pr 2>/dev/null)
    caps=$(find "$d2/.context/images" -type f -name 'dv-*' 2>/dev/null | wc -l | tr -d ' ')
    if [ "$o3" = "$o2" ] && [ "$caps" = "1" ]; then
      _ok "t3-idempotent"
    else
      _fail "t3-idempotent" "caps=$caps same=$([ "$o3" = "$o2" ] && echo y || echo n)"
    fi

    # ---- t4: manifest satisfies the attacher's own schema check
    local mf; mf=$(find "$d2/.context/images" -name screenshots.md 2>/dev/null | head -1)
    if bash "$ATTACHER" --validate-manifest "$mf" >/dev/null 2>&1; then
      _ok "t4-manifest-schema"
    else
      _fail "t4-manifest-schema" "$(bash "$ATTACHER" --validate-manifest "$mf" 2>&1 | head -2 | tr '\n' '~')"
    fi
  else
    # ---- t2b: no image tool → no capture is CLAIMED. The regression this replaces:
    # exit 2 was read as success, so a manifest row named a .png that does not exist.
    local ghost=0 mf2
    mf2=$(find "$d2/.context/images" -name screenshots.md 2>/dev/null | head -1)
    if [ -n "$mf2" ]; then
      while IFS='|' read -r _ _ _ pth _; do
        pth=$(printf '%s' "$pth" | tr -d ' ')
        case "$pth" in
          dv-*) [ -e "$(dirname "$mf2")/$pth" ] || ghost=1 ;;
        esac
      done < "$mf2"
    fi
    if [ "$ghost" -eq 0 ] && ! printf '%s' "$o2" | grep -qE '\]\(\)|\.txt'; then
      _ok "t2b-no-tool-manifests-no-ghost-row"
    else
      _fail "t2b-no-tool-manifests-no-ghost-row" "ghost=$ghost out='$(printf '%s' "$o2" | head -3 | tr '\n' '~')'"
    fi
  fi
  rm -rf "$d2"

  # ---- t5: a worktask tree is refused, leaving FN's attachment the only one
  local d5; d5=$(_mk_repo)
  printf 'x\n' > "$d5/Views/app.css"
  git -C "$d5" add -A >/dev/null 2>&1; git -C "$d5" commit -qm ui >/dev/null 2>&1
  mkdir -p "$d5/.context"
  printf '{"version":1,"worktask_id":"wid-real","run_index":0}' > "$d5/.context/state.json"
  local o5; o5=$(WORKSPACE_ROOT="$d5" BASE_REF="master" bash "$self" --emit pr 2>/dev/null)
  if [ -z "$o5" ] && grep -q '"reason":"worktask_path"' "$d5/.context/logs/audit.jsonl" 2>/dev/null; then
    _ok "t5-worktask-refused"
  else
    _fail "t5-worktask-refused" "out='${o5:0:60}'"
  fi
  rm -rf "$d5"

  # ---- t7: a PNG capture renders as a hosted embed, not a bullet. Seeded on
  # disk because neither silicon nor ImageMagick is a suite prerequisite.
  local d7; d7=$(_mk_repo)
  printf 'x\n' > "$d7/Views/app.css"
  git -C "$d7" add -A >/dev/null 2>&1; git -C "$d7" commit -qm ui >/dev/null 2>&1
  mkdir -p "$d7/.context/images/adhoc-feature"
  printf 'x' > "$d7/.context/images/adhoc-feature/dv-01-pr-diff.png"
  local o7
  o7=$(WORKSPACE_ROOT="$d7" BASE_REF="master" ADHOC_ID=adhoc-feature \
       ASSET_HOST_MODE=raw ASSET_OWNER_REPO=o/r ASSET_REF=main DRY_RUN=1 \
       bash "$self" --emit pr 2>/dev/null)
  if printf '%s' "$o7" | grep -q '^!\[dv-01 ad-hoc PR diff.*\](https://raw\.githubusercontent\.com/'; then
    _ok "t7-png-embeds"
  else
    _fail "t7-png-embeds" "$(printf '%s' "$o7" | head -6 | tr '\n' '~')"
  fi
  rm -rf "$d7"

  # ---- t6: outside a git repo, --emit is silent and --detect says so
  local d6; d6=$(mktemp -d)
  local o6 j6
  o6=$(WORKSPACE_ROOT="$d6" bash "$self" --emit pr 2>/dev/null)
  j6=$(WORKSPACE_ROOT="$d6" bash "$self" --detect 2>/dev/null)
  if [ -z "$o6" ] && printf '%s' "$j6" | grep -q '"visual_surface":false'; then
    _ok "t6-no-git-silent"
  else
    _fail "t6-no-git-silent" "out='${o6:0:40}' json='$j6'"
  fi
  rm -rf "$d6"

  echo "adhoc-visual-evidence: self-test summary — pass=$pass fail=$fail"
  [ "$fail" -eq 0 ]
}
