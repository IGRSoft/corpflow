#!/usr/bin/env bash
# Test-Execution Authority gate — PreToolUse hook (igrsoft worktask plugin).
#
# Enforces skills/shared/testing-strategy.md § Test-Execution Authority: only
# DV (scoped) and QA (scoped + full) may execute tests; every other stage is
# denied, and DV itself is denied a full-suite run. Stage resolution reads
# .context/state.json ONLY — never agent_type or an env var claiming to carry
# it — so a nested delegate inherits the in-progress stage automatically,
# closing the delegation-path hole at the delegate's own leaf Bash call.
#
# The Task branch is OBSERVE-ONLY, never a deny: a delegation prompt quoting
# this very ban contains every runner name (including this worktask's own
# DV/DR/SR/QA dispatch prompts), so a prose-matching deny would refuse to
# dispatch the stages implementing the policy.
#
# Exit code is ALWAYS 0 — the decision travels in JSON
# (hookSpecificOutput.permissionDecision, matching dv-screenshot-gate.sh), so
# a malformed emission fails OPEN by design: this is a backstop, not a
# sandbox — tool-grant narrowing and the orchestrator's dispatch-time ban
# banner are the primary controls. Escape hatch: IGRSOFT_TEST_GATE=off
# (process env only — a command-string prefix cannot reach it, since this
# hook's env comes from the CC parent process, not the command string).
#
# Deliberately no `set -e`: several branches rely on a compound `[ ]`/case
# test evaluating false as ordinary control flow, and `set -e` would abort
# mid-classification instead of falling through, turning a fail-open
# backstop fail-*closed*. `set -f` is added as defense-in-depth (every
# glob-able expansion is already quoted or inside a `case` pattern).
#
# --self-test: fixture-driven, no live process, covers the fail-open ladder.
set -u
set -f

SELF_TEST=0
[ "${1:-}" = "--self-test" ] && SELF_TEST=1

# ---------------------------------------------------------------------------
# RUNNERS — parity counterpart of testing-strategy.md's canonical runner
# list; test-authority-matrix.bats asserts the two enumerations agree. Head
# token after wrapper-stripping is matched against this set.
#
# MULTI_PURPOSE_RUNNERS is a subset: these heads have non-test uses (`swift
# build`, `./gradlew assembleDebug`, `xcodebuild archive`, `go build`, `npm
# run lint`, ...), so a bare head match is NOT sufficient — the subcommand
# must name "test" (or, for gradle, a task containing "test") before the
# invocation classifies as test execution at all. Single-purpose runners
# (bats, pytest, ctest, jest, vitest, playwright, rspec) have no non-test
# invocation shape worth distinguishing.
# ---------------------------------------------------------------------------
RUNNERS="bats swift pytest ctest cargo jest vitest playwright rspec gradle gradlew python python3 go make npx uvx pnpm yarn bunx xcodebuild dotnet npm"
MULTI_PURPOSE_RUNNERS="swift cargo go npm pnpm yarn dotnet xcodebuild gradle gradlew"

# Known bypasses (measured, not guessed): $(...)/backticks/here-docs aren't
# segment-split; `find -exec`/`xargs` and a renamed or written-then-executed
# runner never reach head position; `env -i`/`/usr/bin/env`/`\pytest` aren't
# unwrapped by strip_assignments; `bash -c'x'` with no space before the quote
# misses the `-c ` match; `bash -c 'bash -c "pytest"'` beyond MAX_RECURSE_DEPTH
# classifies not_test (allow) rather than chasing further — an accepted
# trade against unbounded recursion (CWE-674), not a code gap to close;
# `npm test --dry-run` classifies build_only and allows, but `--dry-run` has
# no effect on `npm test`/run-scripts (only the `npm install` family) — npm
# actually executes the script (QA-confirmed live), so this is a real,
# accepted bypass, not merely a theoretical one. This hook is a backstop, not
# a sandbox — tool-grant narrowing and the orchestrator's ban banner are the
# controls without these gaps.

# ---------------------------------------------------------------------------
# strip_assignments <segment> -> echoes the segment with leading VAR=value /
# `env [VAR=value...]` wrappers removed. Shared by classify_segment
# (classification) and run_gate (command_head derivation) so a secret in a
# leading env assignment (e.g. `API_KEY=sk-... pytest x`) can never reach
# either the classifier's runner-name check or the audit log.
# ---------------------------------------------------------------------------
strip_assignments() {
  local _s _next
  _s="$1"
  # A quoted value containing a space (`FOO="a b" pytest x`) is not one
  # space-delimited word, so a naive "strip to the next space" leaves a
  # fragment of the value in head position — which then either drops the
  # invocation out of RUNNERS entirely (a deny bypass: the gate never fires)
  # or, if the fragment happens to collide with a real runner name, denies
  # something that was never a test at all. The regex below consumes a
  # double-quoted, single-quoted, or bare (no-space) value as one unit.
  while :; do
    case "$_s" in
      env\ *) _s="${_s#env }" ;;
      *)
        _next="$(printf '%s' "$_s" | sed -E 's/^[A-Za-z_][A-Za-z0-9_]*=("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:]]*)[[:space:]]+//')"
        [ "$_next" != "$_s" ] || break
        _s="$_next"
        ;;
    esac
  done
  printf '%s' "$_s"
}

# ---------------------------------------------------------------------------
# classify_cmd <command string> -> echoes: full_test_run | scoped_test_run |
#                                          build_only | not_test
# Pure function of the command string. No I/O.
# ---------------------------------------------------------------------------
classify_cmd() {
  local _cmd="$1" _old_ifs _result _norm _seg _class

  _old_ifs="$IFS"
  _result="not_test"
  # Segment split on && || ; | and newline. Command substitution, backticks,
  # and here-docs are NOT split — a documented, accepted hole (see the
  # bypass note above RUNNERS).
  _norm=$(printf '%s' "$_cmd" | sed -E 's/(&&|\|\||;|\|)/\n/g')
  while IFS= read -r _seg; do
    [ -n "$_seg" ] || continue
    _class=$(classify_segment "$_seg")
    case "$_class" in
      full_test_run) _result="full_test_run" ;;
      scoped_test_run) [ "$_result" = "not_test" ] || [ "$_result" = "build_only" ] && _result="scoped_test_run" ;;
      build_only) [ "$_result" = "not_test" ] && _result="build_only" ;;
    esac
    [ "$_result" = "full_test_run" ] && break
  done <<EOF
$_norm
EOF
  IFS="$_old_ifs"
  printf '%s' "$_result"
}

# classify_segment <segment> [<depth>]: strip leading VAR=value / env
# wrappers, a launcher/no-op prefix, recurse into `bash -c '...'` up to
# MAX_RECURSE_DEPTH levels, then match the head token against RUNNERS.
# depth is capped, not "depth 1 only" as an earlier version of this comment
# claimed — `bash -c 'bash -c "pytest"'` genuinely chases two levels; without
# a hard cap, recursion is bounded only by the ~10k-character command-length
# limit CC itself enforces (CWE-674), which is thousands of `sed` forks and
# real latency on a single tool call, not a crash, but not "depth 1" either.
MAX_RECURSE_DEPTH=2
classify_segment() {
  local _seg _depth _head_full _head _rest _launcher _inner _mod _padded _subcmd _rest_for_selection _rest_effective _second _task

  _seg="$1"
  _depth="${2:-0}"
  if [ "$_depth" -ge "$MAX_RECURSE_DEPTH" ]; then
    printf 'not_test'; return
  fi

  # trim leading/trailing whitespace
  _seg="$(printf '%s' "$_seg" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  [ -n "$_seg" ] || { printf 'not_test'; return; }

  _seg="$(strip_assignments "$_seg")"
  [ -n "$_seg" ] || { printf 'not_test'; return; }

  # Strip a package-runner launcher prefix, or a no-op timing/backgrounding
  # wrapper, so the real runner name reaches the head-token check below
  # (`npx jest` must classify on `jest`, not `npx`; `time pytest x` on
  # `pytest`, not `time`).
  for _launcher in "npx " "uvx " "uv run " "pnpm exec " "yarn dlx " "bunx " "time " "nohup " "command " "exec "; do
    case "$_seg" in
      "$_launcher"*) _seg="${_seg#"$_launcher"}" ;;
    esac
  done

  _head_full="${_seg%% *}"
  _head="${_head_full##*/}"
  _rest="${_seg#"$_head_full"}"

  # bash -c '...' / sh -c '...' (and the -lc/-ec/-xc combined-short-option
  # spellings, e.g. `bash -lc '...'`) wraps a real command in a string;
  # recurse into it up to MAX_RECURSE_DEPTH.
  case "$_head" in
    bash|sh|zsh|dash)
      case "$_rest" in
        *" -c "*|*" -lc "*|*" -ec "*|*" -xc "*)
          _inner="${_rest#*c }"
          _inner="${_inner#\'}"
          _inner="${_inner%\'}"
          _inner="${_inner#\"}"
          _inner="${_inner%\"}"
          classify_segment "$_inner" "$((_depth + 1))"
          return
          ;;
      esac
      ;;
  esac

  # python[3] -m <module> collapses to "python -m <module>". A bare
  # `python3 script.py` (no `-m pytest`/`-m unittest`) is not a recognized
  # test invocation at all — it is script execution, not test execution —
  # so it classifies `not_test` rather than being treated as a runner merely
  # because the interpreter's name happens to be in RUNNERS. Without this,
  # every `python3 <anything>.py` at a banned stage would falsely deny.
  if [ "$_head" = "python3" ] || [ "$_head" = "python" ]; then
    case "$_rest" in
      *" -m "*)
        _mod="${_rest#*-m }"
        _mod="${_mod%% *}"
        case "$_mod" in
          pytest|unittest) _head="python -m $_mod"; _rest="${_rest#*"$_mod"}" ;;
          *) printf 'not_test'; return ;;
        esac
        ;;
      *) printf 'not_test'; return ;;
    esac
  fi

  # REPO_FULL named full-runners: no selection surface by construction.
  case "$_head_full" in
    */run-tests.sh|run-tests.sh) printf 'full_test_run'; return ;;
  esac
  case "$_seg" in
    make\ test|make\ coverage|make\ test-ios) printf 'full_test_run'; return ;;
    make\ test\ *|make\ coverage\ *|make\ test-ios\ *) printf 'full_test_run'; return ;;
    *unittest\ discover*) printf 'full_test_run'; return ;;
  esac

  # /<plugin>:build-test in command-string form (Bash rarely spells it this
  # way — the Skill branch in run_gate is the primary path). Anchored to
  # _head_full like every other runner: an unanchored substring match against
  # the whole segment would also fire on `cat docs/build-test.md` or
  # `git log --grep=build-test` — neither executes anything, both must stay
  # allowed since build-only verification is permitted everywhere.
  _padded=" $_seg "
  case "$_head_full" in
    build-test|*/build-test|*:build-test)
      case "$_padded" in
        *' --no-test '*|*' --count '*|*' --dry-run '*|*' --collect-only '*|*' --list-tests '*|*' --list '*)
          printf 'build_only'; return ;;
        *)
          printf 'full_test_run'; return ;;
      esac
      ;;
  esac

  case " $RUNNERS " in
    *" $_head "*) : ;;
    *)
      case "$_head" in
        python\ -m\ *) : ;;
        *) printf 'not_test'; return ;;
      esac
      ;;
  esac

  # Multi-purpose runners (swift/cargo/go/npm/pnpm/yarn/dotnet/xcodebuild/
  # gradle/gradlew) have non-test invocation shapes (`swift build`,
  # `./gradlew assembleDebug`, `xcodebuild archive`, `go build`) that are
  # build-only, not test execution. A bare head match on these is NOT
  # sufficient evidence — without the subcommand check below, a build-only
  # command like `./gradlew assembleDebug` would falsely deny at every
  # banned stage, breaking the promise that build-only stays allowed
  # everywhere. Require the "test" subcommand (gradle/gradlew: any task
  # NAME containing "test", e.g. `testDebugUnitTest`, `connectedAndroidTest`).
  #
  # _rest_effective drops the consumed subcommand/task token from _rest so
  # the trailing-content selector check below judges only what follows it —
  # otherwise the subcommand word itself ("test") is mistaken for a
  # positional selector and `swift test` misreads as scoped instead of full.
  _rest_effective="$_rest"
  case " $MULTI_PURPOSE_RUNNERS " in
    *" $_head "*)
      case "$_head" in
        gradle|gradlew)
          # Exclude task-name prefixes that are pure build steps even though
          # their full name contains "test" — `assembleAndroidTest` compiles
          # a test APK, `installDebugAndroidTest` installs one,
          # `compileDebugUnitTestKotlin` is a compile step. None of the
          # three execute a test; denying them breaks the same build-only
          # promise the subcommand check exists to protect.
          _task="$(printf '%s' "$_rest" | sed -E 's/^[[:space:]]+//')"
          _task="${_task%% *}"
          case "$_task" in
            install*|assemble*|compile*) printf 'not_test'; return ;;
          esac
          case "$_rest" in
            *[Tt]est*) : ;;              # task name mentions test (case-insensitive-ish)
            *) printf 'not_test'; return ;;
          esac
          _rest_effective="$(printf '%s' "$_rest" | sed -E 's/^[[:space:]]*[^ ]*//')"
          ;;
        *)
          _subcmd="$(printf '%s' "$_rest" | sed -E 's/^[[:space:]]+//')"
          _subcmd="${_subcmd%% *}"
          case "$_subcmd" in
            test) _rest_effective="$(printf '%s' "$_rest" | sed -E 's/^[[:space:]]*test//')" ;;
            # `npm run test` / `pnpm run test` / `yarn run test` is the other
            # common package.json-script invocation shape for the same
            # thing `npm test` says directly — accept "run test" as an
            # equivalent subcommand pair for these three heads only.
            run)
              case "$_head" in
                npm|pnpm|yarn)
                  _second="$(printf '%s' "$_rest" | sed -E 's/^[[:space:]]*run[[:space:]]+//')"
                  _second="${_second%% *}"
                  case "$_second" in
                    test) _rest_effective="$(printf '%s' "$_rest" | sed -E 's/^[[:space:]]*run[[:space:]]+test//')" ;;
                    *) printf 'not_test'; return ;;
                  esac
                  ;;
                *) printf 'not_test'; return ;;
              esac
              ;;
            *) printf 'not_test'; return ;;
          esac
          ;;
      esac
      ;;
  esac

  # Build-only / collection-only flags override execution classification.
  # Token-exact (padded) matches only — a substring match would let `--list`
  # wrongly fire on `--listener`, misclassifying a real test invocation as
  # build-only. Bare `-c` is build-only ONLY for bats (its count flag); for
  # every other runner `-c`/`--config` is a normal configuration flag
  # (`swift test -c release`, `pytest -c pytest.ini` both execute tests) —
  # treating it as build-only there would let one flag bypass the DV
  # full-suite deny below.
  # Extends the original five-flag set with four more sanctioned
  # collect/compile-without-run forms: `cargo test --no-run` (compiles,
  # runs nothing), `ctest -N`/`--show-only` (lists tests), `--listTests`
  # (jest's camelCase spelling of the same idea), `--co` (pytest's short
  # form of --collect-only).
  case "$_padded" in
    *' --no-test '*|*' --dry-run '*|*' --collect-only '*|*' --list-tests '*|*' --list '*|*' --no-run '*|*' -N '*|*' --show-only '*|*' --listTests '*|*' --co '*)
      printf 'build_only'; return ;;
  esac
  if [ "$_head" = "bats" ]; then
    case "$_padded" in
      *' -c '*|*' --count '*) printf 'build_only'; return ;;
    esac
  fi

  # Selection-argument predicate, shared with agents/developer.md D2 and
  # agents/qa-engineer.md Q1's own scoped/full test-run counters: a command
  # carrying >=1 test-selection flag (or, below, a trailing positional
  # test-target argument) classifies scoped_test_run, otherwise full_test_run.
  case "$_seg" in
    *" -f "*|*"--filter"*|*" -k "*|*"--only-testing:"*|*" -run "*|*"--testcase"*|*"::"*|*"-gtest_filter"*|*" -R "*|*" -g "*|*" -t "*|*"--tests "*)
      printf 'scoped_test_run'; return ;;
  esac
  # A bare runner with a trailing positional path/file argument also counts
  # as a selection argument (`bats tests/foo.bats`, `cargo test foo`) — the
  # positional limb of the shared predicate above; without it DV's own bare
  # `bats <file>` would misclassify as full and deny DV its own run. A
  # whole-tree argument (`pytest tests/`) therefore reads as scoped, not
  # full — a deliberate policy limit, not a gap specific to this hook.
  #
  # `-c <value>` / `--config(uration) <value>` is a CONFIGURATION flag for
  # swift/pytest, not a selector — strip it first, or `swift test -c
  # release` misreads as scoped and slips past the DV full-suite deny on the
  # strength of one ordinary flag.
  _rest_for_selection="$(printf '%s' "$_rest_effective" | sed -E 's/(^| )-c ([^ ]+)/ /g; s/(^| )--config(uration)? ([^ ]+)/ /g')"
  if [ -n "$(printf '%s' "$_rest_for_selection" | sed -E 's/^[[:space:]]+//')" ]; then
    printf 'scoped_test_run'; return
  fi
  printf 'full_test_run'
}

# ---------------------------------------------------------------------------
# resolve_stage <ctx> -> echoes the single in_progress stage code, or empty.
# Every ambiguity resolves to empty (never a guess) — no state.json, no jq,
# an unparseable file, zero or more than one stage in progress, or a stage
# token this hook doesn't recognize. An empty result is the caller's signal
# to allow unconditionally: there is no reliable "who is acting" answer, and
# guessing wrong in the deny direction would deadlock an unrelated session.
# Fixture-reachable via a temp .context/ root — no live process needed.
# ---------------------------------------------------------------------------
resolve_stage() {
  local _ctx="$1" _state _stages
  _state="$_ctx/state.json"
  [ -f "$_state" ] || { printf ''; return; }
  command -v jq >/dev/null 2>&1 || { printf ''; return; }

  _stages=$(jq -r '
    if (.stages|type=="object") then
      (.stages | to_entries | map(select(.value.status=="in_progress")) | map(.key))
    else [] end
    | join(",")
  ' "$_state" 2>/dev/null) || { printf ''; return; }

  case "$_stages" in
    # Empty (no stage in progress — the common between-stage window and every
    # non-worktask session) or more than one (ambiguous — cannot tell which
    # of two concurrent stages issued this call) both resolve to unknown.
    *,*|"") printf ''; return ;;
  esac

  case "$_stages" in
    PL|AR|TL|DV|DR|SR|QA|DC|RE|FN|ST|IR|ET) printf '%s' "$_stages" ;;
    *) printf '' ;;  # not a recognized stage code — treat as unresolved
  esac
}

# ---------------------------------------------------------------------------
# run_gate <payload json> <ctx dir> -> echoes decision JSON (deny) or nothing
# (allow/observe). Appends an audit row for a deny or a Task observation.
# Parameterized over .context/ so every branch is fixture-reachable, per the
# dv-screenshot-gate.sh idiom (run_gate <payload> <ctx>).
# ---------------------------------------------------------------------------
run_gate() {
  local _payload="$1" _ctx="$2"
  local _tool _stage _subagent _prompt _matched _class _cmd _cmd_head _stripped
  local _skill_cmd _reason _deny _sentinel

  # Process-env escape hatch, checked first: cheapest possible check, and
  # the human relief valve named in the deny message below. A security
  # control switching off should never be silent (CWE-778): note it once per
  # .context/ via a builtin [ -f ] sentinel, so the zero-fork fast path is
  # untouched on every other call and only the (rare, human-initiated) hatch
  # path pays the one-time cost of an audit row. Gated on a resolvable
  # .context/state.json existing at all — otherwise a shell-profile-wide
  # IGRSOFT_TEST_GATE=off would materialize .context/logs/ in every unrelated
  # directory the user opens, the same no-side-effects-without-a-live-context
  # invariant the Task branch already enforces.
  if [ "${IGRSOFT_TEST_GATE:-}" = "off" ] && [ -f "$_ctx/state.json" ]; then
    _sentinel="$_ctx/logs/.gate-off-noted"
    if [ ! -f "$_sentinel" ]; then
      mkdir -p "$_ctx/logs" 2>/dev/null && : > "$_sentinel" 2>/dev/null
      write_audit_row "$_ctx" "test_gate_disabled" '{"vector":"IGRSOFT_TEST_GATE"}'
    fi
    return 0
  fi

  command -v jq >/dev/null 2>&1 || return 0

  _tool=$(printf '%s' "$_payload" | jq -r '.tool_name // empty' 2>/dev/null)
  [ -n "$_tool" ] || return 0  # unparseable payload or missing tool_name — allow

  case "$_tool" in
    Bash|Skill) ;;
    Task)
      # Task is OBSERVE-ONLY, never a deny: a delegation prompt that quotes
      # this very ban contains every runner name (including this worktask's
      # own DV/DR/SR/QA dispatch prompts), so a prose-matching deny would
      # refuse to dispatch the stages implementing the policy.
      #
      # Resolve the stage FIRST, before touching the filesystem at all. No
      # .context/ or no resolvable in-progress stage means this session has
      # no worktask in flight — the common case in a third-party repo where
      # the plugin is merely installed — so there must be zero side effects:
      # no directory creation, no log growth, in a repo unrelated to this
      # policy. Only a live, single-in-progress-stage session gets a
      # telemetry row, and only for an unambiguous runner token (see
      # first_runner_token below — word-boundary matched against a curated,
      # English-word-safe token list, not a bare substring scan).
      _stage=$(resolve_stage "$_ctx")
      if [ -n "$_stage" ]; then
        _subagent=$(printf '%s' "$_payload" | jq -r '.tool_input.subagent_type // "unknown"' 2>/dev/null)
        # Truncate to a short bounded length before it ever reaches the log —
        # this is untrusted payload data, and the audit row exists to record
        # a stable agent identifier, not to accept an arbitrarily long string.
        _subagent="${_subagent:0:64}"
        _prompt=$(printf '%s' "$_payload" | jq -r '.tool_input.prompt // ""' 2>/dev/null)
        _matched=$(first_runner_token "$_prompt")
        if [ -n "$_matched" ]; then
          write_audit_row "$_ctx" "test_delegation_observed" \
            "$(jq -cn --arg st "$_subagent" --arg tok "$_matched" '{subagent_type:$st, matched_token:$tok}')"
        fi
      fi
      return 0
      ;;
    *)
      # Any tool this hook doesn't otherwise recognize is out of scope,
      # except an MCP tool whose own name says "test" — the tool *name* is
      # the classifier there (see the mcp__*test* case below), so widening
      # the matcher to include it costs no parsing at all.
      case "$_tool" in
        mcp__*test*) ;;
        *) return 0 ;;
      esac
      ;;
  esac

  _stage=$(resolve_stage "$_ctx")
  [ -n "$_stage" ] || return 0  # no resolvable acting stage — allow

  case "$_tool" in
    mcp__*test*)
      # Classifying on tool *name* alone is deny-direction only: a
      # read-only tool like `mcp__*__list_tests` also matches and would be
      # denied at a banned stage even though it never executes anything.
      # Acceptable because the failure mode is "an extra deny", never a
      # missed one, and the alternative (parsing MCP tool semantics) isn't
      # worth the cost for what is already a narrow, rare tool surface.
      _class="scoped_test_run"
      _cmd_head="$_tool"
      ;;
    Bash)
      _cmd=$(printf '%s' "$_payload" | jq -r '.tool_input.command // empty' 2>/dev/null)
      [ -n "$_cmd" ] || return 0
      # Zero-fork prefilter (fast path): a case match on the raw string
      # before any classification work, so `git status`/`ls`/`cat` calls
      # never enter classify_cmd.
      case "$_cmd" in
        *bats*|*pytest*|*unittest*|*"swift test"*|*ctest*|*"cargo test"*|*"go test"*|*jest*|*vitest*|*playwright*|*rspec*|*"dotnet test"*|*gradle*|*xcodebuild*|*"pnpm test"*|*"npm test"*|*"yarn test"*|*"pnpm run test"*|*"npm run test"*|*"yarn run test"*|*run-tests*|*build-test*|*coverage*) ;;
        *) return 0 ;;
      esac
      _class=$(classify_cmd "$_cmd")
      # command_head is telemetry, not classification input, and it is
      # derived from the WHOLE command while classify_cmd works per segment
      # — a `;`/`&&`/`||`/`|`/newline-separated command can carry a secret
      # in an early segment while a LATER segment is what actually classifies
      # non-benign (e.g. `SECRET="a b"; pytest tests/`). Stripping VAR=value
      # from the whole-command head is not sufficient defense against that
      # shape. The channel is instead bounded structurally: _cmd_head may
      # only ever be a token this hook already recognizes as a runner name —
      # anything else (a secret fragment, a stray flag, a multi-KB blob) is
      # redacted. A runner name is never a secret, and this also caps the
      # logged value to a short known set regardless of input length.
      _stripped="$(strip_assignments "$(printf '%s' "$_cmd" | sed -E 's/^[[:space:]]+//')")"
      _cmd_head="${_stripped%% *}"
      _cmd_head="${_cmd_head##*/}"
      _cmd_head="$(redact_unless_known_head "$_cmd_head")"
      ;;
    Skill)
      _skill_cmd=$(printf '%s' "$_payload" | jq -r '.tool_input.command // .tool_input.skill // empty' 2>/dev/null)
      case "$_skill_cmd" in
        *build-test*--no-test*|*build-test*--count*|*build-test*--dry-run*) return 0 ;;
        *build-test*) _class="full_test_run" ;;
        *) return 0 ;;  # deterministic build-test rule only — never a prose scan
      esac
      # Same allow-list as the Bash branch (SR2-M1): this arm previously
      # logged the WHOLE skill command unfiltered, so a build-test invocation
      # carrying a secret-bearing flag (`--token sk-...`) would leak it —
      # the exact channel the Bash-side redaction exists to close, left open
      # here. `_cmd_head` must be bounded to a known token everywhere, not
      # just on one branch.
      _cmd_head="${_skill_cmd%% *}"
      _cmd_head="${_cmd_head##*/}"
      _cmd_head="$(redact_unless_known_head "$_cmd_head")"
      ;;
  esac

  [ -n "${_class:-}" ] || return 0  # classification indeterminate — allow
  case "$_class" in
    not_test|build_only) return 0 ;;
  esac

  # DV is allowed scoped test execution but denied a full-suite run — this
  # is the one mechanical check that actually enforces DV's authority limit
  # (everything else here is about who is denied outright). QA is exempt
  # from this branch by design: it is the pipeline's sole full-suite gate.
  if [ "$_stage" = "DV" ] || [ "$_stage" = "QA" ]; then
    if [ "$_stage" = "DV" ] && [ "$_class" = "full_test_run" ]; then
      : # fall through to deny
    else
      return 0  # DV-scoped or QA (either mode) — allow
    fi
  fi

  # Banned stage (or DV-full): DENY. The relief text is actionable BY AN
  # AGENT: requests_test_evidence / blocked-escalation are self-serviceable
  # from inside a stage's own artifact. IGRSOFT_TEST_GATE=off is NOT
  # agent-serviceable — the hook reads process env, not the command string,
  # so a retry with a command-string prefix denies identically — so the text
  # frames it explicitly as a human ask, not a retry an agent can perform.
  _reason="Stage '$_stage' has no test-execution authority (skills/shared/testing-strategy.md § Test-Execution Authority). DV may run scoped tests only; QA is the sole full-suite authority. To proceed: (1) record requests_test_evidence: <what and why> in this stage's artifact so QA executes it, or (2) return verdict: blocked with error_escalated_to: \"DV\" if it blocks this stage's completion. A human operator may disable this gate for a debugging session by restarting with IGRSOFT_TEST_GATE=off in the process environment — an agent cannot self-serve this by retrying the command with a prefix."
  _deny=$(jq -cn --arg reason "$_reason" '
    {hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}
  ') || return 0
  printf '%s\n' "$_deny"

  write_audit_row "$_ctx" "test_execution_blocked" \
    "$(jq -cn --arg st "$_stage" --arg tool "$_tool" --arg head "$_cmd_head" --arg class "$_class" \
      '{stage:$st, tool:$tool, command_head:$head, class:$class}')"
  return 0
}

# OBSERVE_TOKENS — the Task-branch telemetry set, deliberately narrower than
# RUNNERS: "go", "make", "python", "python3", "swift" are common English
# words / adjectives and would make first_runner_token fire on ordinary
# delegation prose ("go ahead", "make the change", "a swift fix"). Excluding
# them keeps the observe row's `matched_token` meaningful telemetry rather
# than near-constant noise; scoped/deny classification (which does need
# those heads) is unaffected — this set is Task-observation-only.
OBSERVE_TOKENS="bats pytest ctest cargo jest vitest playwright rspec gradle gradlew xcodebuild dotnet npm pnpm yarn npx uvx bunx"

# redact_unless_known_head <token> -> echoes the token unchanged if it is a
# member of RUNNERS/build-test/run-tests.sh/env, else echoes "redacted".
# command_head is telemetry, not classification input; the invariant this
# hook maintains is that it is ALWAYS one of those known tokens or the
# literal "redacted" — never an unbounded fragment of the original command —
# regardless of which tool branch (Bash or Skill) produced it. Shared so a
# future third branch can't reopen the same hole by skipping the allow-list.
redact_unless_known_head() {
  local _tok="$1"
  case " $RUNNERS build-test run-tests.sh env " in
    *" $_tok "*) printf '%s' "$_tok" ;;
    *) printf 'redacted' ;;
  esac
}

# first_runner_token <text> -> echoes the first OBSERVE_TOKENS token found in
# free text as its OWN word (word-boundary matched, not a bare substring
# scan — an unanchored scan would match "go" inside "algorithm" and fire on
# nearly every prompt). Used only for the Task branch's observe-only
# telemetry, never for a deny decision.
first_runner_token() {
  local _text="$1" _tok
  for _tok in $OBSERVE_TOKENS; do
    if printf '%s' "$_text" | grep -Eq "(^|[^[:alnum:]_])${_tok}([^[:alnum:]_]|\$)" 2>/dev/null; then
      printf '%s' "$_tok"
      return
    fi
  done
  printf ''
}

# write_audit_row <ctx> <action> <metadata json> — the deny JSON is always
# printed BEFORE this is called, so a logging failure (unwritable dir, no
# `date`, disk full) can never swallow a legitimate deny. Never logs the
# full command — command_head only, since the full command can carry a
# secret token or a path that shouldn't land in a committed log file.
write_audit_row() {
  local _ctx="$1" _action="$2" _meta="$3" _log_dir _log_file _ts _row
  _log_dir="$_ctx/logs"
  _log_file="$_log_dir/audit.jsonl"
  mkdir -p "$_log_dir" 2>/dev/null || return 0
  # A symlinked audit.jsonl would turn this append into a write primitive
  # against an arbitrary target file (content is jq-escaped JSON, so no code
  # execution results, but it is still an unintended write). Refuse to
  # append through a symlink — this is a pre-existing pattern shared with
  # other hooks in this plugin, closed here rather than left as a residual.
  [ ! -L "$_log_file" ] || return 0
  _ts=$(date -u +%FT%TZ 2>/dev/null) || _ts="unknown"
  _row=$(jq -cn --arg ts "$_ts" --arg action "$_action" --argjson meta "$_meta" '
    {ts:$ts, actor:"hook:test-execution-gate", action:$action, result:"ok", metadata:$meta}
  ' 2>/dev/null) || return 0
  printf '%s\n' "$_row" >> "$_log_file" 2>/dev/null || return 0
}

# ---------------------------------------------------------------------------
# --self-test
# ---------------------------------------------------------------------------
if [ "$SELF_TEST" -eq 1 ]; then
  _fail=0
  command -v jq >/dev/null 2>&1 || { echo "test-execution-gate: jq not found — self-test skipped"; exit 0; }

  _tmp=$(mktemp -d)
  trap 'rm -rf "$_tmp"' EXIT

  # DR + scoped bats -> deny
  _ctx1="$_tmp/dr/.context"; mkdir -p "$_ctx1"
  printf '{"stages":{"DR":{"status":"in_progress"}}}' > "$_ctx1/state.json"
  _p1='{"tool_name":"Bash","tool_input":{"command":"tests/vendor/bats-core/bin/bats tests/shell/foo.bats"}}'
  _o1=$(run_gate "$_p1" "$_ctx1")
  printf '%s' "$_o1" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1 \
    || { echo "test-execution-gate: self-test FAIL (DR scoped deny)"; _fail=1; }

  # DV + full run-tests.sh -> deny (DV holds scoped authority only)
  _ctx2="$_tmp/dv/.context"; mkdir -p "$_ctx2"
  printf '{"stages":{"DV":{"status":"in_progress"}}}' > "$_ctx2/state.json"
  _p2='{"tool_name":"Bash","tool_input":{"command":"./run-tests.sh"}}'
  _o2=$(run_gate "$_p2" "$_ctx2")
  printf '%s' "$_o2" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1 \
    || { echo "test-execution-gate: self-test FAIL (DV full deny)"; _fail=1; }

  # QA + full run-tests.sh -> allow
  _ctx3="$_tmp/qa/.context"; mkdir -p "$_ctx3"
  printf '{"stages":{"QA":{"status":"in_progress"}}}' > "$_ctx3/state.json"
  _p3='{"tool_name":"Bash","tool_input":{"command":"./run-tests.sh"}}'
  _o3=$(run_gate "$_p3" "$_ctx3")
  [ -z "$_o3" ] || { echo "test-execution-gate: self-test FAIL (QA full allow)"; _fail=1; }

  # No state.json -> allow, no row (nothing resolves, so nothing to enforce)
  _ctx4="$_tmp/none/.context"; mkdir -p "$_ctx4"
  _o4=$(run_gate '{"tool_name":"Bash","tool_input":{"command":"bats foo.bats"}}' "$_ctx4")
  [ -z "$_o4" ] || { echo "test-execution-gate: self-test FAIL (no state.json)"; _fail=1; }
  [ ! -f "$_ctx4/logs/audit.jsonl" ] || { echo "test-execution-gate: self-test FAIL (no state.json wrote a row)"; _fail=1; }

  # Task carrying ban text -> allow, observe-only row, never deny
  # (a prose-matching deny here would refuse to dispatch this very policy)
  _ctx5="$_tmp/task/.context"; mkdir -p "$_ctx5"
  printf '{"stages":{"DR":{"status":"in_progress"}}}' > "$_ctx5/state.json"
  _p5='{"tool_name":"Task","tool_input":{"subagent_type":"igrsoft:developer","prompt":"Never run bats or pytest outside DV/QA"}}'
  _o5=$(run_gate "$_p5" "$_ctx5")
  [ -z "$_o5" ] || { echo "test-execution-gate: self-test FAIL (Task must never deny)"; _fail=1; }
  tail -n 1 "$_ctx5/logs/audit.jsonl" 2>/dev/null | jq -e '.action == "test_delegation_observed"' >/dev/null 2>&1 \
    || { echo "test-execution-gate: self-test FAIL (Task observe row)"; _fail=1; }

  # Regression: Task dispatch with NO .context/ at all -> zero side effects
  # (no worktask in flight means nothing should be created or logged).
  _ctx5b="$_tmp/task-no-ctx/.context"   # deliberately NOT created
  _o5b=$(run_gate '{"tool_name":"Task","tool_input":{"subagent_type":"igrsoft:developer","prompt":"go ahead and make the change"}}' "$_ctx5b")
  [ -z "$_o5b" ] || { echo "test-execution-gate: self-test FAIL (Task no-ctx must be silent)"; _fail=1; }
  [ ! -d "$_ctx5b" ] || { echo "test-execution-gate: self-test FAIL (Task no-ctx created .context/)"; _fail=1; }

  # command_head only, never the full command, in a deny's audit row.
  _ctx6="$_tmp/redact/.context"; mkdir -p "$_ctx6"
  printf '{"stages":{"SR":{"status":"in_progress"}}}' > "$_ctx6/state.json"
  _p6='{"tool_name":"Bash","tool_input":{"command":"bats /secret/path/leak.bats -f token-abc123"}}'
  run_gate "$_p6" "$_ctx6" >/dev/null
  tail -n 1 "$_ctx6/logs/audit.jsonl" | jq -e '.metadata.command_head == "bats" and (.metadata | has("command") | not)' >/dev/null 2>&1 \
    || { echo "test-execution-gate: self-test FAIL (command_head redaction)"; _fail=1; }

  # Regression: a leading secret env assignment must not reach command_head.
  _ctx6b="$_tmp/redact-secret/.context"; mkdir -p "$_ctx6b"
  printf '{"stages":{"SR":{"status":"in_progress"}}}' > "$_ctx6b/state.json"
  _p6b='{"tool_name":"Bash","tool_input":{"command":"API_KEY=sk-test-xyz pytest tests/"}}'
  run_gate "$_p6b" "$_ctx6b" >/dev/null
  tail -n 1 "$_ctx6b/logs/audit.jsonl" | jq -e '.metadata.command_head == "pytest" and (.metadata.command_head | test("sk-test-xyz|API_KEY") | not)' >/dev/null 2>&1 \
    || { echo "test-execution-gate: self-test FAIL (secret leaked into command_head)"; _fail=1; }

  # IGRSOFT_TEST_GATE=off -> allow even for a banned stage
  _ctx7="$_tmp/off/.context"; mkdir -p "$_ctx7"
  printf '{"stages":{"DR":{"status":"in_progress"}}}' > "$_ctx7/state.json"
  _o7=$(IGRSOFT_TEST_GATE=off run_gate '{"tool_name":"Bash","tool_input":{"command":"bats foo.bats"}}' "$_ctx7")
  [ -z "$_o7" ] || { echo "test-execution-gate: self-test FAIL (escape hatch)"; _fail=1; }

  # DR + build-test --no-test -> allow (build-only stays permitted everywhere)
  _ctx8="$_tmp/buildonly/.context"; mkdir -p "$_ctx8"
  printf '{"stages":{"DR":{"status":"in_progress"}}}' > "$_ctx8/state.json"
  _o8=$(run_gate '{"tool_name":"Bash","tool_input":{"command":"/system-developer:build-test --no-test"}}' "$_ctx8")
  [ -z "$_o8" ] || { echo "test-execution-gate: self-test FAIL (build-test --no-test)"; _fail=1; }

  # Regression: pure build/non-test commands on multi-purpose runners must
  # ALLOW at a banned stage — build-only stays permitted everywhere.
  _ctx9="$_tmp/gradle-build/.context"; mkdir -p "$_ctx9"
  printf '{"stages":{"DR":{"status":"in_progress"}}}' > "$_ctx9/state.json"
  _o9=$(run_gate '{"tool_name":"Bash","tool_input":{"command":"./gradlew assembleDebug"}}' "$_ctx9")
  [ -z "$_o9" ] || { echo "test-execution-gate: self-test FAIL (gradlew assembleDebug must allow)"; _fail=1; }
  _ctx9b="$_tmp/py-coverage/.context"; mkdir -p "$_ctx9b"
  printf '{"stages":{"SR":{"status":"in_progress"}}}' > "$_ctx9b/state.json"
  _o9b=$(run_gate '{"tool_name":"Bash","tool_input":{"command":"python3 tools/coverage_report.py"}}' "$_ctx9b")
  [ -z "$_o9b" ] || { echo "test-execution-gate: self-test FAIL (coverage_report.py must allow)"; _fail=1; }

  # Regression: `-c` is a config flag for swift/pytest, not a build-only
  # signal — a real test run carrying `-c` must still classify (and deny) as
  # a test, not slip through as build-only.
  _ctx10="$_tmp/dashc-dr/.context"; mkdir -p "$_ctx10"
  printf '{"stages":{"DR":{"status":"in_progress"}}}' > "$_ctx10/state.json"
  _o10=$(run_gate '{"tool_name":"Bash","tool_input":{"command":"swift test -c release"}}' "$_ctx10")
  printf '%s' "$_o10" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1 \
    || { echo "test-execution-gate: self-test FAIL (swift test -c release must still deny at DR)"; _fail=1; }
  _ctx10b="$_tmp/dashc-dv/.context"; mkdir -p "$_ctx10b"
  printf '{"stages":{"DV":{"status":"in_progress"}}}' > "$_ctx10b/state.json"
  _o10b=$(run_gate '{"tool_name":"Bash","tool_input":{"command":"swift test -c release"}}' "$_ctx10b")
  printf '%s' "$_o10b" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1 \
    || { echo "test-execution-gate: self-test FAIL (swift test -c release must deny DV-full)"; _fail=1; }

  # Exit code always 0, even on a deny.
  set +e
  ( run_gate "$_p1" "$_ctx1" >/dev/null 2>&1 )
  _ec=$?
  set +e
  [ "$_ec" -eq 0 ] || { echo "test-execution-gate: self-test FAIL (non-zero exit on deny path)"; _fail=1; }

  if [ "$_fail" -ne 0 ]; then
    echo "test-execution-gate: self-test FAIL"
    exit 1
  fi
  echo "test-execution-gate: self-test OK"
  exit 0
fi

# ---------------------------------------------------------------------------
# Live invocation. Builtin `read -r -d ''` (not $(cat), which forks) per the
# zero-fork fast path.
# ---------------------------------------------------------------------------
IFS= read -r -d '' PAYLOAD || true
[ -n "${PAYLOAD:-}" ] || exit 0  # empty/unreadable stdin — nothing to gate

CTX="${CLAUDE_PROJECT_DIR:-.}/.context"
run_gate "$PAYLOAD" "$CTX"
exit 0
