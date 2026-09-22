#!/usr/bin/env bash
# @description autonomy-preflight.sh — lists every human dependency an unattended
#   /worktask would hit (permission grants, evidence tools, broken toolchains) in ONE
#   message before anything is seeded, then records the passing result after the seed.
#
#   Check mode is read-only by contract: it writes nothing under any .context/ and
#   nothing outside one mktemp -d under TMPDIR that it removes on exit. Every check runs
#   before the verdict, so the operator fixes everything in one round instead of
#   discovering one stop per relaunch. Probes never mutate: `git push --dry-run
#   --no-verify`, `gh auth status`, `gh repo view --json viewerPermission`; merge and
#   reset grants are read from settings rules only, because an auto-mode classifier
#   verdict cannot be asked ahead of time. It never writes a settings file; a missing
#   grant prints the exact rule to add.
#
#   A missing evidence tool FAILS unless it was named in --accept-absent at launch.
#   That flag is the only source of `accepted:true`, so a recorded absent tool always
#   means a human chose it, never a silent default.
#
#   Rules are read with precedence user < project < project-local < managed. Deny and
#   ask rules fail any check they match (an ask rule is a prompt nobody will answer).
#   An allow rule matches in the forms `Bash`, `Bash(*)`, `Bash(<prefix>:*)` and
#   `Bash(<glob with *>)`, tested against a representative invocation carrying
#   arguments, so an exact `Bash(gh pr merge)` rule does not count.
#
# @arg --auto <list>              Resolved /worktask --auto values (comma list, brackets ok).
#                                 Neither plan nor finalization => result=skipped.
# @arg --platform <p[,p]>         Platforms whose evidence/toolchain chain is checked.
# @arg --harness                  Also require the `git reset --hard` grant.
# @arg --accept-absent <t[,t]>    Evidence tools allowed to be missing: renderer (all of
#                                 silicon, magick, convert; each also nameable alone),
#                                 playwright, playwright-browser, adb-device, simulator,
#                                 xcodebuildmcp. An unknown token exits 2 before any probe.
# @arg --record <buffer>          Record mode: merge the buffer's passing result_json into
#                                 <context>/state.json metadata.preflight and append the
#                                 audit rows. Requires --context.
# @arg --context <dir>            Existing .context directory holding state.json.
# @arg --candidates <scan-buffer> Record mode: preflight-issue-scan.sh output to record as
#                                 one preflight_issue_candidates row.
# @arg --self-test                Run the embedded fixture suite.
# @arg -h | --help                Show this header.
#
# @env GH_BIN, GIT_BIN                 Binaries probed (default gh, git).
# @env AUTONOMY_PREFLIGHT_TIMEOUT      Seconds bounding each gh/git/tool probe (default 20).
# @env AUTONOMY_PREFLIGHT_SETTINGS     Colon list of settings files, lowest precedence first;
#                                      replaces every default source.
# @env AUTONOMY_PREFLIGHT_MCP_CONFIGS  Colon list of MCP config files (default user
#                                      .claude.json plus each project's .mcp.json).
# @env AUTONOMY_PREFLIGHT_PLUGINS_FILE installed_plugins.json path.
# @env CLAUDE_CONFIG_DIR, CLAUDE_PROJECT_DIR, DEVELOPER_DIR, ANDROID_HOME,
#      ANDROID_SDK_ROOT, PLAYWRIGHT_BROWSERS_PATH  Honoured as their tools honour them.
# @env MILESTONE_MODE                  1 => result=skipped reason=milestone_mode.
#
# @stdout Check mode: on failure one block (`preflight_failures=<n>` then one entry per
#         failed check with its fix lines); on a pass with accepted tools one
#         `accepted_absent=<t[,t]>` line; always last `result_json=<compact json>`
#         ({version:1,result,ran_at,platforms,checks[{id,kind,status,detail}],
#         tools_absent[{tool,platform,accepted}]}). Skips print `result=skipped` and
#         `reason=` only. Record mode prints one `recorded=<what>` line per write.
#
# @exitcode 0  Check passed, skipped, or record written.
# @exitcode 1  Any check failed; or record refused/failed.
# @exitcode 2  Usage error.
#
# Minimum shell: bash 3.2+ (macOS default).

set -uo pipefail

SELF="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$SELF")" 2> /dev/null && pwd -P)" || SCRIPT_DIR=""
# The self-test re-runs this file after cd-ing into a fixture, so a relative path would break.
[ -n "$SCRIPT_DIR" ] && SELF="$SCRIPT_DIR/$(basename -- "$SELF")"

# Advisory tier (AD-1): a missing lib degrades every host_os call to "unknown" rather
# than taking this preflight down — every case below already has a default arm for it.
if [ -n "$SCRIPT_DIR" ] && [ -r "$SCRIPT_DIR/host-os-lib.sh" ]; then
  # shellcheck source=host-os-lib.sh
  . "$SCRIPT_DIR/host-os-lib.sh"
fi
command -v host_os > /dev/null 2>&1 || host_os() { printf 'unknown\n'; }

readonly RENDERER_BINS="silicon magick convert"
readonly KNOWN_TOOLS="renderer $RENDERER_BINS playwright playwright-browser adb-device simulator xcodebuildmcp"
# Buffers are removed by --record only when their basename carries one of these
# prefixes, so a mistyped argument can never delete an unrelated file.
readonly BUFFER_PREFIXES="corpflow-preflight. corpflow-issue-scan."

GH_BIN="${GH_BIN:-gh}"
GIT_BIN="${GIT_BIN:-git}"
PROBE_SECS="${AUTONOMY_PREFLIGHT_TIMEOUT:-20}"
TIMEOUT_BIN="${TIMEOUT_BIN:-$(command -v gtimeout || command -v timeout || true)}"

WORK=""
CHECK_ROWS=()
ABSENT_ROWS=()
FAIL_ENTRIES=()
ACCEPTED_USED=()

usage() {
  awk 'NR>1{ if (!/^#/) exit; sub(/^# ?/,""); print }' "$SELF"
}

die_usage() {
  printf >&2 'autonomy-preflight: %s\n' "$1"
  exit 2
}

# shellcheck disable=SC2329 # invoked only through the EXIT/INT/TERM traps set in check_main
cleanup() {
  [ -n "$WORK" ] && rm -rf -- "$WORK" 2> /dev/null
  return 0
}

# Tabs and newlines would forge a field in the TSV rows the JSON is built from.
_flat() {
  local s="$1"
  s="${s//$'\t'/ }"
  s="${s//$'\r'/ }"
  s="${s//$'\n'/ }"
  printf '%s' "${s:0:240}"
}

# <out-file> <cmd...>: the probe's stdout+stderr land in a file, never a $( ) pipe, so a
# grandchild still holding the pipe cannot outlive the timeout. Returns the command's
# status, or 124 on timeout. stdin is closed so no probe can wait on a prompt.
_bounded() {
  local out="$1" p n=0
  shift
  if [ -n "$TIMEOUT_BIN" ]; then
    "$TIMEOUT_BIN" "$PROBE_SECS" "$@" > "$out" 2>&1 < /dev/null
    return $?
  fi
  "$@" > "$out" 2>&1 < /dev/null &
  p=$!
  while kill -0 "$p" 2> /dev/null && [ "$n" -lt "$PROBE_SECS" ]; do
    sleep 1
    n=$((n + 1))
  done
  if kill -0 "$p" 2> /dev/null; then
    kill -9 "$p" 2> /dev/null
    wait "$p" 2> /dev/null
    return 124
  fi
  wait "$p"
}

# <id> <kind> <status> <detail> [fix...]
_add_check() {
  local id="$1" kind="$2" status="$3" detail entry fix
  detail="$(_flat "$4")"
  shift 4
  CHECK_ROWS[${#CHECK_ROWS[@]}]="$id"$'\t'"$kind"$'\t'"$status"$'\t'"$detail"
  [ "$status" = "fail" ] || return 0
  entry="  - [$kind] $id: $detail"
  for fix in "$@"; do
    entry="$entry"$'\n'"      fix: $(_flat "$fix")"
  done
  FAIL_ENTRIES[${#FAIL_ENTRIES[@]}]="$entry"
}

_in_list() { # <needle> <comma list>
  case ",$2," in *",$1,"*) return 0 ;; esac
  return 1
}

# <token list> -> normalised comma list on stdout; returns 1 on a malformed token.
_norm_list() {
  local raw="$1" tok out=""
  raw="${raw//\[/}"
  raw="${raw//\]/}"
  raw="${raw// /}"
  raw="${raw//,/ }"
  for tok in $raw; do
    [ -n "$tok" ] || continue
    case "$tok" in
      [a-z]*) ;;
      *) return 1 ;;
    esac
    case "$tok" in *[!a-z0-9_-]*) return 1 ;; esac
    _in_list "$tok" "$out" || out="${out:+$out,}$tok"
  done
  printf '%s' "$out"
}

# --- settings rules --------------------------------------------------------------

# Glob where only `*` is special; every other byte of the rule is literal.
_star_glob() {
  local pat="$1" txt="$2" seg first=1
  case "$pat" in
    *\**) ;;
    *)
      [ "$pat" = "$txt" ]
      return
      ;;
  esac
  while :; do
    case "$pat" in
      *\**)
        seg="${pat%%\**}"
        pat="${pat#*\*}"
        ;;
      *)
        [ -z "$pat" ] && return 0
        case "$txt" in *"$pat") return 0 ;; esac
        return 1
        ;;
    esac
    if [ "$first" -eq 1 ]; then
      case "$txt" in
        "$seg"*) txt="${txt#"$seg"}" ;;
        *) return 1 ;;
      esac
      first=0
    elif [ -n "$seg" ]; then
      case "$txt" in
        *"$seg"*) txt="${txt#*"$seg"}" ;;
        *) return 1 ;;
      esac
    fi
  done
}

_rule_matches() { # <rule> <invocation>
  local rule="$1" inv="$2" body
  case "$rule" in
    Bash) return 0 ;;
    'Bash('*')')
      body="${rule#Bash(}"
      body="${body%)}"
      ;;
    *) return 1 ;;
  esac
  [ -n "$body" ] || return 1
  case "$body" in
    *:\*)
      body="${body%:\*}"
      [ "$inv" = "$body" ] && return 0
      case "$inv" in "$body "*) return 0 ;; esac
      return 1
      ;;
  esac
  _star_glob "$body" "$inv"
}

# Only the tree under check: a grant in another checkout of the same repo (such as the
# main checkout of a linked worktree) is not loaded for this session, so it must not pass.
_project_dirs() {
  local top
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "${CLAUDE_PROJECT_DIR}" ]; then
    printf '%s\n' "$CLAUDE_PROJECT_DIR"
    return 0
  fi
  top=$("$GIT_BIN" rev-parse --show-toplevel 2> /dev/null) || top=""
  [ -n "$top" ] && printf '%s\n' "$top"
  return 0
}

# Prints "<label>\t<path>" lowest precedence first.
_settings_sources() {
  local i=0 f d IFS
  if [ -n "${AUTONOMY_PREFLIGHT_SETTINGS:-}" ]; then
    IFS=:
    for f in $AUTONOMY_PREFLIGHT_SETTINGS; do
      i=$((i + 1))
      [ -n "$f" ] && printf 'settings source %d\t%s\n' "$i" "$f"
    done
    return 0
  fi
  printf 'user settings\t%s\n' "${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/settings.json"
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    printf 'project settings\t%s\n' "$d/.claude/settings.json"
    printf 'project local settings\t%s\n' "$d/.claude/settings.local.json"
  done <<< "$(_project_dirs)"
  case "$(host_os)" in
    macos) printf 'managed settings\t%s\n' "/Library/Application Support/ClaudeCode/managed-settings.json" ;;
    linux) printf 'managed settings\t%s\n' "/etc/claude-code/managed-settings.json" ;;
  esac
}

SETTINGS_RULES=""
BYPASS=0

_load_settings() {
  local label path out mode="" nobypass=0 m nb
  while IFS=$'\t' read -r label path; do
    [ -n "$path" ] && [ -f "$path" ] && [ -r "$path" ] || continue
    out=$(jq -r --arg l "$label" '
      (.permissions // {}) as $p
      | def flat: gsub("[\t\r\n]"; " ");
        ( ($p.deny  // [] | .[] | strings | "deny\t\($l)\t\(flat)"),
          ($p.ask   // [] | .[] | strings | "ask\t\($l)\t\(flat)"),
          ($p.allow // [] | .[] | strings | "allow\t\($l)\t\(flat)") )
    ' "$path" 2> /dev/null) || continue
    SETTINGS_RULES="$SETTINGS_RULES${out:+$out$'\n'}"
    m=$(jq -r '.permissions.defaultMode // empty | strings' "$path" 2> /dev/null) || m=""
    [ -n "$m" ] && mode="$m"
    nb=$(jq -r '.permissions.disableBypassPermissionsMode // empty | strings' "$path" 2> /dev/null) || nb=""
    [ "$nb" = "disable" ] && nobypass=1
  done <<< "$(_settings_sources)"
  if [ "$mode" = "bypassPermissions" ] && [ "$nobypass" -eq 0 ]; then
    BYPASS=1
  fi
}

# <kind:deny|ask|allow> <invocation> -> prints "<label>\t<rule>" of the first match.
_first_rule() {
  local want="$1" inv="$2" kind label rule
  while IFS=$'\t' read -r kind label rule; do
    [ "$kind" = "$want" ] || continue
    if _rule_matches "$rule" "$inv"; then
      printf '%s\t%s' "$label" "$rule"
      return 0
    fi
  done <<< "$SETTINGS_RULES"
  return 1
}

# <cmd> <invocation> <need_allow 0|1>; appends findings to _RV_DETAIL/_RV_FIXES.
_RV_DETAIL=""
_RV_FIXES=()
_rules_verdict() {
  local cmd="$1" inv="$2" need="$3" hit
  if hit=$(_first_rule deny "$inv"); then
    _RV_DETAIL="${_RV_DETAIL:+$_RV_DETAIL; }deny rule \"${hit#*$'\t'}\" in ${hit%%$'\t'*} blocks \`$cmd\`"
    _RV_FIXES[${#_RV_FIXES[@]}]="remove the deny rule \"${hit#*$'\t'}\" from ${hit%%$'\t'*}"
  fi
  if hit=$(_first_rule ask "$inv"); then
    _RV_DETAIL="${_RV_DETAIL:+$_RV_DETAIL; }ask rule \"${hit#*$'\t'}\" in ${hit%%$'\t'*} would prompt for \`$cmd\`"
    _RV_FIXES[${#_RV_FIXES[@]}]="remove the ask rule \"${hit#*$'\t'}\" from ${hit%%$'\t'*}; an unattended run cannot answer it"
  fi
  [ "$need" -eq 1 ] || return 0
  [ "$BYPASS" -eq 1 ] && return 0
  _first_rule allow "$inv" > /dev/null && return 0
  _RV_DETAIL="${_RV_DETAIL:+$_RV_DETAIL; }no allow rule matches \`$cmd\` and permissions.defaultMode is not bypassPermissions"
  _RV_FIXES[${#_RV_FIXES[@]}]="add \"Bash($cmd:*)\" to permissions.allow in .claude/settings.local.json"
}

_finish_check() { # <id> <kind> <pass-detail>
  if [ -n "$_RV_DETAIL" ] && [ "${#_RV_FIXES[@]}" -gt 0 ]; then
    _add_check "$1" "$2" fail "$_RV_DETAIL" "${_RV_FIXES[@]}"
  elif [ -n "$_RV_DETAIL" ]; then
    _add_check "$1" "$2" fail "$_RV_DETAIL"
  else
    _add_check "$1" "$2" pass "$3"
  fi
  _RV_DETAIL=""
  _RV_FIXES=()
}

# --- permission checks -----------------------------------------------------------

check_git_push() {
  local remote="" up branch ref rc out="$WORK/push.out"
  if ! "$GIT_BIN" rev-parse --show-toplevel > /dev/null 2>&1; then
    _rules_verdict "git push" "git push origin HEAD" 0
    _RV_DETAIL="${_RV_DETAIL:+$_RV_DETAIL; }not inside a git repository"
    _RV_FIXES[${#_RV_FIXES[@]}]="run the preflight from the project checkout"
    _finish_check git-push permission ""
    return 0
  fi
  up=$("$GIT_BIN" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2> /dev/null) || up=""
  [ -n "$up" ] && remote="${up%%/*}"
  if [ -z "$remote" ]; then
    if "$GIT_BIN" remote 2> /dev/null | grep -qx origin; then
      remote=origin
    else
      remote=$("$GIT_BIN" remote 2> /dev/null | head -n 1) || remote=""
    fi
  fi
  _rules_verdict "git push" "git push ${remote:-origin} HEAD" 0
  case "$remote" in
    "" | -* | *[!A-Za-z0-9._-]*)
      _RV_DETAIL="${_RV_DETAIL:+$_RV_DETAIL; }no usable git remote to push to"
      _RV_FIXES[${#_RV_FIXES[@]}]="add the remote: git remote add origin <url>"
      _finish_check git-push permission ""
      return 0
      ;;
  esac
  branch=$("$GIT_BIN" symbolic-ref -q --short HEAD 2> /dev/null) || branch=""
  ref="HEAD:refs/heads/${branch:-corpflow-preflight-probe}"
  GIT_TERMINAL_PROMPT=0 _bounded "$out" "$GIT_BIN" push --dry-run --no-verify --quiet "$remote" "$ref"
  rc=$?
  if [ "$rc" -eq 124 ]; then
    _RV_DETAIL="${_RV_DETAIL:+$_RV_DETAIL; }git push --dry-run to $remote timed out after ${PROBE_SECS}s"
    _RV_FIXES[${#_RV_FIXES[@]}]="check network access and credentials: git push --dry-run $remote HEAD"
  elif [ "$rc" -ne 0 ]; then
    _RV_DETAIL="${_RV_DETAIL:+$_RV_DETAIL; }git push --dry-run to $remote failed (exit $rc)"
    _RV_FIXES[${#_RV_FIXES[@]}]="fix push credentials for $remote, then confirm: git push --dry-run $remote HEAD"
  fi
  _finish_check git-push permission "git push --dry-run to $remote succeeded"
}

check_gh_pr_create() {
  local rc perm out="$WORK/gh.out"
  _rules_verdict "gh pr create" "gh pr create --fill" 0
  if ! command -v "$GH_BIN" > /dev/null 2>&1; then
    _RV_DETAIL="${_RV_DETAIL:+$_RV_DETAIL; }gh is not installed"
    _RV_FIXES[${#_RV_FIXES[@]}]="install the GitHub CLI (https://cli.github.com) and run gh auth login"
    _finish_check gh-pr-create permission ""
    return 0
  fi
  _bounded "$out" "$GH_BIN" auth status
  rc=$?
  if [ "$rc" -ne 0 ]; then
    _RV_DETAIL="${_RV_DETAIL:+$_RV_DETAIL; }gh auth status failed (exit $rc)"
    _RV_FIXES[${#_RV_FIXES[@]}]="authenticate the GitHub CLI: gh auth login"
    _finish_check gh-pr-create permission ""
    return 0
  fi
  _bounded "$out" "$GH_BIN" repo view --json viewerPermission
  rc=$?
  perm=""
  [ "$rc" -eq 0 ] && perm=$(jq -r '.viewerPermission // empty | strings' "$out" 2> /dev/null | head -n 1)
  case "$perm" in *[!A-Z_]*) perm="UNREADABLE" ;; esac
  case "$perm" in
    WRITE | MAINTAIN | ADMIN) ;;
    "")
      _RV_DETAIL="${_RV_DETAIL:+$_RV_DETAIL; }gh repo view could not read the repository permission (exit $rc)"
      _RV_FIXES[${#_RV_FIXES[@]}]="confirm the repository is reachable: gh repo view --json viewerPermission"
      ;;
    *)
      _RV_DETAIL="${_RV_DETAIL:+$_RV_DETAIL; }repository permission is $perm; opening a PR needs WRITE, MAINTAIN or ADMIN"
      _RV_FIXES[${#_RV_FIXES[@]}]="get WRITE (or higher) access to the repository for the authenticated gh account"
      ;;
  esac
  _finish_check gh-pr-create permission "gh authenticated with ${perm:-unknown} permission"
}

check_rule_only() { # <id> <cmd> <invocation>
  _rules_verdict "$2" "$3" 1
  _finish_check "$1" permission "allow rule or bypassPermissions covers \`$2\`"
}

# --- evidence tools ---------------------------------------------------------------

# <tool> <platform-list> <present 0|1> <detail> <install-fix>
_evidence() {
  local tool="$1" plats="$2" present="$3" detail="$4" fix="$5" p acc=false IFS=,
  if [ "$present" -eq 1 ]; then
    _add_check "$tool" evidence pass "$detail"
    return 0
  fi
  if _in_list "$tool" "$ACCEPT"; then
    acc=true
    ACCEPTED_USED[${#ACCEPTED_USED[@]}]="$tool"
    _add_check "$tool" evidence skip "$detail; accepted absent at launch"
  else
    _add_check "$tool" evidence fail "$detail" "$fix" "or relaunch with --accept-absent $tool to proceed without it"
  fi
  for p in $plats; do
    ABSENT_ROWS[${#ABSENT_ROWS[@]}]="$tool"$'\t'"$p"$'\t'"$acc"
  done
}

# The capture floor row names every binary it tried and the evidence gate matches each name,
# so absence and acceptance are recorded per binary; `renderer` accepts all of them at once.
check_renderer() { # <platform-list>
  local t p acc unaccepted="" detail="no silicon, magick or convert on PATH" IFS=$' \t\n'
  for t in $RENDERER_BINS; do
    if command -v "$t" > /dev/null 2>&1; then
      _add_check renderer evidence pass "$t found on PATH"
      return 0
    fi
  done
  for t in $RENDERER_BINS; do
    acc=false
    if _in_list renderer "$ACCEPT" || _in_list "$t" "$ACCEPT"; then
      acc=true
      ACCEPTED_USED[${#ACCEPTED_USED[@]}]="$t"
    else
      unaccepted="${unaccepted:+$unaccepted,}$t"
    fi
    for p in ${1//,/ }; do
      ABSENT_ROWS[${#ABSENT_ROWS[@]}]="$t"$'\t'"$p"$'\t'"$acc"
    done
  done
  if [ -z "$unaccepted" ]; then
    _add_check renderer evidence skip "$detail; accepted absent at launch"
    return 0
  fi
  [ "$unaccepted" = "${RENDERER_BINS// /,}" ] || detail="$detail; not accepted: $unaccepted"
  _add_check renderer evidence fail "$detail" \
    "install silicon (cargo install silicon) or ImageMagick (brew install imagemagick)" \
    "or relaunch with --accept-absent renderer to proceed without it"
}

_browser_dirs() {
  local d
  if [ -n "${PLAYWRIGHT_BROWSERS_PATH:-}" ] && [ "${PLAYWRIGHT_BROWSERS_PATH}" != "0" ]; then
    printf '%s\n' "$PLAYWRIGHT_BROWSERS_PATH"
    return 0
  fi
  if [ "${PLAYWRIGHT_BROWSERS_PATH:-}" = "0" ]; then
    while IFS= read -r d; do
      [ -n "$d" ] && printf '%s\n' "$d/node_modules/playwright-core/.local-browsers"
    done <<< "$(_project_dirs)"
    return 0
  fi
  case "$(host_os)" in
    macos) printf '%s\n' "${HOME:-}/Library/Caches/ms-playwright" ;;
    *) printf '%s\n' "${XDG_CACHE_HOME:-${HOME:-}/.cache}/ms-playwright" ;;
  esac
}

check_playwright() {
  local present=0 how="" d b found=0
  if command -v playwright > /dev/null 2>&1; then
    present=1
    how="playwright on PATH"
  elif command -v npx > /dev/null 2>&1 && _bounded "$WORK/npx.out" npx --no-install playwright --version; then
    present=1
    how="npx --no-install playwright"
  fi
  if [ "$present" -eq 0 ]; then
    _evidence playwright web 0 "Playwright not found (PATH or npx --no-install)" \
      "install Playwright in the project: npm i -D playwright"
    # A browser cannot be verified without the runner that would drive it.
    _add_check playwright-browser evidence skip "not checked; Playwright is absent"
    return 0
  fi
  _evidence playwright web 1 "$how" ""
  while IFS= read -r d; do
    [ -n "$d" ] && [ -d "$d" ] || continue
    for b in "$d"/chromium* "$d"/firefox* "$d"/webkit*; do
      [ -d "$b" ] && found=1 && break 2
    done
  done <<< "$(_browser_dirs)"
  if [ "$found" -eq 1 ]; then
    _evidence playwright-browser web 1 "a Playwright browser is installed" ""
  else
    _evidence playwright-browser web 0 "no Playwright browser installed" \
      "install a browser: npx playwright install chromium"
  fi
}

check_adb() {
  local n
  if ! command -v adb > /dev/null 2>&1; then
    _evidence adb-device android 0 "adb not found on PATH" \
      "install Android platform-tools and put adb on PATH"
    return 0
  fi
  if ! _bounded "$WORK/adb.out" adb devices; then
    _evidence adb-device android 0 "adb devices failed or timed out" \
      "restart the adb server (adb kill-server) and attach a device or emulator"
    return 0
  fi
  n=$(awk -F'\t' 'NR > 1 && $2 == "device" { c++ } END { print c + 0 }' "$WORK/adb.out")
  if [ "$n" -gt 0 ]; then
    _evidence adb-device android 1 "$n device(s) attached" ""
  else
    _evidence adb-device android 0 "adb devices lists no device in state device" \
      "start an emulator or connect a device so adb devices lists one"
  fi
}

check_simulator() {
  if ! command -v xcrun > /dev/null 2>&1; then
    _evidence simulator apple 0 "xcrun not found" "install Xcode and select it with xcode-select -s"
    return 0
  fi
  if _bounded "$WORK/simctl.out" xcrun simctl list devices available \
    && grep -Eq '\((Shutdown|Booted)\)' "$WORK/simctl.out"; then
    _evidence simulator apple 1 "a bootable simulator is available" ""
  else
    _evidence simulator apple 0 "xcrun simctl lists no bootable simulator" \
      "install a simulator runtime in Xcode > Settings > Components"
  fi
}

check_xcodebuildmcp() {
  local declared=0 plugin=0 f d cfgs pfile detail IFS
  if [ -n "${AUTONOMY_PREFLIGHT_MCP_CONFIGS:-}" ]; then
    cfgs="$AUTONOMY_PREFLIGHT_MCP_CONFIGS"
  else
    cfgs="${CLAUDE_CONFIG_DIR:-${HOME:-}}/.claude.json"
    while IFS= read -r d; do
      [ -n "$d" ] && cfgs="$cfgs:$d/.mcp.json"
    done <<< "$(_project_dirs)"
  fi
  local dirs_json
  dirs_json=$(_project_dirs | jq -R . | jq -cs . 2> /dev/null) || dirs_json='[]'
  IFS=:
  for f in $cfgs; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    if jq -e --argjson dirs "$dirs_json" '
        [ (.mcpServers // {} | keys[]),
          ((.projects // {}) as $p | $dirs[] | ($p[.].mcpServers // {}) | keys[]) ]
        | any(test("^xcodebuildmcp$"; "i"))' "$f" > /dev/null 2>&1; then
      declared=1
      break
    fi
  done
  unset IFS
  pfile="${AUTONOMY_PREFLIGHT_PLUGINS_FILE:-${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/plugins/installed_plugins.json}"
  if [ -f "$pfile" ] && jq -e '(.plugins // {}) | keys | any(startswith("apple-developer@"))' "$pfile" > /dev/null 2>&1; then
    plugin=1
  fi
  if [ "$declared" -eq 1 ] && [ "$plugin" -eq 1 ]; then
    _evidence xcodebuildmcp apple 1 "XcodeBuildMCP declared and apple-developer installed" ""
    return 0
  fi
  detail=""
  [ "$declared" -eq 1 ] || detail="no XcodeBuildMCP server in the user or project MCP config"
  [ "$plugin" -eq 1 ] || detail="${detail:+$detail; }apple-developer plugin not installed"
  _evidence xcodebuildmcp apple 0 "$detail" \
    "declare the XcodeBuildMCP server (claude mcp add XcodeBuildMCP -- npx -y xcodebuildmcp@latest) and install the apple-developer plugin"
}

# --- toolchain integrity ----------------------------------------------------------

check_apple_toolchain() {
  local dev plist n=0 bad="" a b
  dev="${DEVELOPER_DIR:-}"
  if [ -z "$dev" ] && command -v xcode-select > /dev/null 2>&1; then
    _bounded "$WORK/xs.out" xcode-select -p && dev=$(head -n 1 "$WORK/xs.out")
  fi
  if [ -z "$dev" ] || [ ! -d "$dev" ]; then
    _add_check apple-developer-dir toolchain fail "no active Xcode developer directory" \
      "install Xcode and select it: sudo xcode-select -s /Applications/Xcode.app"
    return 0
  fi
  _add_check apple-developer-dir toolchain pass "active developer directory found"

  if ! command -v plutil > /dev/null 2>&1; then
    _add_check apple-sdk-settings toolchain fail "plutil not found; SDKSettings.plist cannot be linted" \
      "run on macOS with Xcode command line tools installed"
  else
    for plist in "$dev"/Platforms/*.platform/Developer/SDKs/*.sdk/SDKSettings.plist; do
      [ -f "$plist" ] || continue
      n=$((n + 1))
      if ! _bounded "$WORK/plutil.out" plutil -lint "$plist"; then
        a="${plist%/SDKSettings.plist}"
        bad="${bad:+$bad, }${a##*/}"
      fi
    done
    if [ "$n" -eq 0 ]; then
      _add_check apple-sdk-settings toolchain fail "no SDKSettings.plist under the developer directory's platform SDKs" \
        "reinstall the platform SDKs (Xcode > Settings > Components) or reinstall Xcode"
    elif [ -n "$bad" ]; then
      _add_check apple-sdk-settings toolchain fail "plutil -lint rejects SDKSettings.plist in $bad" \
        "reinstall the affected SDK (Xcode > Settings > Components) or reinstall Xcode"
    else
      _add_check apple-sdk-settings toolchain pass "$n SDKSettings.plist file(s) lint clean"
    fi
  fi

  if command -v xcodebuild > /dev/null 2>&1 && _bounded "$WORK/sdks.out" xcodebuild -showsdks; then
    _add_check apple-showsdks toolchain pass "xcodebuild -showsdks succeeded"
  else
    _add_check apple-showsdks toolchain fail "xcodebuild -showsdks failed or is unavailable" \
      "run sudo xcodebuild -runFirstLaunch, then confirm with xcodebuild -showsdks"
  fi

  a=""
  b=""
  command -v swift > /dev/null 2>&1 && _bounded "$WORK/sw1.out" swift --version && a=$(head -n 1 "$WORK/sw1.out")
  command -v xcrun > /dev/null 2>&1 && _bounded "$WORK/sw2.out" xcrun swift --version && b=$(head -n 1 "$WORK/sw2.out")
  if [ -n "$a" ] && [ "$a" = "$b" ]; then
    _add_check apple-swift-match toolchain pass "swift on PATH matches xcrun swift"
  else
    _add_check apple-swift-match toolchain fail "swift on PATH (${a:-unavailable}) differs from xcrun swift (${b:-unavailable})" \
      "put the selected Xcode toolchain's swift first on PATH, or xcode-select the Xcode that matches it"
  fi
}

check_android_toolchain() {
  local proj sdk levels n missing="" IFS
  proj=$(_project_dirs | head -n 1)
  [ -n "$proj" ] || proj="$PWD"
  levels=$(find "$proj" -maxdepth 4 \( -name node_modules -o -name build -o -name .git -o -name .gradle \) -prune \
    -o -type f \( -name 'build.gradle' -o -name 'build.gradle.kts' \) -print 2> /dev/null \
    | while IFS= read -r f; do
      grep -hoE 'compileSdk(Version)?[[:space:]]*(=|\()?[[:space:]]*["'\'']?(android-)?[0-9]+' "$f" 2> /dev/null
    done | grep -oE '[0-9]+$' | sort -un | tr '\n' ' ')
  if [ -z "${levels// /}" ]; then
    _add_check android-compile-sdk toolchain skip "compileSdk not found in the Gradle files; recorded as unknown"
    return 0
  fi
  sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  if [ -z "$sdk" ]; then
    case "$(host_os)" in
      macos) sdk="${HOME:-}/Library/Android/sdk" ;;
      *) sdk="${HOME:-}/Android/Sdk" ;;
    esac
  fi
  if [ ! -d "$sdk/platforms" ]; then
    _add_check android-compile-sdk toolchain fail "Android SDK platforms directory not found (compileSdk ${levels% })" \
      "install the Android SDK and set ANDROID_HOME"
    return 0
  fi
  IFS=' '
  for n in $levels; do
    [ -d "$sdk/platforms/android-$n" ] || missing="${missing:+$missing, }$n"
  done
  unset IFS
  if [ -n "$missing" ]; then
    _add_check android-compile-sdk toolchain fail "compileSdk $missing not installed under the Android SDK" \
      "install it: sdkmanager \"platforms;android-${missing%%,*}\""
  else
    _add_check android-compile-sdk toolchain pass "compileSdk ${levels% } installed"
  fi
}

# --- output -----------------------------------------------------------------------

_rows_json() { # <kind: checks|absent>
  local r
  if [ "$1" = "checks" ]; then
    for r in ${CHECK_ROWS[@]+"${CHECK_ROWS[@]}"}; do printf '%s\n' "$r"; done \
      | jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t")
          | {id: .[0], kind: .[1], status: .[2], detail: (.[3] // "")})'
  else
    for r in ${ABSENT_ROWS[@]+"${ABSENT_ROWS[@]}"}; do printf '%s\n' "$r"; done \
      | jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t")
          | {tool: .[0], platform: .[1], accepted: (.[2] == "true")})'
  fi
}

emit_and_exit() {
  local result=pass json checks absent plats ran e used=""
  [ "${#FAIL_ENTRIES[@]}" -eq 0 ] || result=fail
  checks=$(_rows_json checks) || checks='[]'
  absent=$(_rows_json absent) || absent='[]'
  plats=$(printf '%s' "$PLATFORMS" | tr ',' '\n' | jq -R -s -c 'split("\n") | map(select(length > 0))') || plats='[]'
  ran=$(date -u +%FT%TZ 2> /dev/null) || ran="unknown"
  json=$(jq -cn --arg r "$result" --arg ran "$ran" --argjson p "$plats" \
    --argjson c "$checks" --argjson a "$absent" \
    '{version: 1, result: $r, ran_at: $ran, platforms: $p, checks: $c, tools_absent: $a}')
  if [ "$result" = "fail" ]; then
    printf 'preflight_failures=%d\n' "${#FAIL_ENTRIES[@]}"
    for e in "${FAIL_ENTRIES[@]}"; do printf '%s\n' "$e"; done
    printf 'result_json=%s\n' "$json"
    exit 1
  fi
  for e in ${ACCEPTED_USED[@]+"${ACCEPTED_USED[@]}"}; do
    _in_list "$e" "$used" || used="${used:+$used,}$e"
  done
  [ -n "$used" ] && printf 'accepted_absent=%s\n' "$used"
  printf 'result_json=%s\n' "$json"
  exit 0
}

# --- modes ------------------------------------------------------------------------

AUTO=""
AUTO_SEEN=0
PLATFORMS=""
HARNESS=0
ACCEPT=""
RECORD_BUF=""
CONTEXT_DIR=""
CANDIDATES_BUF=""

check_main() {
  local p evidence_plats="" IFS
  case "$PROBE_SECS" in '' | *[!0-9]* | 0) die_usage "AUTONOMY_PREFLIGHT_TIMEOUT must be a positive integer" ;; esac

  if ! _in_list plan "$AUTO" && ! _in_list finalization "$AUTO"; then
    printf 'result=skipped\nreason=not_unattended\n'
    exit 0
  fi
  # Megatask per-issue runs arrive pre-seeded; the host already owns their launch.
  if [ "${MILESTONE_MODE:-0}" = "1" ] || { [ -n "${WORKSPACE_ROOT:-}" ] \
    && [ -f "${WORKSPACE_ROOT}/workspace.json" ] && [ -f "${WORKSPACE_ROOT}/.context/state.json" ]; }; then
    printf 'result=skipped\nreason=milestone_mode\n'
    exit 0
  fi

  if ! command -v jq > /dev/null 2>&1; then
    printf 'preflight_failures=1\n  - [toolchain] jq: jq is not installed\n      fix: install jq\n'
    printf 'result_json={"version":1,"result":"fail","ran_at":"unknown","platforms":[],"checks":[{"id":"jq","kind":"toolchain","status":"fail","detail":"jq is not installed"}],"tools_absent":[]}\n'
    exit 1
  fi

  WORK=$(mktemp -d "${TMPDIR:-/tmp}/corpflow-autonomy-preflight.XXXXXX") || {
    printf >&2 'autonomy-preflight: mktemp -d failed\n'
    exit 1
  }
  trap cleanup EXIT
  trap 'cleanup; exit 130' INT TERM

  _load_settings
  check_git_push
  check_gh_pr_create
  check_rule_only gh-pr-merge "gh pr merge" "gh pr merge 1 --squash"
  [ "$HARNESS" -eq 1 ] && check_rule_only git-reset-hard "git reset --hard" "git reset --hard HEAD"

  # Tokens are [a-z0-9_-] by validation, so splitting on spaces cannot glob.
  for p in ${PLATFORMS//,/ }; do
    case "$p" in
      backend | systems | ai | all) evidence_plats="${evidence_plats:+$evidence_plats,}$p" ;;
    esac
  done
  [ -n "$evidence_plats" ] && check_renderer "$evidence_plats"

  for p in ${PLATFORMS//,/ }; do
    case "$p" in
      backend | systems | ai | all) ;;
      web) check_playwright ;;
      android)
        check_adb
        check_android_toolchain
        ;;
      apple)
        check_simulator
        check_xcodebuildmcp
        check_apple_toolchain
        ;;
      *) _add_check "platform-$p" evidence skip "no evidence or toolchain chain is defined for platform $p" ;;
    esac
  done
  emit_and_exit
}

_owned_buffer_rm() {
  local f="$1" base pre
  [ -f "$f" ] && [ ! -L "$f" ] || return 0
  base="${f##*/}"
  for pre in $BUFFER_PREFIXES; do
    case "$base" in "$pre"*) rm -f -- "$f" 2> /dev/null && return 0 ;; esac
  done
  return 0
}

# <json array of {number,title,url,score}> -> same array with title/url scrubbed, or
# returns 1. Values go through the scrub one line each and are counted back, so a scrub
# that drops or merges a line can never shift a title onto the wrong issue.
_scrub_candidates() {
  local arr="$1" scrub fields n out
  n=$(printf '%s' "$arr" | jq 'length' 2> /dev/null) || return 1
  [ "$n" -gt 0 ] || {
    printf '[]'
    return 0
  }
  scrub="$SCRIPT_DIR/../../shared/scripts/path-scrub.sh"
  [ -r "$scrub" ] || return 1
  # shellcheck source=skills/shared/scripts/path-scrub.sh
  . "$scrub" > /dev/null 2>&1 || return 1
  command -v corpflow_path_scrub > /dev/null 2>&1 || return 1
  [ -n "${CORPFLOW_HOST_PATH_ERE:-}" ] || return 1
  fields=$(printf '%s' "$arr" | jq -r '.[] | (.title, .url) | tostring | gsub("[\r\n\t]"; " ")') || return 1
  out=$(printf '%s\nEND-OF-FIELDS\n' "$fields" | corpflow_path_scrub) || return 1
  printf '%s' "$arr" | jq -c --arg s "$out" '
    ($s | split("\n")) as $l
    | if ($l | length) < (length * 2 + 1) or $l[length * 2] != "END-OF-FIELDS" then error("scrub line count")
      else [ range(0; length) as $i | .[$i] + {title: $l[2 * $i], url: $l[2 * $i + 1]} ] end' 2> /dev/null
}

record_main() {
  local json state patch lib cand_result="" cand_json='[]' scrubbed meta
  [ -n "$CONTEXT_DIR" ] || die_usage "--record requires --context <dir>"
  command -v jq > /dev/null 2>&1 || {
    printf >&2 'autonomy-preflight: --record needs jq; nothing written\n'
    exit 1
  }
  if [ ! -f "$RECORD_BUF" ] || [ -L "$RECORD_BUF" ]; then
    printf >&2 'autonomy-preflight: buffer is not a regular file; nothing written\n'
    exit 1
  fi
  json=$(grep '^result_json=' "$RECORD_BUF" | tail -n 1)
  json="${json#result_json=}"
  # Only a pass is ever recorded, so every recorded tools_absent entry is accepted by
  # construction; anything else on a ledger would be a contract violation.
  if ! printf '%s' "$json" | jq -e '
      type == "object" and .version == 1 and .result == "pass"
      and (.ran_at | type) == "string" and (.platforms | type) == "array"
      and (.checks | type) == "array" and (.tools_absent | type) == "array"
      and all(.checks[]; (.id | type) == "string" and (.detail | type) == "string"
        and ([.kind == ("permission", "evidence", "toolchain")] | any)
        and ([.status == ("pass", "fail", "skip")] | any))
      and all(.tools_absent[]; (.tool | type) == "string" and (.platform | type) == "string"
        and .accepted == true)' > /dev/null 2>&1; then
    printf >&2 'autonomy-preflight: buffer holds no passing v1 result_json; nothing written\n'
    exit 1
  fi
  state="$CONTEXT_DIR/state.json"
  if [ ! -f "$state" ] || [ -L "$state" ]; then
    printf >&2 'autonomy-preflight: no state.json in the context directory; nothing written\n'
    exit 1
  fi
  patch="$SCRIPT_DIR/state-patch.sh"
  lib="$SCRIPT_DIR/../../shared/lib/audit-lib.sh"
  if [ ! -r "$patch" ] || [ ! -r "$lib" ]; then
    printf >&2 'autonomy-preflight: state-patch.sh or audit-lib.sh unreachable; nothing written\n'
    exit 1
  fi

  if [ -n "$CANDIDATES_BUF" ]; then
    if [ -f "$CANDIDATES_BUF" ] && [ ! -L "$CANDIDATES_BUF" ]; then
      cand_result=$(sed -n 's/^result=//p' "$CANDIDATES_BUF" | head -n 1)
      case "$cand_result" in shown | prior-run | none | skipped) ;; *) cand_result="unreadable" ;; esac
      cand_json=$(sed -n 's/^candidate=//p' "$CANDIDATES_BUF" | jq -c -s '
        map(select(type == "object")
          | {number: (.number | tonumber? // null), title: ((.title // "") | tostring),
             url: ((.url // "") | tostring), score: (.score | tonumber? // 0)}
          | select(.number != null))' 2> /dev/null) || cand_json='[]'
      if scrubbed=$(_scrub_candidates "$cand_json"); then
        cand_json="$scrubbed"
      else
        cand_result="scrub_unavailable"
        cand_json='[]'
      fi
    else
      cand_result="unreadable"
    fi
  fi

  mkdir -p "$CONTEXT_DIR/logs" 2> /dev/null
  if ! bash "$patch" --state "$state" --log "$CONTEXT_DIR/logs/state-merge.log" \
    --ledger-meta --set "$(jq -cn --argjson p "$json" '{preflight: $p}')" > /dev/null; then
    printf >&2 'autonomy-preflight: state-patch.sh --ledger-meta failed; no audit row written\n'
    exit 1
  fi
  printf 'recorded=metadata.preflight\n'

  # shellcheck source=skills/shared/lib/audit-lib.sh
  . "$lib"
  # The rows name the ledger's one in-progress task: "none" before any stage runs, "unknown" when
  # several run or the ledger cannot be read.
  ptask=$(jq -r '[(.tasks // {}) | to_entries[] | select(.value.status == "in_progress") | .key
    | select(test("^[A-Z]{2}[0-9]+$"))]
    | if length == 0 then "none" elif length == 1 then .[0] else "unknown" end' "$state" 2> /dev/null) \
    || ptask="unknown"
  [ -n "$ptask" ] || ptask="unknown"
  meta=$(printf '%s' "$json" | jq -c '{result, platforms, tools_absent}')
  corpflow_audit_row --file "$CONTEXT_DIR/logs/audit.jsonl" --actor orchestrator \
    --action autonomy_preflight --subject preflight --result ok --task-id "$ptask" --meta "$meta"
  if [ "${CORPFLOW_AUDIT_LAST_RC:-1}" -ne 0 ]; then
    printf >&2 'autonomy-preflight: autonomy_preflight audit row not written\n'
    exit 1
  fi
  printf 'recorded=autonomy_preflight\n'

  if [ -n "$CANDIDATES_BUF" ]; then
    meta=$(jq -cn --arg r "$cand_result" --argjson c "$cand_json" '{result: $r, candidates: $c}')
    corpflow_audit_row --file "$CONTEXT_DIR/logs/audit.jsonl" --actor orchestrator \
      --action preflight_issue_candidates --subject preflight --result ok --task-id "$ptask" --meta "$meta"
    if [ "${CORPFLOW_AUDIT_LAST_RC:-1}" -ne 0 ]; then
      printf >&2 'autonomy-preflight: preflight_issue_candidates audit row not written\n'
      exit 1
    fi
    printf 'recorded=preflight_issue_candidates\n'
    _owned_buffer_rm "$CANDIDATES_BUF"
  fi
  _owned_buffer_rm "$RECORD_BUF"
  exit 0
}

# --- self-test --------------------------------------------------------------------

self_test() {
  local t pass=0 fail=0 out rc stub bin r
  t=$(mktemp -d "${TMPDIR:-/tmp}/corpflow-autonomy-preflight-st.XXXXXX") || return 1
  # shellcheck disable=SC2064 # expand now: $t is local and gone by the time EXIT fires
  trap "rm -rf -- '$t'" EXIT

  ok() {
    printf 'ok: %s\n' "$1"
    pass=$((pass + 1))
  }
  bad() {
    printf 'FAIL: %s\n' "$1"
    fail=$((fail + 1))
  }

  for r in 'Bash(gh pr merge:*)' 'Bash(gh pr merge *)' 'Bash(gh pr:*)' 'Bash(gh:*)' \
    'Bash(gh *)' 'Bash' 'Bash(*)' 'Bash(gh pr m*)'; do
    if _rule_matches "$r" "gh pr merge 1 --squash"; then ok "rule $r matches"; else bad "rule $r should match"; fi
  done
  for r in 'Bash(gh pr merge)' 'Bash(gh pr list:*)' 'Bash(ghx:*)' 'Read' 'Bash(gh pr *merge-queue)'; do
    if _rule_matches "$r" "gh pr merge 1 --squash"; then bad "rule $r should not match"; else ok "rule $r does not match"; fi
  done

  stub="$t/bin"
  mkdir -p "$stub" "$t/proj" "$t/cfg"
  bin="$(command -v jq)"
  ln -s "$bin" "$stub/jq"
  cat > "$stub/gh" << 'EOS'
#!/bin/sh
case "$1" in
  auth) exit 0 ;;
  repo) printf '{"viewerPermission":"%s"}\n' "${ST_PERM:-WRITE}" ;;
esac
exit 0
EOS
  cat > "$stub/git" << 'EOS'
#!/bin/sh
case "$1 $2" in
  "rev-parse --show-toplevel") pwd ;;
  "rev-parse --abbrev-ref") echo origin/main ;;
  "symbolic-ref -q") echo main ;;
  "push --dry-run") exit 0 ;;
  *) exit 0 ;;
esac
EOS
  printf '#!/bin/sh\nexit 0\n' > "$stub/silicon"
  printf '#!/bin/sh\nexit 1\n' > "$stub/npx"
  chmod +x "$stub/gh" "$stub/git" "$stub/silicon" "$stub/npx"
  printf '{"permissions":{"allow":["Bash(gh pr merge:*)"]}}' > "$t/cfg/allow.json"
  printf '{"permissions":{"allow":["Bash(gh pr list:*)"]}}' > "$t/cfg/none.json"

  _st_run() { # <settings> <perm> <args...>
    local s="$1" perm="$2"
    shift 2
    (cd "$t/proj" && env -u WORKSPACE_ROOT -u MILESTONE_MODE PATH="$stub:/usr/bin:/bin" \
      GH_BIN="$stub/gh" GIT_BIN="$stub/git" ST_PERM="$perm" CLAUDE_PROJECT_DIR="$t/proj" \
      AUTONOMY_PREFLIGHT_SETTINGS="$s" AUTONOMY_PREFLIGHT_TIMEOUT=5 TMPDIR="$t" \
      bash "$SELF" "$@")
  }

  out=$(_st_run "$t/cfg/allow.json" WRITE --auto plan --platform backend --accept-absent bogus 2> /dev/null)
  rc=$?
  if [ "$rc" -eq 2 ] && [ -z "$out" ]; then ok "unknown --accept-absent token exits 2 silently"; else bad "bogus token rc=$rc"; fi

  out=$(_st_run "$t/cfg/allow.json" WRITE --auto plan --platform backend 2> /dev/null)
  rc=$?
  if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q '^result_json={"version":1,"result":"pass"'; then
    ok "all grants and renderer present passes"
  else bad "pass run rc=$rc"; fi

  out=$(_st_run "$t/cfg/none.json" READ --auto plan --platform backend 2> /dev/null)
  rc=$?
  if [ "$rc" -eq 1 ] && [ "$(printf '%s\n' "$out" | grep -c '^preflight_failures=2$')" -eq 1 ] \
    && printf '%s\n' "$out" | grep -q 'gh-pr-merge' && printf '%s\n' "$out" | grep -q 'gh-pr-create' \
    && [ ! -e "$t/proj/.context" ]; then
    ok "READ permission and missing merge rule fail in one block, no .context"
  else bad "fail run rc=$rc"; fi

  out=$(_st_run "$t/cfg/allow.json" WRITE --auto finalization --platform web --accept-absent playwright 2> /dev/null)
  rc=$?
  if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -qx 'accepted_absent=playwright'; then
    ok "accepted absent Playwright passes"
  else bad "accepted run rc=$rc"; fi
  printf '%s\n' "$out" > "$t/corpflow-preflight.buf"

  mkdir -p "$t/ctx"
  printf '{"version":2,"tasks":{},"metadata":{}}' > "$t/ctx/state.json"
  if (cd "$t/proj" && TMPDIR="$t" bash "$SELF" --record "$t/corpflow-preflight.buf" --context "$t/ctx" > /dev/null 2>&1) \
    && jq -e '.metadata.preflight.tools_absent == [{"tool":"playwright","platform":"web","accepted":true}]' "$t/ctx/state.json" > /dev/null \
    && grep -q '"action":"autonomy_preflight"' "$t/ctx/logs/audit.jsonl" && [ ! -e "$t/corpflow-preflight.buf" ]; then
    ok "--record merges metadata.preflight, appends the row, removes the buffer"
  else bad "--record pass"; fi

  out=$(_st_run "$t/cfg/none.json" WRITE --auto plan --platform web 2> /dev/null)
  printf '%s\n' "$out" > "$t/fail.buf"
  cp "$t/ctx/state.json" "$t/before.json"
  # Without a fail record in the buffer, a refusal proves nothing about the fail path.
  if grep -q '^result_json={"version":1,"result":"fail"' "$t/fail.buf" \
    && ! (TMPDIR="$t" bash "$SELF" --record "$t/fail.buf" --context "$t/ctx" > /dev/null 2>&1) \
    && cmp -s "$t/ctx/state.json" "$t/before.json"; then
    ok "--record refuses a failing result and leaves the ledger untouched"
  else bad "--record fail refusal"; fi

  # The evidence gate matches the binary names a tool_missing row lists, so each is recorded.
  rm -f "$stub/silicon"
  if PATH="/usr/bin:/bin" command -v silicon > /dev/null 2>&1 || PATH="/usr/bin:/bin" command -v magick > /dev/null 2>&1 \
    || PATH="/usr/bin:/bin" command -v convert > /dev/null 2>&1; then
    ok "renderer binaries per entry (skipped: host renderer on /usr/bin:/bin)"
  else
    out=$(_st_run "$t/cfg/allow.json" WRITE --auto plan --platform systems 2> /dev/null)
    rc=$?
    if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q '\] renderer: '; then
      ok "absent renderer without --accept-absent fails"
    else bad "renderer unaccepted rc=$rc"; fi
    out=$(_st_run "$t/cfg/allow.json" WRITE --auto plan --platform systems --accept-absent renderer 2> /dev/null)
    rc=$?
    if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | sed -n 's/^result_json=//p' | jq -e '.tools_absent == [
        {"tool":"silicon","platform":"systems","accepted":true},
        {"tool":"magick","platform":"systems","accepted":true},
        {"tool":"convert","platform":"systems","accepted":true}]' > /dev/null; then
      ok "--accept-absent renderer records silicon, magick and convert"
    else bad "renderer accepted rc=$rc"; fi
  fi

  printf 'autonomy-preflight --self-test: %d passed, %d failed\n' "$pass" "$fail"
  [ "$fail" -eq 0 ]
}

# --- argv -------------------------------------------------------------------------

_need_val() {
  [ "$#" -ge 2 ] || die_usage "$1 requires a value"
}

MODE=check
while [ "$#" -gt 0 ]; do
  case "$1" in
    --auto=* | --platform=* | --accept-absent=* | --record=* | --context=* | --candidates=*)
      _flag="${1%%=*}"
      _val="${1#*=}"
      shift
      set -- "$_flag" "$_val" "$@"
      continue
      ;;
  esac
  case "$1" in
    --auto)
      _need_val "$@"
      AUTO="$2"
      AUTO_SEEN=1
      shift 2
      ;;
    --platform)
      _need_val "$@"
      PLATFORMS="$2"
      shift 2
      ;;
    --accept-absent)
      _need_val "$@"
      ACCEPT="$2"
      shift 2
      ;;
    --harness)
      HARNESS=1
      shift
      ;;
    --record)
      _need_val "$@"
      RECORD_BUF="$2"
      MODE=record
      shift 2
      ;;
    --context)
      _need_val "$@"
      CONTEXT_DIR="$2"
      shift 2
      ;;
    --candidates)
      _need_val "$@"
      CANDIDATES_BUF="$2"
      shift 2
      ;;
    --self-test)
      self_test
      exit $?
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) die_usage "unknown argument: $1" ;;
  esac
done

if [ "$MODE" = "record" ]; then
  if [ "$AUTO_SEEN" -eq 1 ] || [ -n "$PLATFORMS" ] || [ -n "$ACCEPT" ] || [ "$HARNESS" -eq 1 ]; then
    die_usage "--record takes only --context and --candidates; the result_json already carries the check"
  fi
  record_main
fi

[ -z "$CONTEXT_DIR" ] && [ -z "$CANDIDATES_BUF" ] || die_usage "--context and --candidates belong to --record"
[ "$AUTO_SEEN" -eq 1 ] || die_usage "--auto <list> is required"
[ -n "$PLATFORMS" ] || die_usage "--platform <p[,p]> is required"
AUTO=$(_norm_list "$AUTO") || die_usage "--auto: malformed token"
PLATFORMS=$(_norm_list "$PLATFORMS") || die_usage "--platform: malformed token"
[ -n "$PLATFORMS" ] || die_usage "--platform <p[,p]> is required"
ACCEPT=$(_norm_list "$ACCEPT") || die_usage "--accept-absent: malformed token"
for _tok in ${ACCEPT//,/ }; do
  case " $KNOWN_TOOLS " in
    *" $_tok "*) ;;
    *) die_usage "--accept-absent: unknown tool '$_tok' (known: $KNOWN_TOOLS)" ;;
  esac
done
check_main
