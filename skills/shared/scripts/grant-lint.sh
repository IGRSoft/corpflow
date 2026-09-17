#!/usr/bin/env bash
# @description grant-lint.sh — the one checker for the anchored script-grant shape
#   (`Bash(bash <token>/skills/<skill>/scripts/<name>.sh [<args>] *)`, where <token> is the
#   literal `CORPFLOW_GRANT_TOKEN` text below and the optional <args> is a fixed,
#   wildcard-free subcommand prefix such as `--consumer`) and, with `--invocations`, for the rule that a
#   runnable body mention of a granted script
#   must read the grant prefix byte for byte. `tests/shell/skills/plugin-root-refs.bats`
#   sources this file for its arm-S path rule, so the rule is defined once.
#
#   Sourcing defines functions only and runs nothing:
#     corpflow_grant_script_path_ok <path>       — 0 iff a well-formed script path
#     corpflow_grant_rule_ok <grant>              — 0 iff a well-formed anchored grant
#     corpflow_grant_matches <rule> <cmd> <root>  — documented-semantics matcher model
#
#   CLI (frontmatter scan): grant-lint.sh [--root <dir>]
#     Exit 0 clean, 1 one or more findings, 2 usage error or empty/unavailable
#     scan set. Finding line:
#       <file>:<lineno>: <class>: <text>
#     class one of: relative | shell-var | quoted | colon-star | bare-name |
#                   no-interpreter | malformed
#
#   CLI (body scan): grant-lint.sh --invocations [--root <dir>]
#     Same exit codes and finding shape, over runnable mentions of a script the
#     SAME file's frontmatter grants. A file with no anchored grant is not scanned.
#
#   Scan set: `git ls-files agents/*.md commands/*.md skills/*/SKILL.md` under
#   --root (default: the repo containing this script). A grant is read only from
#   frontmatter (line 1 literally `---`, closed by the next bare `---`), on a
#   `^(tools|allowed-tools):` line or a YAML block-list `- Bash(...)` item.
#   Non-script grants (no `skills/` and no `.sh`/`.py` in the token) are ignored.
#   An empty or unavailable scan set (git missing, --root not a git work tree,
#   or no tracked candidate files) is a usage error, never a silent clean pass.
#
#   Matcher model (`corpflow_grant_matches`), a model for tests only — it never
#   enforces anything and Claude Code's own matcher is the actual authority:
#   substitute the token via a prefix/suffix loop (never `${r//..}`); a trailing
#   `:*` reads as ` *`; ` *` matches the bare prefix or the prefix plus a space
#   and anything; no `*` is exact; any other `*` fails closed; any of
#   `& ; | < > ` + backtick + `$(` + LF + CR in the command text fail closed
#   (anywhere in the text, not just between simple commands); a leading
#   `VAR=` assignment fails closed but a `--flag=value` argument still matches;
#   the final decision compares with `[ = ]`/`[ != ]`, never `case`, so a
#   glob-shaped command text is never itself read as a pattern.
#
# @arg --root <dir>       Scan root (default: this file's own plugin root).
# @arg --invocations       Switch to the body-mention scan.
# @arg -h | --help         Show this header.
#
# @exitcode 0  clean (or sourced / --help)
# @exitcode 1  one or more findings
# @exitcode 2  usage error or empty/unavailable scan set
#
# Minimum shell: bash 3.2+ (macOS default). Requires git.

# CORPFLOW_GRANT_TOKEN is the ONLY place this file spells the placeholder: every
# other function reads $CORPFLOW_GRANT_TOKEN, never the literal brace text, so the
# arm-S "only mention" fixture in plugin-root-refs.bats has exactly one hit here.
# shellcheck disable=SC2016  # deliberately unexpanded: this is the literal token text
CORPFLOW_GRANT_TOKEN='${CLAUDE_PLUGIN_ROOT}'

# corpflow_grant_script_path_ok <path> — 0 iff skills/[a-z0-9-]+/scripts/[A-Za-z0-9_.-]+\.(sh|py), no '..'.
corpflow_grant_script_path_ok() {
  local p="$1"
  case "$p" in
    *..*) return 1 ;;
  esac
  [[ "$p" =~ ^skills/[a-z0-9-]+/scripts/[A-Za-z0-9_.-]+\.(sh|py)$ ]]
}

# _cf_gl_args_ok <path_term> — 0 iff <path_term> is a bare script path or a
# script path, one space and a literal argument prefix. The argument charset has
# no `*`, `$`, quotes or metacharacters, so a narrowed grant can never smuggle a
# second wildcard or an expansion; the path half is checked by the caller.
_cf_gl_args_ok() {
  local args args_re
  case "$1" in
    *' '*) args="${1#* }" ;;
    *) return 0 ;;
  esac
  args_re='^[A-Za-z0-9_.,=/-]+( [A-Za-z0-9_.,=/-]+)*$'
  [[ "$args" =~ $args_re ]]
}

# corpflow_grant_rule_ok <grant> — 0 iff Bash(<interp> <token>/<path>[ <args>] *)
# (<token> = the CORPFLOW_GRANT_TOKEN text); bash<->.sh, python3<->.py.
corpflow_grant_rule_ok() {
  local g="$1" interp path rest
  case "$g" in
    "Bash(bash ${CORPFLOW_GRANT_TOKEN}/"*)
      interp=bash
      rest="${g#"Bash(bash ${CORPFLOW_GRANT_TOKEN}/"}"
      ;;
    "Bash(python3 ${CORPFLOW_GRANT_TOKEN}/"*)
      interp=python3
      rest="${g#"Bash(python3 ${CORPFLOW_GRANT_TOKEN}/"}"
      ;;
    *) return 1 ;;
  esac
  case "$rest" in
    *' *)') path="${rest% \*)}" ;;
    *) return 1 ;;
  esac
  _cf_gl_args_ok "$path" || return 1
  path="${path%% *}"
  corpflow_grant_script_path_ok "$path" || return 1
  case "$interp:$path" in
    bash:*.sh | python3:*.py) return 0 ;;
    *) return 1 ;;
  esac
}

# _cf_gl_subst_token <string> <token> <replacement> — every occurrence of <token>
# in <string> replaced with <replacement>, via a prefix/suffix loop (never a
# single-shot `${s//token/repl}`, per the documented matcher model).
_cf_gl_subst_token() {
  local s="$1" tok="$2" rep="$3" out=""
  while :; do
    case "$s" in
      *"$tok"*)
        out="$out${s%%"$tok"*}$rep"
        s="${s#*"$tok"}"
        ;;
      *) break ;;
    esac
  done
  printf '%s' "$out$s"
}

# corpflow_grant_matches <rule> <cmd> <root> — 0 iff <cmd> (the Bash tool's exact
# command text) matches <rule> (a raw `Bash(...)` grant token) once the token is
# substituted for <root>. Never treats <cmd> as a glob pattern.
corpflow_grant_matches() {
  local rule="$1" cmd="$2" root="$3" inner pat prefix rest env_re

  # Fail-closed metacharacter set: any of these anywhere in the text means it
  # is not a single simple command (covers && via &, || via |, and redirection/
  # substitution/multi-line smuggling), so the rule matches command text, not
  # a shell script.
  case "$cmd" in
    *'&'* | *';'* | *'|'* | *'<'* | *'>'* | *'`'* | *'$('* | *$'\n'* | *$'\r'*)
      return 1 ;;
  esac
  # Only an anchored leading `VAR=` shell assignment fails; a `--flag=value`
  # argument anywhere else in the command must still be able to match.
  env_re='^[A-Za-z_][A-Za-z0-9_]*='
  if [[ "$cmd" =~ $env_re ]]; then return 1; fi

  case "$rule" in
    'Bash('*')') inner="${rule#Bash(}"; inner="${inner%)}" ;;
    *) return 1 ;;
  esac
  inner="$(_cf_gl_subst_token "$inner" "$CORPFLOW_GRANT_TOKEN" "$root")"

  case "$inner" in
    *:\*) pat="${inner%:\*} *" ;;
    *) pat="$inner" ;;
  esac

  case "$pat" in
    *' *')
      prefix="${pat% \*}"
      if [ "$cmd" = "$prefix" ]; then return 0; fi
      rest="${cmd#"$prefix "}"
      [ "$rest" != "$cmd" ]
      return
      ;;
    *'*'*) return 1 ;; # any other placement of * fails closed
    *) [ "$cmd" = "$pat" ] ;;
  esac
}

# --- everything below is CLI-only: the awk scan, classifiers and dispatch ---

_cf_gl_usage() {
  awk 'NR>1{ if (!/^#/) exit; sub(/^# ?/,""); print }' "$_CF_GL_SRC"
}

# _cf_gl_scan_tokens <file>... — emits "<file>\t<lineno>\t<Bash(...)>" for every
# Bash(...) token on a frontmatter grant line. One awk pass, resetting frontmatter
# state on FNR==1 per file; frontmatter counts only when line 1 is a bare `---`.
_cf_gl_scan_tokens() {
  awk '
    function strip_cr(s) { sub(/\r$/, "", s); return s }
    FNR == 1 { fm = (strip_cr($0) == "---") ? 1 : 0 }
    {
      line = strip_cr($0)
      if (FNR > 1 && fm == 1 && line ~ /^---[[:space:]]*$/) { fm = 0; next }
      if (!fm) next
      if (line !~ /^(tools|allowed-tools):/ && line !~ /^[[:space:]]*-[[:space:]]*Bash\(/) next
      rest = line
      while (match(rest, /Bash\([^)]*\)/)) {
        print FILENAME "\t" FNR "\t" substr(rest, RSTART, RLENGTH)
        rest = substr(rest, RSTART + RLENGTH)
      }
    }
  ' "$@"
}

# _cf_gl_is_script_candidate <token> — 0 iff the token is plausibly a script
# grant (mentions a script extension or a skills/ path); non-script grants
# (Bash(git:*), Bash(mkdir:*), ...) are silently ignored.
_cf_gl_is_script_candidate() {
  case "$1" in
    *skills/* | *.sh* | *.py*) return 0 ;;
    *) return 1 ;;
  esac
}

# _cf_gl_classify_grant <token> — prints one finding class for a Bash(...) grant
# token already known not to satisfy corpflow_grant_rule_ok.
_cf_gl_classify_grant() {
  local tok="$1" content interp path path_term term

  content="${tok#Bash(}"
  content="${content%)}"

  # Anchor-token-first: when the token sits in the canonical position, the only
  # possible defect left is the terminator (colon-star), never shell-var/quoted —
  # the token text itself is exactly right.
  for interp in bash python3; do
    case "$content" in
      "$interp ${CORPFLOW_GRANT_TOKEN}/"*)
        path_term="${content#"$interp ${CORPFLOW_GRANT_TOKEN}/"}"
        case "$path_term" in
          *' *') path="${path_term% \*}"; term="space" ;;
          *:\*) path="${path_term%:\*}"; term="colon" ;;
          *) printf 'malformed'; return ;;
        esac
        _cf_gl_args_ok "$path" || { printf 'malformed'; return; }
        path="${path%% *}"
        if corpflow_grant_script_path_ok "$path"; then
          case "$interp:$path" in
            bash:*.sh | python3:*.py)
              if [ "$term" = colon ]; then printf 'colon-star'; else printf 'malformed'; fi
              return
              ;;
            *) printf 'malformed'; return ;;
          esac
        fi
        printf 'malformed'
        return
        ;;
    esac
  done

  case "$content" in
    *'"'*) printf 'quoted'; return ;;
  esac
  case "$content" in
    *'$'*) printf 'shell-var'; return ;;
  esac

  case "$content" in
    *' *') path_term="${content% \*}"; term="space" ;;
    *:\*) path_term="${content%:\*}"; term="colon" ;;
    *) printf 'malformed'; return ;;
  esac

  case "$path_term" in
    bash\ */*) interp=bash; path="${path_term#bash }" ;;
    python3\ */*) interp=python3; path="${path_term#python3 }" ;;
    bash\ * | python3\ *) printf 'bare-name'; return ;;
    */*) printf 'no-interpreter'; return ;;
    *) printf 'bare-name'; return ;;
  esac

  case "$path" in
    skills/*)
      if [ "$term" = colon ]; then printf 'colon-star'; else printf 'relative'; fi
      ;;
    *) printf 'malformed' ;;
  esac
}

# _cf_gl_run_grants <file>... — prints findings, returns 1 iff any were printed.
_cf_gl_run_grants() {
  local found=0 file lineno tok class
  while IFS="$(printf '\t')" read -r file lineno tok; do
    [ -n "$file" ] || continue
    _cf_gl_is_script_candidate "$tok" || continue
    corpflow_grant_rule_ok "$tok" && continue
    class="$(_cf_gl_classify_grant "$tok")"
    printf '%s:%s: %s: %s\n' "$file" "$lineno" "$class" "$tok"
    found=1
  done < <(_cf_gl_scan_tokens "$@")
  if [ "$found" -eq 0 ]; then return 0; fi
  return 1
}

# --- --invocations: body-mention scan ---

# _cf_gl_file_grants <file> — prints "<interp>\t<path>" per anchored grant the
# file's own frontmatter holds (only grants that already pass corpflow_grant_rule_ok).
# An argument prefix is dropped: the body rule checks the anchored script prefix,
# so every narrowed grant of one script collapses to a single path line.
_cf_gl_file_grants() {
  local file lineno tok content interp
  while IFS="$(printf '\t')" read -r file lineno tok; do
    [ -n "$tok" ] || continue
    corpflow_grant_rule_ok "$tok" || continue
    content="${tok#Bash(}"
    content="${content%)}"
    for interp in bash python3; do
      case "$content" in
        "$interp ${CORPFLOW_GRANT_TOKEN}/"*)
          printf '%s\t%s\n' "$interp" "${content#"$interp ${CORPFLOW_GRANT_TOKEN}/"}" \
            | sed -E 's/ \*$//; s/ .*$//'
          ;;
      esac
    done
  done < <(_cf_gl_scan_tokens "$1") | sort -u
}

# _cf_gl_classify_invocation <line> <interp> <path> — prints a finding class on
# stdout and returns 1 when <line> mentions <path>'s basename in a form other
# than the exact anchored grant prefix; returns 0 (prints nothing) when the
# line carries the correct prefix; returns 2 when the basename is not mentioned
# at all (caller: not a candidate line for this grant).
_cf_gl_classify_invocation() {
  local line="$1" interp="$2" path="$3" base good
  base="${path##*/}"
  good="$interp $CORPFLOW_GRANT_TOKEN/$path"

  case "$line" in
    *"$good"*) return 0 ;;
  esac
  case "$line" in
    *"$base"*) ;;
    *) return 2 ;;
  esac
  case "$line" in
    *'"'*"$base"* | *"$base"*'"'*) printf 'quoted'; return 1 ;;
  esac
  case "$line" in
    *'$'*"$base"*) printf 'shell-var'; return 1 ;;
  esac
  case "$line" in
    *"$interp $path"*) printf 'relative'; return 1 ;;
  esac
  case "$line" in
    *"$path"*) printf 'no-interpreter'; return 1 ;;
  esac
  printf 'bare-name'
  return 1
}

# _cf_gl_run_invocations <file>... — prints findings, returns 1 iff any were printed.
_cf_gl_run_invocations() {
  local found=0 file
  for file in "$@"; do
    local grants
    grants="$(_cf_gl_file_grants "$file")"
    [ -n "$grants" ] || continue

    local fm=1 first=1 infence=0 lineno=0 line trimmed class rc interp path
    while IFS= read -r line || [ -n "$line" ]; do
      lineno=$((lineno + 1))
      line="${line%$'\r'}"
      if [ "$first" -eq 1 ]; then
        first=0
        [ "$line" = "---" ] || fm=0
        continue
      fi
      if [ "$fm" -eq 1 ]; then
        [[ "$line" =~ ^---[[:space:]]*$ ]] && fm=0
        continue
      fi
      trimmed="${line#"${line%%[![:space:]]*}"}"
      case "$trimmed" in
        '```'*) infence=$((1 - infence)); continue ;;
      esac
      [ "$infence" -eq 1 ] || case "$trimmed" in
        'Run `'* | 'run `'* | *'invoke `'*) ;;
        *) continue ;;
      esac
      while IFS="$(printf '\t')" read -r interp path; do
        [ -n "$path" ] || continue
        # `trap - ERR` inside the substitution subshell, plus `|| rc=$?` on the
        # assignment itself: classify's own return 1/2 is a normal signal, not
        # a script error, and either guard alone still lets the other one fire.
        rc=0
        class="$(trap - ERR; _cf_gl_classify_invocation "$line" "$interp" "$path")" || rc=$?
        [ "$rc" -eq 1 ] || continue
        printf '%s:%s: %s: %s\n' "$file" "$lineno" "$class" "$line"
        found=1
      done <<< "$grants"
    done < "$file"
  done
  if [ "$found" -eq 0 ]; then return 0; fi
  return 1
}

_cf_gl_main() {
  set -Eeuo pipefail
  trap 'printf >&2 "error: %s:%d: exit %d\n" "${BASH_SOURCE[0]}" "$LINENO" "$?"' ERR

  local root="" invocations=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --root)
        [ "$#" -ge 2 ] || { _cf_gl_usage >&2; exit 2; }
        root="$2"
        shift 2
        ;;
      --invocations) invocations=1; shift ;;
      -h | --help)
        _cf_gl_usage
        exit 0
        ;;
      *)
        _cf_gl_usage >&2
        exit 2
        ;;
    esac
  done

  if [ -z "$root" ]; then
    root="$(CDPATH='' cd -- "$(dirname -- "$_CF_GL_SRC")/../../.." 2> /dev/null && pwd -P)" \
      || { printf >&2 'grant-lint.sh: could not resolve a default --root\n'; exit 2; }
  fi
  [ -d "$root" ] || { printf >&2 'grant-lint.sh: --root %s is not a directory\n' "$root"; exit 2; }

  local files=()
  while IFS= read -r -d '' f; do
    files+=("$root/$f")
  done < <(cd "$root" && git ls-files -z -- 'agents/*.md' 'commands/*.md' 'skills/*/SKILL.md' 2> /dev/null)

  if [ "${#files[@]}" -eq 0 ]; then
    # Fail closed, not clean: a repo with no tracked candidate files (git
    # missing, --root outside a work tree, or nothing tracked yet) must never
    # read the same as "scanned and found nothing".
    printf >&2 'grant-lint.sh: no files to scan under --root %s (git missing, --root not a git work tree, or no tracked agents/*.md, commands/*.md, skills/*/SKILL.md)\n' \
      "$root"
    exit 2
  fi

  local rc=0
  if [ "$invocations" -eq 1 ]; then
    _cf_gl_run_invocations "${files[@]}" || rc=$?
  else
    _cf_gl_run_grants "${files[@]}" || rc=$?
  fi
  [ "$rc" -eq 0 ] && exit 0
  exit 1
}

_CF_GL_SRC="${BASH_SOURCE[0]:-$0}"

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  _cf_gl_main "$@"
fi
