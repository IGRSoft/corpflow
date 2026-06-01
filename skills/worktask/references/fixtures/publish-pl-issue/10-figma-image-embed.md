# Plan with Figma image-embed design preview (placeholder tokens)

This fixture exercises the host-and-rewrite path. The `## design-preview`
anchor names two persisted per-frame screenshots using the placeholder
grammar `{{asset:<basename>}}` (basename only — no `.context/` path), each
immediately followed by its description bullet, with the Figma source URL
preserved on its own line above. The publish helper resolves each token to a
hosted `![<basename>](<https-url>)` image line AFTER `sanitise_body` runs, so
the image lines survive Pass-1 L1 and no local path ever reaches the body.

## Summary

Add a face-scan progress screen. Capture the design from Figma and have DV
and QA compare implementation and screenshots against the linked frames.

## Requirements

- REQ-A: The scan screen shows a circular progress ring with percent label.
- REQ-B: A hint banner appears while the user is positioning their face.
- REQ-C: An analyzing state with a spinner follows capture completion.
- REQ-D: Each state matches the design linked under Design Preview.

## Acceptance Criteria

- AC-1 (REQ-A): Given the scan screen at 25%, When rendered, Then the ring
  shows 25% fill and the percent label reads "25%".
- AC-2 (REQ-C): Given capture completes, When the analyzing state shows, Then
  a spinner and an "Analyzing…" label are visible.
- AC-3 (REQ-D): Given the implemented states, When compared to the Figma
  frames, Then spacing, type ramp, and selection state match.

## Scope

In: scan progress ring, hint banner, analyzing state, per-state theming.
Out: post-analysis results screen, share sheet, retake flow.

## design-preview

https://www.figma.com/design/FOO/FaceScan?node-id=255-2263

{{asset:figma-scan-25-default-255-2264.png}}
- state `default` — 25% progress ring, hint text hidden, primary CTA disabled.
{{asset:figma-analyzing-default-255-2267.png}}
- state `default` — spinner overlay, "Analyzing…" label, ring at 100%.

## Complexity

Score: 14/50 (Medium). Patterns 3, Integration 3, Concerns 2, Risk 3, Docs 3.
Multi-state single screen with per-frame design comparison.

## stages

PL0 → DV0 → DR0 → QA0
