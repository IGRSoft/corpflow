# Clean plan fixture — no leaky tokens

This fixture exercises the happy path for the two-pass sanitiser. The body
must survive both Pass 1 (line-strip rules L1–L9) and Pass 2 (token-strip)
mostly intact.

## Summary

Implement OAuth login flow for the public-facing app. Add token refresh,
silent re-auth, and graceful fallback to password sign-in when refresh
tokens expire.

## Requirements

- REQ-A: Users can sign in with Google, Apple, and Microsoft providers.
- REQ-B: Refresh tokens persist across app restarts.
- REQ-C: Sign-out clears all cached identity material.
- REQ-D: First-launch UX shows provider buttons in localised order.

## Acceptance Criteria

- AC-1 (REQ-A): Given a clean install, When the user taps "Sign in with
  Google", Then they reach the home screen with a valid session.
- AC-2 (REQ-B): Given a valid refresh token, When the access token
  expires, Then the next API call succeeds without user interaction.
- AC-3 (REQ-C): Given a signed-in user, When they tap "Sign out", Then
  subsequent launches show the provider picker.

## Scope

In: OAuth provider integration, token storage, silent refresh, sign-out
flow. Out: enterprise SSO, magic-link email login, biometric unlock.

## Complexity

Score: 18/50 (Medium). Patterns 3, Integration 5, Concerns 4, Risk 3,
Docs 3. Standard OAuth library wiring plus a small UX state machine —
no novel cryptography, no on-device key storage beyond the platform
keychain wrapper.

## Planned Stages

PL0 → AR0 → DV0 → DR0 → QA0
