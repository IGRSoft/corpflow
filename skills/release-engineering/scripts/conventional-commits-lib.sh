#!/usr/bin/env bash
# @description Conventional-commit parsing shared by changelog-from-git.sh and
#              version-bump-from-git.sh. Sourced, never executed.
#              Bash 3.2+ compatible (no assoc arrays, no ${var,,}).
#
# Both consumers must route breaking-change detection through cc_parse; a second
# detector lets the changelog print BREAKING while the bump says MINOR.
#
# shellcheck disable=SC2034  # the CC_* globals are this file's return channel

# cc_parse <full-commit-message>
# Takes the WHOLE message, not a subject — `BREAKING CHANGE:` is a footer.
# Sets CC_SUBJECT / CC_CONVENTIONAL / CC_TYPE / CC_SCOPE / CC_DESC / CC_BREAKING.
# Returns 1 on a blank message, so call it as `if cc_parse "$m"; then`.
cc_parse() {
  local msg="$1"

  CC_SUBJECT=""
  CC_CONVENTIONAL=0
  CC_TYPE=""
  CC_SCOPE=""
  CC_DESC=""
  CC_BREAKING=0

  # Leading blank lines would otherwise make the subject parse as empty.
  msg="$(printf '%s' "$msg" | sed '/[^[:space:]]/,$!d')"

  local first="${msg%%$'\n'*}"
  first="$(printf '%s' "$first" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  CC_SUBJECT="$first"
  if [[ -z "$first" ]]; then
    return 1
  fi

  # Case-sensitive by spec: matching loosely would promote prose ("this is a
  # breaking change: ...") to MAJOR.
  if [[ "$msg" == *$'\n'* ]]; then
    local body="${msg#*$'\n'}"
    if printf '%s\n' "$body" | grep -qE '^BREAKING[ -]CHANGE:'; then
      CC_BREAKING=1
    fi
  fi

  local cc_re='^([a-zA-Z]+)(\([^)]*\))?(!)?: ' # in a var to appease SC2221
  if [[ "$first" =~ $cc_re ]]; then
    CC_CONVENTIONAL=1
    CC_TYPE="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')"

    local raw_scope="${BASH_REMATCH[2]}"
    if [[ -n "$raw_scope" ]]; then
      CC_SCOPE="${raw_scope:1:${#raw_scope}-2}"
    fi

    if [[ "${BASH_REMATCH[3]}" == "!" ]]; then
      CC_BREAKING=1
    fi

    local prefix_len="${#BASH_REMATCH[0]}"
    CC_DESC="$(printf '%s' "${first:$prefix_len}" | sed 's/^[[:space:]]*//')"
  fi

  return 0
}

# cc_classify_section <type> <breaking-flag>
# Keep-a-Changelog section name; empty for silent types. An empty type
# (non-conventional commit) falls through to Other so it is never dropped.
# A breaking commit is never silent: suppressing it would ship a MAJOR bump
# whose changelog says nothing about the break.
cc_classify_section() {
  local type="$1" breaking="${2:-0}"
  local section

  case "$type" in
    feat) section='Added' ;;
    fix) section='Fixed' ;;
    refactor | perf) section='Changed' ;;
    docs | style | test | chore | ci | build) section='' ;;
    *) section='Other' ;;
  esac

  if [[ -z "$section" && "$breaking" == "1" ]]; then
    section='Changed'
  fi

  printf '%s' "$section"
}

# cc_bump_for <type> <breaking-flag>
# Bump one commit alone justifies: major|minor|patch|none. Breaking is tested
# first and ignores type, so `fix!:` and a footer on `chore:` also escalate.
cc_bump_for() {
  local type="$1" breaking="$2"

  if [[ "$breaking" == "1" ]]; then
    printf 'major'
    return 0
  fi

  case "$type" in
    feat) printf 'minor' ;;
    fix | refactor | perf) printf 'patch' ;;
    *) printf 'none' ;;
  esac
}

# cc_bump_rank <bump>
# Severity ordinal: none=0 < patch=1 < minor=2 < major=3. Unknown ranks 0 so a
# mistyped bump cannot win an aggregation.
cc_bump_rank() {
  case "$1" in
    major) printf '3' ;;
    minor) printf '2' ;;
    patch) printf '1' ;;
    *) printf '0' ;;
  esac
}

# cc_bump_max <bump-a> <bump-b>
# Folding this over a range is what makes 3x fix + 1x feat resolve to minor.
cc_bump_max() {
  local a="$1" b="$2"
  if [[ "$(cc_bump_rank "$a")" -ge "$(cc_bump_rank "$b")" ]]; then
    printf '%s' "$a"
  else
    printf '%s' "$b"
  fi
}

# cc_collect_records <range> <repo-path> <input-file>
# Emits NUL-separated whole commit messages. The last record has no trailing
# NUL, so read them with `while IFS= read -r -d '' m || [[ -n "$m" ]]`.
# Records are whole messages rather than subjects so footers survive to cc_parse.
# A NUL-free file is read one record per line, keeping subject-list files valid.
cc_collect_records() {
  local range="$1" repo="$2" file="$3"

  if [[ -n "$file" ]]; then
    if [[ ! -r "$file" ]]; then
      printf >&2 'error: cannot read file: %s\n' "$file"
      return 1
    fi
    if [[ "$(LC_ALL=C tr -dc '\000' < "$file" | wc -c | tr -d ' ')" -gt 0 ]]; then
      cat -- "$file"
    else
      local line
      while IFS= read -r line || [[ -n "$line" ]]; do
        printf '%s\0' "$line"
      done < "$file"
    fi
    return 0
  fi

  if [[ ! "$range" =~ ^[a-zA-Z0-9_.^~/@{}-]+(\.\.[a-zA-Z0-9_.^~/@{}-]+)?$ ]]; then
    printf >&2 'error: git range contains unsafe characters: %s\n' "$range"
    return 1
  fi

  # -z is what makes NUL the record separator; without it `format:` joins
  # records with a newline and every record after the first arrives blank-led.
  if [[ -n "$repo" ]]; then
    git -C "$repo" log -z "$range" --pretty=format:'%B' --
  else
    git log -z "$range" --pretty=format:'%B' --
  fi
}
