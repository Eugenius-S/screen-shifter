# External display acceptance — 2026-08-08

> **Status: BLOCKED — awaiting physical MacBook + external monitor.**
>
> This file is the template for the manual acceptance evidence required
> by plan 001 step 6. Steps 1–5 (bootstrap, reset inventory failure,
> refresh-rate canonicalization, HiDPI both-dimensions, quiet menu-bar
> status) are complete on the `codex/001-reliability-release-readiness`
> branch and unit-tested. The release gate cannot be marked complete on
> unit tests alone; do not weaken the assertions below.
>
> Fill in every field. If a behaviour differs from the expectation, stop
> and report the observable result with the reproduction conditions.

## Build

- Commit: `<fill in — git rev-parse HEAD at time of verification>`
- Test result: `<fill in — swift test summary, expected: all green>`
- Secret scan: `<fill in — FOUNDATION_SECRET_SCAN=pass>`

## Environment

- macOS version: `<fill in — output of sw_vers>`
- MacBook model: `<fill in>`
- Monitor model: `<fill in — vendor/product from system report, no serial number>`

## Capture and manual apply

- Captured logical mode: `<fill in — e.g. 2560×1440>`
- Captured physical mode: `<fill in — e.g. 5120×2880>`
- Captured HiDPI state: `<fill in — true / false>`
- Captured refresh rate: `<fill in — Hz>`
- Manual apply result: `<fill in — applied / already applied / unavailable>`

## Reset

- Reset result: `<fill in — display returned to system default, profile removed from store, no errors>`

## Disconnect all (MacBook-only fallback)

- After disconnect: `<fill in — saved profile removed, display goes to system default>`

## Reconnect

- Reconnect result: `<fill in — saved profile re-applied automatically, or remained at default; menu-bar status updates>`

## Unknown displays

- Behavior: `<fill in — unknown displays stayed unchanged, no apply attempt>`

## Unexpected observations

- `<fill in — describe any deviation from the expectation above. If
  anything differs, stop here and report the reproduction conditions.>`

## Non-sensitive data rule

- Do not include serial numbers, account data, keys, tokens, or local
  absolute paths. Use the public-facing display name from System
  Settings → Displays.
