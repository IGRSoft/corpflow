# Leaky plan fixture — every line below must be stripped by Pass 1 or Pass 2

## Summary

See .context/planning-3.md for the canonical spec.

## Requirements

- REQ-A: Edit MyModule.swift to add the new login flow.
- REQ-B: Refer to /Users/foo/bar/src/AuthCoordinator.swift for the
  reference impl.
- REQ-C: Working dir is conductor/workspaces/andorra-v1 during dev.
- REQ-D: Config at ~/.config/oauth.toml drives behaviour.
- REQ-E: Cache lives at /tmp/oauth-cache during tests.
- REQ-F: plan_file: planning-2.md tracks the parent epic.
- REQ-G: Edit ./src/networking/HTTPClient.swift to bump the timeout.

## Acceptance Criteria

- AC-1: Run xcodebuild test -workspace App.xcworkspace.
- AC-2: artifact_path: development-1.md must list every modified file.
- AC-3: See analyzing-0.md for architectural decisions.
- AC-4: workspace_path = /Users/korich/conductor/workspaces/foo.

## Scope

Touched files: AppDelegate.swift, SceneDelegate.swift, NetworkClient.swift.
Documentation lives in docs/auth-design.md.

## Complexity

Score: 24/50 (Moderate). run_index: 0 for this iteration.

## Planned Stages

PL0 → AR0 → DV0 → DR0 → QA0 (see coordination-0.md for fan-out).
