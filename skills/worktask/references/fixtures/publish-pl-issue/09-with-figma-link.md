# Plan with Figma design preview anchor

This fixture exercises the optional Design Preview render path. The plan
contains all four required anchors plus an additional `## design-preview`
anchor carrying a Figma URL. The render pipeline must surface a
"## Design Preview" section between Scope and Complexity, preserve the
Figma URL verbatim through both sanitiser passes, and emit a single
reviewer instruction line.

## Summary

Add dark-mode toggle to the Settings screen. Capture the design from
Figma and have DV and QA compare implementation and screenshots against
the linked frame.

## Requirements

- REQ-A: Settings screen exposes a toggle for system / light / dark mode.
- REQ-B: Selection persists across app restarts.
- REQ-C: First-launch defaults to "follow system".
- REQ-D: The toggle row matches the design linked under Design Preview.

## Acceptance Criteria

- AC-1 (REQ-A): Given the Settings screen, When the user taps the appearance
  row, Then a three-option picker appears with system, light, and dark.
- AC-2 (REQ-B): Given a dark-mode selection, When the app relaunches, Then
  the dark theme is active before the first screen renders.
- AC-3 (REQ-D): Given the implemented toggle row, When compared to the
  Figma frame, Then spacing, type ramp, and selection state match.

## Scope

In: Settings appearance row, theme persistence, app-startup theme
application. Out: per-screen theme overrides, scheduled theme switching,
user-uploaded accent colours.

## design-preview

https://www.figma.com/design/AbC123/Example?node-id=1-2

## Complexity

Score: 9/50 (Low). Patterns 2, Integration 2, Concerns 1, Risk 2, Docs 2.
Single screen plus persistence — well-trodden ground.

## stages

PL0 → DV0 → DR0 → QA0
