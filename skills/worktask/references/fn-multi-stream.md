# FN multi-stream arm

Read by `agents/project-manager.md § FN multi-stream arm`. Runs only when the ledger holds more
than one non-skipped DV task (`skills/worktask/references/handoff-protocol.md § Iterating the DV
tasks`). With one DV task, skip this file: the single-tree commit and push are unchanged.

Start with `bash ${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/fn-stream-merge.sh plan`. `arm=single reason=<token>`
(every DV task shares one tree) → leave this file; the single-tree path applies. `arm=multi
streams=<n>` is followed by one `<task><TAB><stream><TAB><tree>` line per stream: run § Per stream — scope and staging
for each, in that order, then § Merge, battery, push.

## Untracked files — on the multi-stream arm

The tree being checked is the `<tree>` on that stream's `plan` line: list with
`git -C <tree> status --porcelain --untracked-files=all` and pass `--arg root "<tree>"` to the
landed-set expression in `agents/project-manager.md § Untracked files and the landed set`. Each
stream subtracts its own tree's set, never the union over every tree.
`fn-stream-merge.sh commit` and `merge` read that same set with
`land-artifacts.sh --list-landed --tree <tree> --strict`, and `commit`'s `untracked=<n>` leaves out
the tree's untracked landed paths.

## Per stream — scope and staging

1. Run `agents/project-manager.md § Pre-commit scope check` in `<tree>`
   (`git -C <tree> status --porcelain`) against that tree's landed set (§ Untracked files — on the
   multi-stream arm).
2. Stage the stream's new files: `git -C <tree> add -- <path>...` for every `??` path its DV artifact
   lists as changed, never a path in that tree's landed set. `commit` stages tracked edits only
   (`add -u`), so a new file left unstaged never ships.

## Per stream — commit and facts

3. `Write` the message per `skills/shared/git-conventions.md` to `.context/logs/fn-commit-<task>.txt`,
   then `bash ${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/fn-stream-merge.sh commit --task <task> --message-file .context/logs/fn-commit-<task>.txt`.
4. Pass the JSON after `facts=` on the second printed line to
   `bash ${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/state-patch.sh --facts '<that JSON>'`. Skipping it makes `merge`
   block with `stream_branch_missing`.

If `untracked=<n>` above 0 on the result line: stage any of those paths the DV artifact lists, then re-run `commit`.

## Merge, battery, push

1. `bash ${CLAUDE_PLUGIN_ROOT}/skills/worktask/scripts/fn-stream-merge.sh merge` in FN's own tree: it cuts `facts.branch`
   from the base unless it exists, then merges each stream branch `--no-ff`, in task-id order.
2. `agents/project-manager.md` § Pre-`gh pr create` validator battery; `continuity` checks every
   stream (`agents/project-manager.md § Branch checks`).
3. The existing non-force push, `git push -u origin HEAD:refs/heads/<facts.branch>`
   (`agents/project-manager.md § Final FN steps`), then the PR.

## Arm exits

| Exit | Printed | FN does |
|---|---|---|
| 0 | result lines | continue |
| 1 | `blocked reason=<token> task=<ID\|-> stream=<s\|->` | `handoff.verdict: blocked`; copy the line verbatim to `.context/errors/project-manager.md` and name the reason and stream in `complete-summary-N.md`; no push, no `gh pr create` |
| 1 | `blocked reason=stream_is_combined task=<ID> stream=<s>` | a stream's branch is `facts.branch` (`commit`: the stream tree's current branch; `merge`: a `facts.stream_branches` value); nothing was written; `handoff.verdict: blocked` naming that stream, as above |
| 2 | `fn-stream-merge: <message>` on stderr, nothing on stdout | FN's own call is malformed: fix it and re-run |
| 3 | stderr | ledger unreadable or install broken: handle as exit 1 |
| 4 | `escalate reason=merge_abort_failed task=- stream=<s>` | the tree is left mid-merge: `handoff.verdict: escalate`, the line to the errors file, and stop without touching that tree |

### Arm exits — the landed set

Both reasons are exit 1 `blocked` lines, handled as the first exit-1 row above.

| Reason | Cause | Clearing it |
|---|---|---|
| `landed_path_unsafe` | a `landed_paths` entry scoped to that stream's tree fails the path allow-list; nothing was staged or merged | a human inspects that tree's `landed_paths`. `land-artifacts.sh` never writes such an entry, so never edit it away to clear the block |
| `landed_set_unreadable` | reading that tree's landed set failed, so the arm failed closed | § Clearing a block: fix the failed read, then re-run the same step |

## Clearing a block

`commit` and `merge` are idempotent: clear a block by fixing its named cause and re-running the
same step. A `merge_conflict` block was already aborted, so no ref moved. A re-run never clears
`stream_is_combined`: that stream's work sits on the PR branch itself, where the foreign-commit
check cannot tell it apart. Giving it its own branch is a human's call.

## Forbidden on this arm

- DO NOT force-push (`--force`, `--force-with-lease`, a `+` refspec), `git reset`, `git rebase`,
  `git commit --amend`, or delete a branch (`git branch -d`/`-D`, `git push --delete`) — not to
  clear a block, not to redo a merge.

`Bash(git:*)` grants every one of these and no hook stops them, while each stream branch may hold
the only copy of a DV task's commits.

| Excuse | Reality |
|--------|---------|
| "The merge conflicted; reset and merge again" | The arm already ran `merge --abort` and moved no ref. Return blocked naming the stream; its DV task resolves the conflict. |
| "The combined branch has a stray commit; delete it and recut" | `combined_foreign_commits` means work nobody in this run wrote is on it. Return blocked; a human decides. |
