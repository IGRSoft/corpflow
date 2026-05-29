# Already-published fixture — companion 04-state.json is what drives the test

The companion file `04-state.json` (sibling in this directory) carries a
`metadata.github_issue_url` value. When the helper is launched with
`STATE_FILE=…/04-state.json`, the idempotency guard MUST short-circuit
and audit `deferred`/`already_published` without invoking gh.

This `.md` body is a placeholder — the fixture's intent is verified by
reading the JSON state file, not this plan. The self-test for fixture 04
confirms that 04-state.json carries a populated github_issue_url.
