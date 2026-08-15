#!/usr/bin/env bash
# @description First-pass secrets scanner for the SR stage.
#              Prefers gitleaks when available; falls back to six built-in regexes.
#              Output: file:line:severity:pattern  (no surrounding code excerpt).
#              This is a FILTER feeding model triage, not an authoritative finding.
# @arg --path <dir>    Root directory to scan (default: current working dir).
# @arg --format json   Emit newline-delimited JSON instead of plain text.
# @arg --self-test     Run internal fixture tests (no network, no external deps).
# @exitcode 0  No Critical/High secrets found.
# @exitcode 1  Critical/High secret(s) found — triage required.
# @exitcode 2  Usage error.
set -Eeuo pipefail
shopt -s inherit_errexit 2> /dev/null || true
IFS=$'\n\t'
trap 'printf >&2 "error: %s:%d: exit %d\n" "${BASH_SOURCE[0]}" "$LINENO" "$?"' ERR

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
SCAN_PATH="."
OUTPUT_FORMAT="text"
SELF_TEST=0

usage() {
  printf >&2 'Usage: bash scan-secrets.sh [--path <dir>] [--format json] [--self-test]\n'
  exit 2
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --path)
      [[ $# -ge 2 ]] || usage
      SCAN_PATH="$2"
      shift 2
      ;;
    --format)
      [[ $# -ge 2 ]] || usage
      OUTPUT_FORMAT="$2"
      shift 2
      ;;
    --self-test)
      SELF_TEST=1
      shift
      ;;
    -h | --help) usage ;;
    *) usage ;;
  esac
done

# ---------------------------------------------------------------------------
# Built-in regex patterns (six from SKILL.md § Secrets Detection Patterns).
# Each entry: SEVERITY|LABEL|EXTENDED_REGEX
# ---------------------------------------------------------------------------
declare -a PATTERNS=(
  'Critical|aws-access-key|AKIA[0-9A-Z]{16}'
  'Critical|private-key|-----BEGIN [A-Z ]*PRIVATE KEY-----'
  'Critical|password-assignment|password[[:space:]]*=[[:space:]]*['"'"'"][^'"'"'"]{3,}['"'"'"]'
  'Critical|database-url|(mysql|postgres|mongodb)://[^@[:space:]]{3,}@'
  'High|jwt-token|eyJ[A-Za-z0-9_-]{10,}\.[Ee][Yy][Jj]'
  'High|generic-api-key|[Aa][Pp][Ii][_-]?[Kk][Ee][Yy][[:space:]]*=[[:space:]]*[A-Za-z0-9_-]{32,45}'
)

# File globs to scan when in fallback mode (mirrors SKILL.md § Where to Check).
declare -a INCLUDE_GLOBS=(
  '*.swift' '*.m' '*.go' '*.py' '*.js' '*.ts' '*.rb' '*.java' '*.kt'
  '*.env' '*.env.*' '*.json' '*.yaml' '*.yml' '*.toml' '*.ini' '*.conf' '*.cfg' '*.xml'
  'Dockerfile' 'docker-compose*' '.travis.yml' '*.gitlab-ci.yml' 'Jenkinsfile'
  '*.sh' '*.bash' '*.zsh'
)

# ---------------------------------------------------------------------------
# emit_line FILE LINENO SEVERITY PATTERN
# Writes exactly one file:line:severity:pattern line (or JSON).
# ---------------------------------------------------------------------------
emit_line() {
  local file="$1" lineno="$2" severity="$3" pattern="$4"
  if [[ "$OUTPUT_FORMAT" == "json" ]] && command -v jq > /dev/null 2>&1; then
    printf '{"file":%s,"line":%s,"severity":%s,"pattern":%s}\n' \
      "$(printf '%s' "$file" | jq -Rs .)" \
      "$(printf '%s' "$lineno" | jq -Rs .)" \
      "$(printf '%s' "$severity" | jq -Rs .)" \
      "$(printf '%s' "$pattern" | jq -Rs .)"
  else
    printf '%s:%s:%s:%s\n' "$file" "$lineno" "$severity" "$pattern"
  fi
}

# ---------------------------------------------------------------------------
# validate_patterns
# Compile-check every built-in ERE once, before the scan. A pattern the local grep
# rejects otherwise fails per-file with no signal at all, which turns a broken
# detector into a clean-looking scan — the worst failure mode for a scanner.
# Necessary but NOT sufficient: dialects disagree on what is invalid (BSD accepts an
# unmatched `)` as a literal), so this cannot catch a pattern that compiles yet
# matches the wrong thing. That half is covered by the per-pattern specimen
# assertions in tests/shell/skills/scan-secrets.bats.
# ---------------------------------------------------------------------------
validate_patterns() {
  local entry label regex err rc
  for entry in "${PATTERNS[@]}"; do
    label="${entry#*|}"
    label="${label%%|*}"
    regex="${entry#*|}"
    regex="${regex#*|}"
    rc=0
    # /dev/null is empty, so rc 1 ("no match") means the pattern compiled.
    err=$(grep -qE -- "$regex" /dev/null 2>&1) || rc=$?
    if [[ $rc -gt 1 ]]; then
      printf >&2 'scan-secrets: built-in pattern %s is invalid: %s\n' "$label" "$err"
      exit 2
    fi
  done
}

# ---------------------------------------------------------------------------
# fallback_scan ROOT
# Grep-based scan against built-in patterns.  Prints findings; returns 1 if any.
# ---------------------------------------------------------------------------
fallback_scan() {
  local root="$1"
  local found=0
  local engine_failed=0

  validate_patterns

  # Collect matching files into a NUL-delimited temp file.
  local tmpfile
  tmpfile="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$tmpfile'" RETURN

  # Build find -name alternation array.
  local -a find_args=("$root" -type f \()
  local first=1
  local glob
  for glob in "${INCLUDE_GLOBS[@]}"; do
    if [[ $first -eq 1 ]]; then
      find_args+=(-name "$glob")
      first=0
    else
      find_args+=(-o -name "$glob")
    fi
  done
  find_args+=(\))

  find "${find_args[@]}" -print0 2> /dev/null > "$tmpfile" || true

  local filepath entry severity label regex lineno relpath grep_out grep_rc
  while IFS= read -r -d '' filepath; do
    for entry in "${PATTERNS[@]}"; do
      severity="${entry%%|*}"
      label="${entry#*|}"
      label="${label%%|*}"
      # Strip exactly the two leading fields; the regex is the whole remainder.
      # `${entry##*|}` would strip through the LAST `|`, which truncates any
      # pattern containing an alternation (database-url) into a malformed ERE.
      regex="${entry#*|}"
      regex="${regex#*|}"

      # grep -nE: line numbers, ERE; -I: skip binary; output is "lineno:match".
      # We only need lineno, so cut to first field.
      # grep's stderr is deliberately NOT discarded: a `2> /dev/null` here hid a
      # dead pattern for the whole life of the database-url regex, and would hide
      # the next one identically. Unreadable files are worth surfacing too.
      #
      # The exit status is discriminated rather than blanket-swallowed, matching
      # gitleaks_scan's `gl_exit -gt 1` treatment below. grep returns 1 for "no
      # match" — the overwhelmingly common, entirely normal case — and >1 only
      # when the engine itself failed: a malformed ERE, or a BSD grep that traps
      # on a pattern it cannot compile (observed on macOS as
      # `Trace/BPT trap: 5`, i.e. status 133). A previous `|| true` made those
      # two indistinguishable, so a crashed scan still exited 0 — the documented
      # "no Critical/High findings" code — and read as a clean bill of health.
      # This is the same failure class the stderr comment above describes, one
      # layer up in the exit code, so it fails closed here.
      grep_out="$(grep -nEI -- "$regex" "$filepath"; printf '\034%s' "$?")"
      grep_rc="${grep_out##*$'\034'}"
      grep_out="${grep_out%$'\034'*}"
      if [[ "$grep_rc" -gt 1 ]]; then
        printf >&2 'scan-secrets: ENGINE FAILURE (exit %s) on pattern "%s" in %s\n' \
          "$grep_rc" "$label" "${filepath#"$root"/}"
        engine_failed=1
        continue
      fi
      while IFS= read -r lineno; do
        [[ -z "$lineno" ]] && continue
        relpath="${filepath#"$root"/}"
        emit_line "$relpath" "$lineno" "$severity" "$label"
        found=1
      done < <(printf '%s' "$grep_out" | cut -d: -f1)
    done
  done < "$tmpfile"

  # An engine failure outranks both outcomes: the scan is not clean (0) and not
  # "findings present" (1) — it is unreliable, and must not be reported as
  # either. 2 is the script's existing hard-error code.
  if [[ "$engine_failed" -eq 1 ]]; then
    printf >&2 'scan-secrets: scan is UNRELIABLE — one or more patterns crashed the regex engine; results are incomplete. Install gitleaks, or fix the offending pattern, before treating this scan as evidence.\n'
    return 2
  fi

  return "$found"
}

# ---------------------------------------------------------------------------
# gitleaks_scan ROOT
# Uses gitleaks detect --no-git; parses JSON report.  Returns 1 if findings.
# Falls back to fallback_scan on gitleaks error.
# ---------------------------------------------------------------------------
gitleaks_scan() {
  local root="$1"
  local tmpout
  tmpout="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$tmpout'" RETURN

  local gl_exit=0
  # --redact: never write the secret value to the report.
  gitleaks detect \
    --source "$root" \
    --report-format json \
    --report-path "$tmpout" \
    --no-git \
    --redact \
    2> /dev/null || gl_exit=$?

  # exit 0 = clean; exit 1 = findings; anything else = error → fallback.
  if [[ $gl_exit -gt 1 ]]; then
    printf >&2 'scan-secrets: gitleaks exited %d; falling back to regex mode\n' "$gl_exit"
    fallback_scan "$root"
    return
  fi

  if [[ ! -s "$tmpout" ]]; then
    return 0
  fi

  local found=0
  local file lineno rule severity relpath
  while IFS=$'\t' read -r file lineno rule; do
    severity="High"
    case "$rule" in
      *aws* | *private* | *password* | *database* | *secret*)
        severity="Critical"
        ;;
    esac
    relpath="${file#"$root"/}"
    emit_line "$relpath" "$lineno" "$severity" "$rule"
    found=1
  done < <(jq -r '.[] | [.File, (.StartLine | tostring), .RuleID] | @tsv' "$tmpout" 2> /dev/null || true)

  return "$found"
}

# ---------------------------------------------------------------------------
# run_self_test
# Creates a temp dir, plants a fake secret and a clean file, then verifies:
#   - exit code is 1 (findings present)
#   - the planted file appears in output
#   - the clean file does NOT appear in output
#   - every output line has at least 4 colon-delimited fields (no code excerpts)
# ---------------------------------------------------------------------------
run_self_test() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  # Happy path: planted fake AWS key (Critical hit expected).
  printf 'export AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE\n' > "$tmp/secrets.env"
  # Edge case: clean file (must produce zero findings).
  printf 'greeting=hello\nname=world\n' > "$tmp/clean.env"
  # Additional Critical: fake private key header.
  # Use %s to avoid printf treating leading dashes as a flag on macOS.
  printf '%s\n' '-----BEGIN RSA PRIVATE KEY-----' 'MIIEowIBAAK...' '-----END RSA PRIVATE KEY-----' > "$tmp/id_rsa.conf"

  # Suppress ERR trap: exit 1 from the subprocess means findings found (expected).
  trap - ERR
  local output exit_code
  exit_code=0
  output="$(bash "${BASH_SOURCE[0]}" --path "$tmp" 2> /dev/null)" || exit_code=$?

  if [[ $exit_code -ne 1 ]]; then
    printf >&2 'self-test FAIL: expected exit 1, got %d\noutput:\n%s\n' "$exit_code" "$output"
    exit 1
  fi

  if ! printf '%s\n' "$output" | grep -q 'secrets.env'; then
    printf >&2 'self-test FAIL: secrets.env not in findings\noutput:\n%s\n' "$output"
    exit 1
  fi

  if printf '%s\n' "$output" | grep -q 'clean.env'; then
    printf >&2 'self-test FAIL: clean.env appeared in findings\noutput:\n%s\n' "$output"
    exit 1
  fi

  # Every non-empty output line must have >= 4 colon-separated fields.
  local line field_count
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    field_count="$(printf '%s' "$line" | awk -F: '{print NF}')"
    if [[ "$field_count" -lt 4 ]]; then
      printf >&2 'self-test FAIL: malformed line (< 4 fields): %s\n' "$line"
      exit 1
    fi
  done <<< "$output"

  printf 'scan-secrets: self-test OK\n'
  exit 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
[[ $SELF_TEST -eq 1 ]] && run_self_test

if [[ ! -d "$SCAN_PATH" ]]; then
  printf >&2 'scan-secrets: path not a directory: %s\n' "$SCAN_PATH"
  exit 2
fi

# Resolve to absolute path (portable: avoid readlink -f which is absent on old macOS).
SCAN_PATH="$(cd -- "$SCAN_PATH" && pwd -P)"

# Disable the ERR trap before the scan: exit code 1 (findings present) is
# intentional and must not be mistaken for an unexpected error.
trap - ERR

found=0
if command -v gitleaks > /dev/null 2>&1; then
  gitleaks_scan "$SCAN_PATH" || found=$?
else
  printf >&2 'scan-secrets: gitleaks not found — using built-in regex fallback\n'
  fallback_scan "$SCAN_PATH" || found=$?
fi

exit "$found"
