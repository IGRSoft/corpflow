#!/usr/bin/env bash
# scan-secrets-selftest.sh — the `--self-test` harness for scan-secrets.sh.
#
# SOURCED, never executed: scan-secrets.sh loads this file only on the `--self-test`
# path, so the production path never pays for it. Sourcing leaves the caller's
# `$0` and every function it has already defined in scope — this file reads the
# caller's helpers and is not standalone.
#
# Contract: defines `run_self_test`, which owns the exit for this invocation.

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
  # `$0`, not BASH_SOURCE: this file is sourced, so BASH_SOURCE[0] names the
  # harness, which has no entry point. `$0` is still the caller.
  output="$(bash "$0" --path "$tmp" 2> /dev/null)" || exit_code=$?

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
