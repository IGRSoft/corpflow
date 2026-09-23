---
name: appstore
description: 'Store publishing front door — listing metadata, screenshots, or in-app purchases; delegates to the platform plugin''s release engineer (Apple App Store, Google Play).'
argument-hint: '--task <listing|screenshots|iap> [--platform apple|android] [--lang en|ua] [--path <dir>] [--dry-run]'
allowed-tools: Read, Glob, Grep, Task(corpflow:release-engineer)
version: 0.1.0
related:
  - skills/shared/routing-matrix.md
  - skills/shared/platform-detection.md
  - skills/cross-plugin-handoff/SKILL.md
  - agents/release-engineer.md
---

# App Store Publishing

Parse the arguments, dispatch `Task(corpflow:release-engineer)`, return its report. Every store flow
lives in the platform plugin that ships to that store, because App Store Connect and Play Console
differ field by field and a shared implementation would be true of neither.

Platform detection, alias resolution, and the sibling dispatch belong to the agent — routing policy
has one home, `skills/shared/routing-matrix.md`. This command writes nothing and holds no `Write`
grant.

## Options

| Option | Required | Effect |
|--------|----------|--------|
| `--task <listing\|screenshots\|iap>` | yes | The job. `listing` is store-listing metadata, `screenshots` the graphic assets, `iap` the in-app purchase products. |
| `--platform <apple\|android>` | no | Skips detection. Give it in a repo that carries markers for both. |
| everything else | no | Passed through verbatim to the target: `--lang`, `--path`, `--dry-run`, `--bundle`, `--apple-platform`, `--android-form-factor`. |

`--apple-platform` selects an Apple **device class** (`ios`, `macos`, `tvos`, `watchos`) and is
deliberately distinct from the plugin-wide `--platform`. Pass it through; never fold one into the
other.

```
/appstore --task listing --platform apple --lang ua
/appstore --task screenshots --apple-platform macos --path AppStore/
/appstore --task iap --platform apple --bundle com.example.app --dry-run   # read-only; no product created
/appstore --task listing --platform android
```

## Where the work happens

| Platform | Target agent | Commands it runs |
|----------|--------------|------------------|
| apple | `apple-developer:apple-release-engineer` | `/apple-developer:gen-appstore-listing`, `gen-appstore-screenshots`, `gen-appstore-iap` |
| android | `android-developer:and-release-engineer` | `/android-developer:gen-playstore-listing`, `gen-playstore-screenshots` |

Only platforms with a store have a target. `--task iap --platform android` is not supported yet —
Play Billing product setup is not ported.

## Refusals

The agent stops and reports rather than guessing when:

- both apple and android markers are present, or neither is, and no `--platform` was given;
- the resolved plugin is not installed — it names the plugin, the alias, and the direct
  `/<plugin>:<command>` to run instead, and records one `plugin_unavailable` audit row;
- the request is `--task iap` on android.

None of these fall back to doing the work inline, because writing to a live store account on a
guessed platform is the failure this design exists to prevent.

## Output Format

The delegate's report, prefixed by the route it resolved:

~~~markdown
# App Store Publishing — <task>

## Route — platform (detected or `--platform`) · target agent · command dispatched
## Result — the platform release engineer's report, verbatim
## Artifacts — paths the target wrote, or `none` (this command writes nothing itself)
## Next Steps — the direct `/<plugin>:<command>` to re-run, plus anything the agent flagged
~~~

A refusal (§ Refusals) replaces `## Result` with `## Refusal — <reason>` naming the plugin, the
alias, and the direct command to run instead. Either way the run ends in a report, never in a
partial store write.

## Relationship to the pipeline

`/appstore` runs outside the worktask pipeline and patches no `state.json`. The RE stage is
unchanged: `agents/release-engineer.md` still owns it, and the platform release engineers are
RE-stage *consultation* exactly as the platform architects are for AR.
