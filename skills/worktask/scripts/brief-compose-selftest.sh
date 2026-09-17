#!/usr/bin/env bash
# brief-compose-selftest.sh — the `--self-test` harness for brief-compose.sh.
#
# SOURCED, never executed: brief-compose.sh loads this file only on the `--self-test`
# path, so the production path never pays for it. Sourcing leaves the caller's helpers
# ($0, plugin_root, etc.) in scope; this file is not standalone.
#
# Contract: defines `self_test`, which owns the exit for this invocation.

self_test() {
  local self_dir SELF td fail=0
  self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  SELF="$self_dir/brief-compose.sh"
  td=$(mktemp -d -t brief-compose-XXXXXX)
  # shellcheck disable=SC2064  # expand now: $td is local and gone by EXIT time otherwise
  trap "rm -rf '$td'" EXIT

  # extract_section <text> <marker> — the section body between <<<marker>>> and the
  # next <<<...>>> tag or EOF; mirrors cache-lint.sh's own extractor so a self-test
  # assertion reads sections the same way the prefix-lint that checks them does.
  extract_section() {
    local body="$1" marker="$2"
    awk -v m="$marker" '
      $0 == "<<<" m ">>>" { capture = 1; next }
      /^<<<.*>>>$/ && capture { exit }
      capture { print }
    ' <<< "$body"
  }

  check() {
    local label="$1"
    shift
    if "$@"; then
      printf 'ok: %s\n' "$label"
    else
      printf 'FAIL: %s\n' "$label" >&2
      fail=1
    fi
  }

  # Invoked indirectly as `check "<label>" str_eq …` — shellcheck cannot trace a command
  # name passed as a plain argument, so each is a false "never invoked" positive.
  # shellcheck disable=SC2329
  str_eq() { [ "$1" = "$2" ]; }
  # shellcheck disable=SC2329
  not_grep() { ! grep -q -- "$1" <<< "$2"; }
  # shellcheck disable=SC2329
  not_grep_i() { ! grep -qi -- "$1" <<< "$2"; }

  # ---- refs: a DV0 fixture — every non-identifier [5] line is a resolvable ref ----
  local d1="$td/ac1"
  mkdir -p "$d1/.context"
  cat > "$d1/.context/planning-0.md" << 'EOF'
## requirements

Fixture requirement text.

## acceptance-criteria

Fixture acceptance text.
EOF
  cat > "$d1/.context/state.json" << EOF
{
  "worktask_id": "brief-compose-selftest",
  "plan_file": ".context/planning-0.md",
  "run_index": 0,
  "tasks": {
    "DV0": {
      "metadata": {
        "stage": "DV",
        "agent": "system-developer:bash-developer",
        "model": "opus",
        "run_index": 0,
        "workspace_path": "$d1",
        "context_refs": ["planning-0.md#requirements"]
      }
    }
  }
}
EOF
  local out1 rc1=0
  out1=$(bash "$SELF" DV0 --state "$d1/.context/state.json" --orch-root "$d1" 2>/dev/null) || rc1=$?
  check "refs: DV0 fixture composes (exit 0)" [ "$rc1" -eq 0 ]

  local sec5 line bad_line="" ref_count=0
  sec5=$(extract_section "$out1" "task-description")
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      task_id:* | stage:* | agent:* | model:* | artifact:* | subject:*) continue ;;
      'ref: '*)
        ref_count=$((ref_count + 1))
        # A resolvable ref is shaped exactly one of two ways: "path:N" (file:line) or
        # "artifact#anchor" — anything else is a fact this brief did not actually check.
        case "${line#ref: }" in
          *:[0-9]*)
            case "${line#ref: }" in *'#'*) bad_line="$line" ;; esac
            ;;
          *'#'*) : ;;
          *) bad_line="$line" ;;
        esac
        ;;
      *) bad_line="$line" ;;
    esac
  done <<< "$sec5"
  check "refs: every non-identifier [5] line is 'ref: ' + file:line or artifact#anchor" [ -z "$bad_line" ]
  check "refs: [5] carries at least one ref" [ "$ref_count" -gt 0 ]

  # Each ref must be proven to RESOLVE, not merely shaped like one: brief-
  # compose.sh's own exit 0 is not evidence, since a guard bug could pass a ref it never
  # actually checked. This re-derives resolution independently, off the fixture's own
  # files, and never calls check_ref_resolves.
  local proot resolve_fail=""
  proot="$(cd "$self_dir/../../.." && pwd -P)"
  while IFS= read -r line; do
    case "$line" in
      'ref: '*)
        local rv="${line#ref: }"
        case "$rv" in
          *'#'*)
            local art="${rv%%#*}" anchor="${rv#*#}" found=0 hl
            local apath="$d1/.context/$art"
            if [ -f "$apath" ]; then
              while IFS= read -r hl; do
                if [ "$hl" = "## $anchor" ]; then
                  found=1
                  break
                fi
              done < "$apath"
            fi
            [ "$found" -eq 1 ] || resolve_fail="${resolve_fail}${rv} "
            ;;
          *:[0-9]*)
            local f="${rv%:*}" ln="${rv##*:}" n
            if [ -f "$proot/$f" ]; then
              n=$(wc -l < "$proot/$f" | tr -d ' ')
              if [ "$ln" -lt 1 ] || [ "$ln" -gt "$n" ]; then resolve_fail="${resolve_fail}${rv} "; fi
            else
              resolve_fail="${resolve_fail}${rv} "
            fi
            ;;
          *) resolve_fail="${resolve_fail}${rv} " ;;
        esac
        ;;
    esac
  done <<< "$sec5"
  check "refs: every [5] ref independently resolves " [ -z "$resolve_fail" ]

  # ---- guard: absolute-path guard — off-root fails closed, on-root passes ----
  local d2="$td/ac2"
  mkdir -p "$d2/.context"
  cp "$d1/.context/planning-0.md" "$d2/.context/planning-0.md"
  cat > "$d2/.context/state.json" << EOF
{
  "worktask_id": "brief-compose-selftest",
  "plan_file": ".context/planning-0.md",
  "run_index": 0,
  "tasks": {
    "DV0": {
      "metadata": {
        "stage": "DV",
        "agent": "system-developer:bash-developer",
        "model": "opus",
        "run_index": 0,
        "workspace_path": "$d2",
        "description": "touches /opt/elsewhere/x.md outside every allowed root"
      }
    }
  }
}
EOF
  local out2 err2 rc2=0
  err2=$(mktemp)
  out2=$(bash "$SELF" DV0 --state "$d2/.context/state.json" --orch-root "$d2" 2> "$err2") || rc2=$?
  check "guard: an off-root absolute path exits 1" [ "$rc2" -eq 1 ]
  check "guard: an off-root absolute path prints no stdout" [ -z "$out2" ]
  check "guard: an off-root absolute path names itself on stderr" grep -q '^brief-compose: ' "$err2"
  rm -f "$err2"

  local d3="$td/ac2b"
  mkdir -p "$d3/.context"
  cp "$d1/.context/planning-0.md" "$d3/.context/planning-0.md"
  cat > "$d3/.context/state.json" << EOF
{
  "worktask_id": "brief-compose-selftest",
  "plan_file": ".context/planning-0.md",
  "run_index": 0,
  "tasks": {
    "DV0": {
      "metadata": {
        "stage": "DV",
        "agent": "system-developer:bash-developer",
        "model": "opus",
        "run_index": 0,
        "workspace_path": "$d3",
        "description": "touches $d3/notes/ok.md, which sits under the fixture root"
      }
    }
  }
}
EOF
  local out3 rc3=0
  out3=$(bash "$SELF" DV0 --state "$d3/.context/state.json" --orch-root "$d3" 2>/dev/null) || rc3=$?
  check "guard: a path under WORKSPACE_ROOT passes" [ "$rc3" -eq 0 ]
  check "guard: a passing compose is non-empty" [ -n "$out3" ]

  # ---- fan-out: a two-stream DV fan-out — refs.dev in ascending task-id order, no override text ----
  local d4="$td/ac3"
  mkdir -p "$d4/.context"
  cp "$d1/.context/planning-0.md" "$d4/.context/planning-0.md"
  cat > "$d4/.context/development-0-service.md" << 'EOF'
---
handoff:
  stage: DV
  verdict: ok
---

## files-changed

fixture body (service)
EOF
  cat > "$d4/.context/development-0-web.md" << 'EOF'
---
handoff:
  stage: DV
  verdict: ok
---

## files-changed

fixture body (web)
EOF
  cat > "$d4/.context/state.json" << EOF
{
  "worktask_id": "brief-compose-selftest",
  "plan_file": ".context/planning-0.md",
  "run_index": 0,
  "tasks": {
    "DV0": {
      "metadata": {"stage": "DV", "model": "opus", "run_index": 0, "stream": "service",
        "artifact": ".context/development-0-service.md", "workspace_path": "$d4"}
    },
    "DV1": {
      "metadata": {"stage": "DV", "model": "opus", "run_index": 0, "stream": "web",
        "artifact": ".context/development-0-web.md", "workspace_path": "$d4"}
    },
    "DR0": {
      "metadata": {"stage": "DR", "agent": "corpflow:technical-lead", "model": "opus",
        "run_index": 0, "workspace_path": "$d4"}
    }
  }
}
EOF
  local out4 rc4=0
  out4=$(bash "$SELF" DR0 --state "$d4/.context/state.json" --orch-root "$d4" 2>/dev/null) || rc4=$?
  check "fan-out: DR0 fixture composes (exit 0)" [ "$rc4" -eq 0 ]

  local dev_refs
  dev_refs=$(grep -E '^ref: development-0-(service|web)\.md#files-changed$' <<< "$out4")
  local want_refs
  want_refs=$(printf 'ref: development-0-service.md#files-changed\nref: development-0-web.md#files-changed')
  check "fan-out: refs.dev is exactly service then web, in that order" str_eq "$dev_refs" "$want_refs"

  check "fan-out: no git-diff override text" not_grep_i "git diff" "$out4"
  check "fan-out: no bare development-0.md" not_grep 'development-0\.md' "$out4"
  check "fan-out: no hand-written anchor list" not_grep "Anchors:" "$out4"

  [ "$fail" -eq 0 ] || exit 1
  printf 'self-test OK\n'
}
