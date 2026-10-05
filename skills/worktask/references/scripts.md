# Worktask scripts — CLI reference

CLI, stdout and exit contracts of the helpers the orchestrator loop calls. Read when interpreting a helper's output or exit code. A bare `§ Step …` points into `skills/worktask/SKILL.md`; the `blocked_on` arm table stays there (`§ blocked-on-lib.sh — the arm table`).

## state-patch.sh — exit codes

Exits **3** (Layer-1 self-patch signature) when unresolved AND `--prev` given AND `--via` absent,
and on a missing or unknown `handoff.verdict` on any path (`ERROR: verdict refused`); otherwise
exits 0. `--allow-missing-artifact` silences that but writes **nothing**. Contract:
`references/handoff-protocol.md#layer-1-fallback`.

## permission-park.sh — CLI

```
permission-park.sh classify [--payload <json|text>] [--tool <t>] [--command <c>]   # stdin when --payload absent
permission-park.sh park     --task-id <ID> --detail <json> [--state <state.json>]
permission-park.sh batch    [--tasks <ID,ID...>] [--boundary <ID>] [--workspace-json <path>] [--state <state.json>]
permission-park.sh resume   --task-id <ID> --answer grant|manual [--state <state.json>]
permission-park.sh --self-test
```

Exit `0` success (for classify, the payload is a permission denial); `1` classify found no denial
or no recoverable tool, or park/resume had a ledger write refused or a task not parked; `2` usage
error, missing or unparseable ledger, or broken install. On the text path `--tool`/`--command` are
optional: classify recovers both from the last `Tool(...)` line at or before the classifier-denial
line. It grants nothing, writes no Claude Code configuration, and emits no retry decision.

## permission-park.sh — stdout

| Subcommand | stdout (one JSON line) |
|---|---|
| `classify` | `{"tool","command","classifier_reason","allow_rule"}` |
| `park` | `{"blocked_on":{"kind":"permission","detail":{…4 keys},"resume_with":"decision_ref"},"dedupe_key":"<16 hex>","truncated":true\|false,"audit_row_written":true\|false}` |
| `batch` | `{"mode":"ask","needs":[{"task_id","tool","command","classifier_reason","allow_rule","truncated","cwd"}…],"payloads":[{"questions":[…≤4]}]}`; megatask per-issue run: `{"mode":"megatask_park","needs":[…],"payloads":[],"park":{"boundary","execution","escalated":[{"tool","command_head","truncated"}],"workspace_written","workspace_reason","audit_row_written"}}`, `"park":null` when nothing is parked |
| `resume` | `{"resume_block":{"task_id","tool","command","answer","truncated","do_not_rerun":true,"decision_ref","instruction"},"cleared":true,"audit_row_written":true\|false}` |

## permission-park.sh — the resume audit row

`resume` appends one `permission_resumed` row per successful resume and none on a refusal:
`actor: "orchestrator"`, `subject: <task_id>`, `result: "ok"`,
`metadata.{tool, dedupe_key, command_head, truncated, answer, decision_ref}`. `decision_ref` is
`permission_resumed:<task_id>:<dedupe_key>:<n>`, where `n` is 1 plus the earlier rows with that
subject and key. It is the record `blocked_on.resume_with: decision_ref` points at, and it comes
back as `resume_block.decision_ref` (§ Step 7a). The row never holds the command:
`command_head` is the redacted head every committed row carries (at most 4 tokens, masked,
path-scrubbed, at most 120 characters), `truncated` marks a head showing less than the whole
command, and an unavailable scrub gives `[redacted]` with `redaction: "scrub_unavailable"`. `resume_block.truncated` is a different flag:
the stored command was cut at 512 characters.

## land-artifacts.sh — CLI

```
land-artifacts.sh --producer <ID> [--consumer <ID>] [--state <p>] [--orch-root <p>] [--dry-run]
land-artifacts.sh --consumer <ID> [--state <p>] [--orch-root <p>] [--dry-run]
land-artifacts.sh --list-landed --tree <path> [--strict] [--state <p>]
land-artifacts.sh --check-path <path>
land-artifacts.sh --self-test | -h | --help
```

Any call with `--producer` is the boundary pass (§ Step 6.5d); `--consumer` alone is the dispatch
gate (§ Step 4.8 — land consumed artifacts). `--dry-run` checks every path and writes nothing.
`--list-landed --tree <path>` prints the landed set scoped to that tree
(`skills/shared/state-ledger.md § The landed set`) one path per line; empty output is exit 0, and
no `--tree` is exit 2.

### land-artifacts.sh — the fail-closed modes

`--strict` prints the same set, but exits 1 with empty stdout and one stderr line that never echoes
the entry when any raw `landed_paths` entry scoped to that tree fails the path ladder or the
alphabet. This script never writes such an entry, so one means a hand-edited ledger.
`--check-path <path>` runs the path ladder alone, with no ledger: silent exit 0 when safe, exit 1
printing `reason=<token>` when refused. The orchestrator's grant admits a call only when its first
argument is `--producer`, `--consumer` or `--list-landed`, so every call leads with that argument.
Scripts make the other calls: `fn-stream-merge.sh` and `blocked-on-dispatch.sh` pass `--strict`, and
only the router calls `--check-path`.

## land-artifacts.sh — exits

Exits are 0, 1 or 2 only: an interrupting signal (INT, TERM, HUP) or an unexpected command failure
rolls back what the run wrote and exits 2, so 1 is never a stray status. Exit `0`: landed, same
tree, already present, a gate no-op, nothing selected, or a consumer a boundary pass skips — a
`blocked` one silently, any other non-`pending` one with one `warn` `contract_landed` row
(`consumer_not_pending`). `1`: a consumer failed, and is now `blocked` with
`metadata.landing_error {reason, path, producer}` and one fail `contract_landed` row; the gate
refuses a consumer that is no longer `pending` this way (`consumer_already_dispatched`). Exit 1 is
also a refused `--check-path` or an unsafe entry under `--strict`; neither writes. `2`: usage, a
malformed id, a bad ledger, an invalid tree, a missing tool, a failed ledger write, or that signal
or failure. Refusal reasons and the audit rows:
`references/handoff-protocol.md § Landing consumed artifacts`.

## blocked-on-dispatch.sh and blocked-on-lib.sh

| Script | One-line invocation | Purpose |
|--------|---------------------|---------|
| `scripts/blocked-on-dispatch.sh` | `route\|batch\|resume` | Routes a typed `blocked_on` return to its arm or its `user_action` fallback, batches those needs and builds the resume (§ Step 6.5a3, § Step 7a). Self-test: `--self-test`. |
| `scripts/blocked-on-lib.sh` | sourced, never run | The one definition of the `blocked_on` enums, the arm table, the alias normalize step and `validate`. `handoff-harness.sh` and the router both source it. |

## blocked-on-dispatch.sh — CLI

```
blocked-on-dispatch.sh route  --task-id <ID> --payload <handoff json> [--state <state.json>]
blocked-on-dispatch.sh batch  [--tasks <ID,ID...>] [--boundary <ID>] [--workspace-json <path>] [--state <state.json>]
blocked-on-dispatch.sh resume --task-id <ID> --leg <leg> [--decision-ref <ud-id>] [--state <state.json>]
blocked-on-dispatch.sh --self-test
```

Exit `0` success. `1`: for `route`, an invalid need, with one `fail:` line on stderr naming the
unknown kind or `resume_with`, the missing `detail` or key, or the wrong pairing, and nothing
written; for `resume`, a task not parked on a non-permission `blocked_on`, a `--leg` that is not
its arm's closing leg, a `user_decision` with no verified ledger row to resume with, or `--leg landed`
on an artifact `path` that the path ladder refuses or that has not landed. `2`: usage error, missing
or unparseable ledger, broken install, or a ledger write refused. Requires jq; bash 3.2+.

## blocked-on-dispatch.sh — route

Normalizes and validates `--payload` through the lib, then acts on the arm the lib's table names:

- `permission`: writes nothing; § Step 6.5a4 parks it.
- `user_action`, or a kind whose owner has not landed — none today: `state-patch.sh --task-meta`
  with the stage's original `blocked_on` (under `--log /dev/null`), then `--task-status blocked`,
  then one `requested` row.
- `user_decision`: the same park, then one `asked` row with no fallback fields. It is queued for
  the next boundary's question, as `requested` is.
- `host_environment`: `autonomy-preflight.sh --auto plan --platform <metadata.preflight.platforms>`
  in check mode, `--harness` added when `check` is `git-reset-hard`, then one `probed` row. Only a
  `checks[]` entry with that `id` reading `pass` clears it: `--claim`, `blocked_on` set to `null`,
  and `decision_ref` on the row. A fail, a skip or an absent id parks it as a `user_action`.

### blocked-on-dispatch.sh — route, the artifact arm

- `artifact`: parks first. When `detail.producer_task` is a task id, `detail.path` passes
  `land-artifacts.sh --check-path`, and the landed set of the task's `metadata.workspace_path` tree
  (`--list-landed --tree <workspace_path> --strict`) holds `detail.path` exactly, it claims, clears
  `blocked_on`, writes one ok `landed` row with `decision_ref` `blocked_on:<ID>:artifact:<n>`, and
  prints `resume_block` with `artifact_path` set to `detail.path`. No `workspace_path`, a failed
  read, a refused path or a non-member leaves it parked as a `user_action`: a `requested` row with `fallback_from: artifact`
  and no `owner_issue`. `BLOCKED_ON_LAND` swaps the landing script, a test seam.

### blocked-on-dispatch.sh — route, the correction arm — invocation

`correction` guards first: `detail.target_task` exists, not source, is `completed`; miss exits 1 with `fail:` line and unchanged ledger (§ Step 6.5a3 re-dispatches). Then `state-patch.sh --task-reopen <target> --from <source> --finding-file -` with rework text on stdin, source park, one `opened` row (`result: blocked`). Re-opening before parking deliberate: op can refuse under its lock; park ahead would leave source blocked with no row. Op input-bounds refusal (empty finding, byte cap, control byte) exits 1 with `fail:`, not escalation.

### blocked-on-dispatch.sh — route, the correction arm — re-route idempotency

Re-route of same still-open need detected by `opened` leg, not status guard (now reads `pending` after first route). Router re-parks source, writes no second `opened`, calls no op, so `fix_round` moves once per correction. Rework text on stdin: finding byte-for-byte, `evidence_ref:`, `source_task:` lines; lands as `gate_blockers[0]` (`references/handoff-protocol.md § tasks — re-open and settle — guards and invocation`).

### blocked-on-dispatch.sh — route stdout

One JSON line: `{"task_id","kind","arm","leg","source","parked","audit_row_written"}`, plus
`fallback_from` and `owner_issue` on a fallback, and `decision_ref` and `resume_block` on a passing
re-probe or an artifact already landed. `leg` is `null` for `permission`. `source` names the key the need came from,
always `blocked_on`.

## blocked-on-dispatch.sh — batch

Selects every `blocked` task whose `metadata.blocked_on.kind` is not `permission`. Interactive:
`{"mode":"ask","needs":[{"task_id","kind","arm":"user_action","resume_leg","request","command",
"verify","truncated","cwd"}…],"payloads":[{"questions":[…≤4]}]}`, a fallback need adding
`fallback_from` and `owner_issue`. A fallback's `request` is its kind's lead line and its `command`
is `""`. Each question has the task id as `header`, the lead line, then every `detail` key as
`key: value` data and `cwd:` from the ledger's `workspace_path`, inside a fence one backtick longer
than its longest run. Options: "done" and "stop here".

### blocked-on-dispatch.sh — batch, a user decision

`user_decision` needs sharing one `(question, options, item)` become one question:

- `header` is the lowest task id, and `multiSelect` is false.
- `question` is `detail.question` verbatim and unfenced, because the hook matches its exact bytes.
- Each option is `{label: <option>, description: "Recommended" | "Offered by <header>"}`.
- Two questions with the same text never share a call, since the answers are keyed by that text.

Each need is `{task_id, kind, arm: "user_decision", resume_leg: "resumed", header}`. The megatask
park adds `{kind: "user_decision"}` to `escalated[]`.

### blocked-on-dispatch.sh — batch, the `!` line and the megatask park

A `! <command>` line, in its own fence, appears only on a native `user_action` whose `command` is
non-empty and not cut at 512 characters. Under a megatask per-issue run it asks nothing and prints
`permission-park.sh batch`'s `megatask_park` shape: the same `workspace.json` write and symlink
refusal, and one `escalation_parked` row with `metadata.kind: "user_action"` whose `escalated[]`
entries are `{kind, command_head, truncated}`.

## blocked-on-dispatch.sh — resume — general flow

`--claim`, `blocked_on` → `null`, one closing-leg row with `decision_ref` (`references/handoff-protocol.md § Schema — blocked_on, decision_ref on the other arms`). Prints `{"resume_block":{"task_id","kind","arm","leg","decision_ref","resume_with","do_not_rerun":true,"instruction"},"cleared":true,"audit_row_written"}`, with `artifact_path` in `resume_block` when the kind resumes with one. `instruction` restates need (detail fenced) and forbids re-running completed steps.

### blocked-on-dispatch.sh — resume — artifact leg

`--leg landed` resumes `artifact` need: re-checks `path` safety and landed-set membership, exits 1 if not landed, otherwise claims, clears, writes ok `landed` row with `decision_ref`, prints same stdout. `--leg verified` (user's "done") still resumes through fallback.

### blocked-on-dispatch.sh — resume — correction leg

`--leg closed` resumes `correction` need: claim, clear, ok `closed` row with `decision_ref`, `artifact_path` = target's `artifact` or `metadata.artifact` (recorded-else-planned). Checks target status **not at all** — orchestrator calls at target's completion boundary (§ Step 6.5d). `--leg verified` (user's "done") resumes through fallback with same path. Settling `stale` dependents not part of either resume; keys on target, not parked need; runs own op at boundary.

### blocked-on-dispatch.sh — resume, a user decision

`resume` first finds the ledger row: `--decision-ref <ud-id>` names it, and without the flag it is
the newest valid row covering the task that no earlier `blocked_on` row for the task carries. A
refused or missing row exits 1 with nothing written. Otherwise the `resumed` row and
`resume_block.decision_ref` carry that `ud-` id. `instruction` names the verify command,
`state-patch.sh --verify-decision`, and carries no answer text
(`hooks/references/user-decision-ledger.md`).

### blocked-on-dispatch.sh — the lead lines

Fixed strings, with `<ID>` the only substitution:

- `user_decision`: "<ID> needs your decision. Answer with one of the options below, or your own."
- `user_action`: "<ID> needs you to do the request below, then answer done."
- `peer_session`: "<ID> needs an answer from the session below. Ask it, then answer with its reply."
- `artifact`: "<ID> waits on the file below from another task. Answer done once it exists."
- `correction`: "<ID> found the defect below in another task's work. Answer done once it is fixed."
- `host_environment`: "<ID> is blocked by the host check below, which still fails. Answer done
  once it passes."

### blocked-on-dispatch.sh — the blocked_on row

`actor: "orchestrator"`, `action: "blocked_on"`, `subject` and `task_id` both the task id. `result`
is `blocked` on a leg that leaves the task parked and `ok` on the closing leg. `metadata` is
`{kind, arm, leg}` plus `fallback_from` and `owner_issue` on a fallback, `command_head` and
`truncated` on a need with a command, and `decision_ref` on the closing leg. The redaction rule and
the head ladder: `skills/agent-coordination/SKILL.md § Writers — blocked_on rows`.

## blocked-on-lib.sh — the sourced interface

- `BLOCKED_ON_KINDS`, `BLOCKED_ON_RESUME_WITH`: both enums, in registry order.
- `blocked_on_arm <kind>`: prints the kind's row as `required|optional|resume_with|legs|closing_leg|owner_issue|landed`,
  comma-separated within a field. Exit 1 on an unknown kind.
- `blocked_on_normalize <handoff json>`: prints `{"blocked_on":{…},"source":"blocked_on"}`. Exit 1
  when `blocked_on` is absent; no other handoff key is read as a need.
- `blocked_on_validate <blocked_on json>`: kind and `resume_with` in their enums and `detail` a
  non-empty object; exit 1 with one `fail:` line. The harness stops here.
- `blocked_on_validate_arm <blocked_on json>`: adds the arm's required keys and its `resume_with`,
  and on `user_decision` the question, option, `recommended` and `item` bounds.

## mailbox.sh, mailbox-reply.sh and mailbox-lib.sh

| Script | One-line invocation | Purpose |
|--------|---------------------|---------|
| `scripts/mailbox.sh` | `show\|leg\|comment\|ingest-comments\|scan\|sweep\|wait` | The orchestrator side of the durable ask: the message transport's legs, the comment transport, reply ingestion, and the run's own scan and deadline sweep (§ Step 6.5a3, § Step 7a). |
| `scripts/mailbox-reply.sh` | `--ask-id … --answer-file …` | The only writer of `mailbox/replies/<ask_id>.json`. Self-test: `--self-test`. |
| `scripts/mailbox-lib.sh` | sourced, never run | The ask_id grammar, the mailbox root and its mode checks, the no-clobber write, the sha256 input, reply verification and the leg metadata. The router and both CLIs source it. |

### mailbox.sh — CLI

```
mailbox.sh show    --ask-id <id>
mailbox.sh leg     --task-id <ID> --ask-id <id> --leg sent|delivered --transport message
                   [--result ok|queued|refused|dropped|oversized|burst_limited]
mailbox.sh comment --task-id <ID> [--render-only]
mailbox.sh ingest-comments | scan | sweep | wait [--max-seconds N]      # all take [--state <state.json>]
```

Exit `0` ok; `1` refused — not an open ask, an invalid leg, or a bad `ask_id`; `2` usage error,
missing or unparseable ledger, or a broken install. Requires jq; bash 3.2+.

### mailbox.sh — stdout

| Subcommand | stdout (one JSON line) |
|---|---|
| `show` | the request JSON verbatim, for a same-repo peer reading `mailbox ask <ask_id>` |
| `leg` | `{"written"}` — `false` when that `(task, ask_id, leg)` was already recorded |
| `comment` | `{"posted","result"}`, result `posted\|post_failed\|opted_out\|unavailable\|scrub_failed`; `{"body"}` under `--render-only`, which posts nothing and writes no leg |
| `ingest-comments` | `{"ingested","ignored"}` |
| `scan` | `{"replied":[{task_id,ask_id}],"open":[{task_id,ask_id,deadline}]}` |
| `sweep` | `{"expired":[{task_id,ask_id,routed}]}` |
| `wait` | `{"reason":"reply\|deadline\|timeout\|none"}` |

### mailbox.sh — what scan, sweep and wait cover

`scan`, `sweep` and `wait` iterate **this run's ledger**, never the mailbox directory: the box is
shared across worktrees, and no run relays or expires another run's ask. `wait` polls every
`MAILBOX_POLL_SECONDS` (15), runs `ingest-comments` at most once a minute while a posted ask is
open, and stops at the first verified reply, at `min(deadline)+5`, or at `--max-seconds` (3600).

### mailbox-reply.sh — CLI

```
mailbox-reply.sh --ask-id <id> --answer-file <path|-> --kind peer|user --session <s> [--mailbox-dir <dir>]
mailbox-reply.sh --self-test
```

Prints `{"ask_id","reply_ref","sha256"}`. Exit `0` written; `1` refused, with one
`fail: <reason>: <detail>` line on stderr and nothing written, reason one of `invalid_ask_id`,
`bad_session`, `too_long`, `unknown_ask`, `bad_request`, `late`, `schema_invalid`, `duplicate`;
`2` usage error, mailbox unavailable, or no sha256 tool. The answer arrives only through
`--answer-file` (`-` for stdin), so untrusted text never reaches an argv (§ Step 7a — ingestReply).
