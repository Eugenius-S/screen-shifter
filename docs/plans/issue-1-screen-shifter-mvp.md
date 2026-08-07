# Issue #1: Screen Shifter MVP

## Status

In progress: core profile capture, manual apply, guarded automatic restoration, local logs, reset behavior, login-item registration, and DMG packaging are implemented and locally tested.

## Goal

Implement the native macOS menu bar application defined by Issue #1 and `docs/project-brief.md`.

## Scope

- Swift and SwiftUI macOS app with a menu bar control and persistent Settings window.
- Display inventory, stable external-display identity resolution, local profiles, local logs, onboarding, automation pause, and Login Item setting.
- Capture all currently connected display scaling modes only after a confirmation dialog.
- Apply known profiles after settled display changes and apply the saved MacBook profile after all external displays disconnect.
- Keep external displays at their maximum physical resolution while restoring their saved logical scaling mode.
- Provide Reset to Default per display and error-only user notifications.
- Integrate display mode application behind an internal `DisplayCore` abstraction.

## Out of scope

- Display arrangement, primary display selection, rotation, refresh rate, HDR, color profile, brightness, wallpaper, cloud sync, analytics, accounts, and network services.
- Multi-display combination profiles. Known displays apply independently.
- Copying displayplacer source until its implementation path, license obligations, and macOS behavior have been reviewed on the target host.

## Plan

1. Provision a macOS 14+ build host, set the `macos` source alias in `project-sources.yml`, and verify Xcode command-line tools.
2. Create the Xcode project, app target, unit-test target, app metadata, and menu bar plus Settings shell.
3. Implement the domain model, UserDefaults persistence, display inventory, stable identity matching, profile capture confirmation, and local log storage with unit tests.
4. Implement `DisplayCore` mode discovery and application behind a protocol, with exact-mode matching, external maximum-physical-resolution enforcement, current-mode no-op checks, rollback handling, and error reporting.
5. Implement display observation, debounce, cooldown, wake protection, independent profile application, MacBook-only fallback, pause automation, and launch-at-login behavior.
6. Implement Settings, onboarding, menu actions, profile reset confirmation, log viewer, and error-only notifications.
7. Test on the target MacBook with one and multiple external displays, including an unknown monitor, a saved monitor, disconnect-all, unavailable mode, reset, pause, sleep/wake, and dock scenarios.
8. Add packaging, license attribution if external source is used, Developer ID/notarization documentation, and DMG build evidence.

## Verification

- `xcodebuild` build and unit tests on macOS.
- Manual acceptance checks against every criterion in Issue #1 on a real MacBook and external display.
- Staged secret scan before each push.
- Two independent review waves before PR creation and wrap-up.

## Checkpoint

- Last completed: repository and Issue intake; Xcode 26.6, macOS SDK 26.5, and Swift 6.3 verification; public CoreGraphics display inventory and exact mode selection; UserDefaults profile persistence; menu-bar Capture Current Setup with overwrite confirmation; Settings profile inspection; manual Apply Saved Setup; and display-change automation with two-second debounce, three-second cooldown, wake protection, and persistent pause.
- Current blocker: setting a non-current mode and reset-to-default have not yet been manually verified against a real external display. The current host has only its built-in display connected. The public CoreGraphics reset path is implemented with a nullable mode, as documented in the installed SDK. No external source has been incorporated, so `displayplacer` licensing review remains deferred.
- Next action: connect a known external display, capture a non-current scaling profile, manually apply it, verify reset and disconnect-all fallback, and record the result. Then run the two independent review waves and final secret scan before PR or wrap-up.
