#!/usr/bin/env bash
if [ -n "${CODEX_CAPTURE_JSON_FILE:-}" ]; then
  jq -c . >> "$CODEX_CAPTURE_JSON_FILE"
elif [ -n "${CODEX_CAPTURE_FILE:-}" ]; then
  jq -r '.tool_input.file_path // empty' >> "$CODEX_CAPTURE_FILE"
else
  cat
fi
