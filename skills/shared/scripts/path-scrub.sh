#!/usr/bin/env bash
# @description path-scrub.sh — the one definition of the absolute host-path pattern,
#   and the token-level scrub every GitHub-publishing surface runs last. It rewrites
#   the path token and never drops a line, so it reaches paths a whitespace-anchored
#   line rule cannot see.
#
#   Rewrites, longest known path first:
#     root   $WORKSPACE_ROOT, `git rev-parse --show-toplevel`, and the main worktree
#            from resolve-root.sh --root, each in its given, physical (`pwd -P`) and
#            verified logical form. `<root>/a/b` becomes `a/b`; a bare `<root>` becomes `.`.
#     other  a token opening with CORPFLOW_HOST_PATH_ERE or CORPFLOW_DRIVE_PATH_ERE, or
#            with the literal $HOME / $TMPDIR value, becomes `[local-path]` as a whole,
#            so no user, volume or project name survives. The placeholder has no `/`,
#            so pr-body-lint.sh P1 never flags it and a second pass leaves it alone.
#
#   Token start: line start, a `file://` or `file://localhost` prefix in any case (the
#   prefix is consumed with the path), or any character except letters, digits and
#   `. ~ / \ % @ # ? + -`, which can continue a URL or relative path. So
#   `https://host/tmp/x`, `skills/a.sh` and `.context/x.md` stay intact.
#   Token end: whitespace or `` ` ' " ( ) [ ] < > { } , ; | * ``. Trailing `. , : ; ! ?`
#   stay outside the token, so `<root>.` at a sentence end becomes `..`.
#   Not covered: the tail after a space inside a path; `~/` paths.
#
#   Roots and literals are compared with substr, never compiled into a regex: a
#   checkout named `a+b[1]` must match itself and nothing else. The scrub is idempotent.
#
#   Sourcing defines, never runs: corpflow_path_scrub, CORPFLOW_HOST_PATH_ERE and
#   CORPFLOW_DRIVE_PATH_ERE (both exported). Consumers read the EREs through awk
#   ENVIRON[], never `awk -v`: BSD awk rewrites backslash escapes in -v values and the
#   drive-letter ERE ends in one. Consumers source this file after a `[ -r ]` check,
#   because `.` on a missing file exits the shell before any guard runs, and fail
#   closed when the file or the function is missing.
#
# @arg (none)       Scrub stdin to stdout.
# @arg --self-test  Run the embedded fixture suite.
# @arg -h | --help  Show this header.
#
# @env WORKSPACE_ROOT  Rebased to repo-relative form when set.
# @env HOME, TMPDIR    Literal values are replaced with [local-path] when absolute.
#
# @exitcode 0  Scrubbed (or self-test passed).
# @exitcode 2  Usage error, or a self-test failure.
#
# Minimum shell: bash 3.2+ (macOS default). awk: BSD awk or gawk.

CORPFLOW_HOST_PATH_ERE='/(Users|home|tmp|var|opt|etc|root|Volumes|mnt|media|private|srv)/'
# The two backslashes are the regex for one literal backslash, not a quote escape.
# shellcheck disable=SC1003
CORPFLOW_DRIVE_PATH_ERE='[A-Za-z]:\\'
export CORPFLOW_HOST_PATH_ERE CORPFLOW_DRIVE_PATH_ERE

_CF_PS_SRC="${BASH_SOURCE[0]:-$0}"
_CF_PS_DIR="$(CDPATH='' cd -- "$(dirname -- "$_CF_PS_SRC")" 2> /dev/null && pwd -P)" || _CF_PS_DIR=""

_cf_ps_norm() {
  local p="$1"
  while :; do
    case "$p" in
      /) break ;;
      */) p="${p%/}" ;;
      *) break ;;
    esac
  done
  printf '%s' "$p"
}

_cf_ps_phys() {
  CDPATH='' cd -- "$1" 2> /dev/null && pwd -P
}

# Prints "<kind>\t<path>". Anything that is not an absolute path deeper than `/` is
# dropped: an empty or `/` entry would rewrite every path in the body.
_cf_ps_emit_one() {
  local nl=$'\n' tab=$'\t'
  case "$2" in
    /?*) ;;
    *) return 0 ;;
  esac
  case "$2" in
    *"$nl"* | *"$tab"*) return 0 ;;
  esac
  printf '%s\t%s\n' "$1" "$2"
}

# git answers with physical paths, but a body usually carries the spelling the user
# typed. Logical spellings come from a logical/physical pair the environment already
# holds, or from macOS's /private firmlinks, and each is emitted only if it resolves
# back to the same physical root, so nothing is added on the strength of a guess.
_cf_ps_aliases() {
  local kind="$1" r="$2" l p c
  for l in "${PWD:-}" "${WORKSPACE_ROOT:-}" "${HOME:-}"; do
    l="$(_cf_ps_norm "$l")"
    case "$l" in
      /?*) ;;
      *) continue ;;
    esac
    p="$(_cf_ps_phys "$l")" || continue
    [ -n "$p" ] && [ "$p" != "$l" ] || continue
    case "$r" in
      "$p") c="$l" ;;
      "$p"/*) c="$l${r#"$p"}" ;;
      *) continue ;;
    esac
    [ "$(_cf_ps_phys "$c")" = "$r" ] && _cf_ps_emit_one "$kind" "$c"
  done
  case "$r" in
    /private/var/* | /private/tmp/* | /private/etc/*)
      c="${r#/private}"
      [ "$(_cf_ps_phys "$c")" = "$r" ] && _cf_ps_emit_one "$kind" "$c"
      ;;
  esac
  return 0
}

# One candidate in its given spelling, its physical form, and the verified logical
# spellings of that physical form.
_cf_ps_emit() {
  local kind="$1" p phys
  p="$(_cf_ps_norm "$2")"
  _cf_ps_emit_one "$kind" "$p"
  [ -d "$p" ] || return 0
  phys="$(_cf_ps_phys "$p")" || return 0
  [ -n "$phys" ] && [ "$phys" != "/" ] || return 0
  [ "$phys" != "$p" ] && _cf_ps_emit_one "$kind" "$phys"
  _cf_ps_aliases "$kind" "$phys"
  return 0
}

_cf_ps_entries() {
  local r
  _cf_ps_emit R "${WORKSPACE_ROOT:-}"
  if command -v git > /dev/null 2>&1; then
    r="$(git rev-parse --show-toplevel 2> /dev/null)" && _cf_ps_emit R "$r"
    if [ -n "$_CF_PS_DIR" ] && [ -r "$_CF_PS_DIR/resolve-root.sh" ]; then
      r="$(bash "$_CF_PS_DIR/resolve-root.sh" --root 2> /dev/null)" && _cf_ps_emit R "$r"
    fi
  fi
  _cf_ps_emit L "${HOME:-}"
  _cf_ps_emit L "${TMPDIR:-}"
  return 0
}

# stdin -> stdout. Runs in a subshell so a caller's set -e/-u/pipefail and IFS neither
# leak in nor get changed.
corpflow_path_scrub() (
  set +e +u
  IFS=$' \t\n'
  _CF_PS_ENTRIES="$(_cf_ps_entries)"
  export _CF_PS_ENTRIES
  CORPFLOW_HOST_PATH_ERE="$CORPFLOW_HOST_PATH_ERE" \
    CORPFLOW_DRIVE_PATH_ERE="$CORPFLOW_DRIVE_PATH_ERE" \
    LC_ALL=C awk '
    function is_term(ch) {
      return ch == "" || ch ~ /[[:space:]]/ || index(TERM, ch) > 0
    }
    function continues(ch) {
      return ch != "" && ch ~ /[A-Za-z0-9._~+-]/
    }
    # True when s from position j holds only sentence punctuation before a terminator.
    function ends_here(s, j,    ch) {
      while ((ch = substr(s, j, 1)) != "" && index(".,:;!?", ch) > 0) j++
      return is_term(ch)
    }
    function token_len(s,    j, n) {
      n = length(s)
      j = 1
      while (j <= n && !is_term(substr(s, j, 1))) j++
      j = j - 1
      while (j > 1 && substr(s, j, 1) ~ /[.,:;!?]/) j--
      return j
    }
    # Sets REPL and RKIND; returns how many characters of s the match consumes, or 0.
    function try_entries(s,    k, p, pl, nc, nn) {
      for (k = 1; k <= NE; k++) {
        p = EPATH[k]
        pl = length(p)
        if (substr(s, 1, pl) != p) continue
        nc = substr(s, pl + 1, 1)
        if (EKIND[k] == "R") {
          if (nc == "/") {
            nn = substr(s, pl + 2, 1)
            RKIND = "R"
            if (is_term(nn)) { REPL = "."; return pl + 1 }
            REPL = ""
            return pl + 1
          }
          if (!continues(nc) || ends_here(s, pl + 1)) { REPL = "."; RKIND = "R"; return pl }
        } else if (nc == "/" || !continues(nc) || ends_here(s, pl + 1)) {
          REPL = "[local-path]"
          RKIND = "L"
          return token_len(s)
        }
      }
      return 0
    }
    BEGIN {
      TERM = "`\047\"()[]<>{},;|*"
      HOST = "^" ENVIRON["CORPFLOW_HOST_PATH_ERE"]
      DRIVE = "^" ENVIRON["CORPFLOW_DRIVE_PATH_ERE"]
      n = split(ENVIRON["_CF_PS_ENTRIES"], raw, "\n")
      NE = 0
      for (k = 1; k <= n; k++) {
        t = index(raw[k], "\t")
        if (t == 0) continue
        kind = substr(raw[k], 1, t - 1)
        p = substr(raw[k], t + 1)
        if (p == "") continue
        # A path that is both a root and HOME/TMPDIR rebases: the repo-relative form
        # is the more useful one and carries no identity.
        if (p in SEEN) { if (kind == "R") EKIND[SEEN[p]] = "R"; continue }
        NE++
        EPATH[NE] = p
        EKIND[NE] = kind
        SEEN[p] = NE
      }
      # Longest first, so a worktree nested inside the main checkout or under HOME
      # rebases against itself rather than against its parent.
      for (a = 2; a <= NE; a++) {
        tp = EPATH[a]; tk = EKIND[a]
        b = a - 1
        while (b >= 1 && length(EPATH[b]) < length(tp)) {
          EPATH[b + 1] = EPATH[b]; EKIND[b + 1] = EKIND[b]
          b--
        }
        EPATH[b + 1] = tp; EKIND[b + 1] = tk
      }
      for (k = 1; k <= NE; k++) SEEN[EPATH[k]] = k
    }
    {
      line = $0
      out = ""
      L = length(line)
      i = 1
      # After a rebase consumed "<root>/", the next character starts a fresh token:
      # without this, "<root>//Users/x" would surface "/Users/x" only on a second pass.
      forced = 0
      while (i <= L) {
        c = substr(line, i, 1)
        if (c == "/" || (c ~ /[A-Za-z]/ && substr(line, i + 1, 2) == ":\\")) {
          prev = (i == 1) ? "" : substr(line, i - 1, 1)
          glen = 0
          if (i > 16 && tolower(substr(line, i - 16, 16)) == "file://localhost") glen = 16
          else if (i > 7 && tolower(substr(line, i - 7, 7)) == "file://") glen = 7
          if (forced || i == 1 || glen || prev !~ /[A-Za-z0-9.~\/\\%@#?+-]/) {
            rest = substr(line, i)
            adv = try_entries(rest)
            if (adv == 0 && (match(rest, HOST) || match(rest, DRIVE))) {
              REPL = "[local-path]"
              RKIND = "E"
              adv = token_len(rest)
            }
            if (adv > 0) {
              if (glen && substr(out, length(out) - glen + 1) == substr(line, i - glen, glen)) out = substr(out, 1, length(out) - glen)
              out = out REPL
              i += adv
              forced = (RKIND == "R" && REPL == "")
              continue
            }
          }
        }
        forced = 0
        out = out c
        i++
      }
      print out
    }
  '
)

_cf_ps_usage() {
  awk 'NR>1{ if (!/^#/) exit; sub(/^# ?/,""); print }' "$_CF_PS_SRC"
}

_cf_ps_self_test() {
  local tmp pass=0 fail=0 root phys meta out want corpus once twice
  tmp="$(mktemp -d)" || {
    printf >&2 'path-scrub.sh --self-test: mktemp -d failed\n'
    return 2
  }
  # Values expanded now: tmp is a function local and is gone when the trap fires.
  # shellcheck disable=SC2064
  trap "rm -rf '${tmp}'" EXIT INT TERM
  root="$tmp/wt"
  mkdir -p "$root/skills" "$tmp/outside"
  phys="$(cd "$root" && pwd -P)"
  meta='/nonexistent-cf/a+b[1].c'

  # [VAR=value | -VAR]... A function, not inline: bash 3.2 cannot parse a `case`
  # arm like `-*)` inside a command substitution.
  _cf_ps_apply_env() {
    local kv
    for kv in "$@"; do
      case "$kv" in
        -*) unset "${kv#-}" ;;
        *) export "${kv?}" ;;
      esac
    done
  }

  # <label> <input> <want> [VAR=value | -VAR]... — runs outside any repository so
  # only the roots the case declares can rebase.
  _cf_ps_check() {
    local label="$1" input="$2" expect="$3" got
    shift 3
    got="$(
      cd "$tmp/outside" || exit 1
      export GIT_CEILING_DIRECTORIES="$tmp"
      unset WORKSPACE_ROOT TMPDIR
      export HOME="$tmp/nohome"
      _cf_ps_apply_env "$@"
      printf '%s' "$input" | corpflow_path_scrub
    )"
    if [ "$got" = "$expect" ]; then
      printf '%s: ok\n' "$label"
      pass=$((pass + 1))
    else
      printf >&2 '%s: FAIL\n  input: %s\n  want:  %s\n  got:   %s\n' "$label" "$input" "$expect" "$got"
      fail=$((fail + 1))
    fi
  }

  _cf_ps_check "host path, root path and .context path" \
    "See /Users/me/notes.md and $root/skills/a.sh and .context/planning-0.md" \
    "See [local-path] and skills/a.sh and .context/planning-0.md" "WORKSPACE_ROOT=$root"
  _cf_ps_check "physical form of a root rebases" \
    "Edit $phys/skills/a.sh" "Edit skills/a.sh" "WORKSPACE_ROOT=$root"
  _cf_ps_check "bare root and root glued to a line number" \
    "at $root and $root:12" "at . and .:12" "WORKSPACE_ROOT=$root"
  # The backticks are the markdown code span under test, not a substitution.
  # shellcheck disable=SC2016
  _cf_ps_check "code-spanned path" 'Ref `/Users/me/x.md` here' 'Ref `[local-path]` here'
  _cf_ps_check "punctuation-glued path" 'Mounted (/Volumes/x/y), "/tmp/z" and a=/srv/q.' \
    'Mounted ([local-path]), "[local-path]" and a=[local-path].'
  _cf_ps_check "file:// scheme" 'Open file:///Users/x/y.md now' 'Open [local-path] now'
  _cf_ps_check "file://localhost scheme" 'file://localhost/Users/x/y.md' '[local-path]'
  _cf_ps_check "upper-case file:// scheme" 'FILE:///Users/x' '[local-path]'
  _cf_ps_check "bare root and HOME literal at a sentence end" \
    "Worktree at $meta. Home is /data/u1." "Worktree at .. Home is [local-path]." \
    "WORKSPACE_ROOT=$meta" "HOME=/data/u1"
  _cf_ps_check "https URL containing /tmp/ is intact" \
    'See https://example.com/tmp/x and https://github.com/o/r/blob/main/Users/y' \
    'See https://example.com/tmp/x and https://github.com/o/r/blob/main/Users/y'
  _cf_ps_check "drive letter" 'Path C:\Users\me\x.md, done' 'Path [local-path], done'
  _cf_ps_check "root with regex metacharacters matches only itself" \
    "A $meta/skills/a.sh B /nonexistent-cf/aab1xc/skills/a.sh" \
    "A skills/a.sh B /nonexistent-cf/aab1xc/skills/a.sh" "WORKSPACE_ROOT=$meta"
  _cf_ps_check "non-standard HOME literal, prefix-safe" \
    'Home /data/u1/proj/x.md and /data/u10/x.md' \
    'Home [local-path] and /data/u10/x.md' "HOME=/data/u1"
  _cf_ps_check "unset HOME" 'Ref /home/me/x and skills/b.sh' 'Ref [local-path] and skills/b.sh' "-HOME"
  _cf_ps_check "relative paths and prose are intact" \
    'Edit skills/worktask/scripts/x.sh; srv and media; /usr/bin/env bash' \
    'Edit skills/worktask/scripts/x.sh; srv and media; /usr/bin/env bash'
  _cf_ps_check "nested root prefers the longest" \
    "x $root/inner/skills/c.sh" "x skills/c.sh" "WORKSPACE_ROOT=$root/inner" "HOME=$root"
  _cf_ps_check "empty input" "" ""

  # <label> <got> <want> — for results computed outside _cf_ps_check.
  _cf_ps_eq() {
    if [ "$2" = "$3" ]; then
      printf '%s: ok\n' "$1"
      pass=$((pass + 1))
    else
      printf >&2 '%s: FAIL\n  want: %s\n  got:  %s\n' "$1" "$3" "$2"
      fail=$((fail + 1))
    fi
  }

  corpus="See /Users/me/notes.md, ($root/skills/a.sh) $root//Users/q $root/$root/x File://LocalHost/Users/me/z.md
file:///tmp/y \`C:\\x\` [/Volumes/v] https://h/tmp/z $root"
  once="$(cd "$tmp/outside" && printf '%s\n' "$corpus" \
    | GIT_CEILING_DIRECTORIES="$tmp" WORKSPACE_ROOT="$root" corpflow_path_scrub)"
  twice="$(cd "$tmp/outside" && printf '%s\n' "$once" \
    | GIT_CEILING_DIRECTORIES="$tmp" WORKSPACE_ROOT="$root" corpflow_path_scrub)"
  want="See [local-path], (skills/a.sh) [local-path] x [local-path]
[local-path] \`[local-path]\` [[local-path]] https://h/tmp/z ."
  _cf_ps_eq "one pass over the mixed corpus" "$once" "$want"
  _cf_ps_eq "idempotent" "$twice" "$once"

  out="$(bash "$_CF_PS_DIR/path-scrub.sh" --bogus < /dev/null 2> /dev/null)"
  if [ "$?" -eq 2 ] && [ -z "$out" ]; then
    printf 'usage error exits 2: ok\n'
    pass=$((pass + 1))
  else
    printf >&2 'usage error exits 2: FAIL\n'
    fail=$((fail + 1))
  fi

  printf 'path-scrub.sh --self-test: %d passed, %d failed\n' "$pass" "$fail"
  [ "$fail" -eq 0 ] || return 2
  return 0
}

_cf_ps_main() {
  set -Eeuo pipefail
  case "${1:-}" in
    "") [ "$#" -le 1 ] || {
      _cf_ps_usage >&2
      exit 2
    } ;;
    --self-test)
      [ "$#" -eq 1 ] || {
        _cf_ps_usage >&2
        exit 2
      }
      set +e
      _cf_ps_self_test
      exit $?
      ;;
    -h | --help)
      _cf_ps_usage
      exit 0
      ;;
    *)
      _cf_ps_usage >&2
      exit 2
      ;;
  esac
  corpflow_path_scrub
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  _cf_ps_main "$@"
fi
