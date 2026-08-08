# Screen Shifter v2 Architecture

## Goal

Bring the codebase from MVP-complete-but-fragile to release-ready by addressing the findings of the [2026-08-08 code audit](../audits/2026-08-08-code-audit.md). The audit identified 3 P0, 10 P1, 15 P2, and several nits. This spec defines the target architecture, scope, acceptance, and slice order for the fix-up.

## Scope

In scope:
- All P0 and P1 findings from the audit.
- Protocol extraction for `DisplayInventorying`, `DisplayModeApplying`, `MainDisplayIDProviding`.
- `DisplayModeDescriptor` and `DisplayProfile` gain `refreshRate` (rounded Hz).
- Typed `ModelError` replacing the stringly-typed `errorMessage`.
- Single Settings entry point: drop the custom `SettingsWindowController`; use the SwiftUI `Settings` scene and the `openSettings` env value from the menu bar.
- Removal of dead `prepareCapture` / `confirmCapture` / `captureCandidates` and the unreachable alerts in `MenuBarContent`.
- Test fakes for `DisplayInventorying` / `DisplayModeApplying`; the two hardware-dependent tests move behind `#if DEBUG && !CI`.

Out of scope:
- New product features. The per-display capture flow stays as-is.
- UI polish beyond the Settings duplication / dead-code cleanup.
- Log rotation (P2) — addressed in a follow-up spec.
- Build / packaging script hardening (P2 nits on Info.plist generation, sign-options quoting).
- Log viewer empty state, Picker-vs-Label on built-in display, scheduled-automation deinit cancel — address in a polish pass.

## Module boundaries (target)

`ScreenShifterDomain` — pure value types, persistence contracts, log store, identity formation, capture state machine, policy enums. No AppKit, no CoreGraphics.

`DisplayCore` — display discovery, topology, mode selection, mode planning, capture state transitions, mode application. Public surface is the three protocols and pure decision functions. Concrete `SystemDisplayInventory` and `SystemDisplayModeApplier` are module-private; the rest of the app talks to the protocols.

`ScreenShifterApp` — SwiftUI views, `@MainActor` model, Sparkle, IOKit sleep assertion, `SMAppService`. Depends on `ScreenShifterDomain` and `DisplayCore`; only uses the public protocols.

## Data model changes

- `DisplayModeDescriptor` gains `refreshRate: Double` (Hz, rounded to 0.01 Hz). Profiles store the rate as captured.
- Mode selection prefers the mode that matches the saved logical size, HiDPI flag, and refresh rate; falls back to the saved logical size + HiDPI + current refresh rate if no exact match exists.
- `DisplayProfile` mirrors the new field.
- New typed `ModelError` enum:
  ```swift
  enum ModelError: Equatable, Sendable {
      case sleepAssertionFailed
      case modeUnavailable(display: String)
      case launchAtLoginFailed(String)
      case logWriteFailed
  }
  ```
  The model publishes the current error; views render system-red text for any non-nil error and clear it on success.

## Protocol surface (target)

```swift
// in DisplayCore
@MainActor
public protocol DisplayInventorying: Sendable {
    func connectedDisplays() throws -> [ConnectedDisplay]
}

@MainActor
public protocol DisplayModeApplying: Sendable {
    func apply(_ profile: DisplayProfile, to display: ConnectedDisplay) throws -> DisplayApplicationOutcome
    func reset(_ display: ConnectedDisplay) throws
}

@MainActor
public protocol MainDisplayIDProviding: Sendable {
    var mainDisplayID: CGDirectDisplayID { get }
}
```

`ScreenShifterModel` accepts these in `init`. The default production wiring in `ScreenShifterApp` injects the system implementations; tests inject fakes.

## Decisions

1. **Single Settings entry point.** Drop `SettingsWindowController`. Use `Settings { SettingsView(model: model) }` and `openSettings` from `MenuBarContent`. The SwiftUI scene owns `@State` for selected external display and expansion.
2. **Per-display capture only.** Remove `prepareCapture`, `confirmCapture`, `captureCandidates`, and the bulk-capture alert.
3. **No manual Apply menu item.** Update `docs/project-brief.md` criterion 6 to reflect the new workflow; remove "Apply Saved Setup" from the menu bar spec. Document the rationale in the brief.
4. **`CGDisplayCopyAllDisplayModes` options**:
   ```swift
   let displayModeOptions: CGDisplayModeOption = [
       .kCGDisplayShowDuplicateLowResolutionModes,
       .kCGDisplayModeIsValid,
       .kCGDisplayModeIsSafe,
       .kCGDisplayModeIsInterlaced,
       .kCGDisplayModeIsStretched,
       .kCGDisplayModeIsTelevisionOutput
   ]
   ```
5. **`setActivationPolicy` removed.** `LSUIElement=true` in `Info.plist` is the source of truth.
6. **Refresh rate in profile.** Persisted at capture; used as a tiebreaker in mode selection; falls back to current rate if the saved rate is unavailable.
7. **Typed error model.** `ModelError` replaces `errorMessage: String?`; success paths clear the error before mutating state.
8. **Sleep assertion lifecycle.** Created in `init` after the initial `refresh()` completes.
9. **Reset path.** Re-read inventory before applying; remove the saved profile even if the display disconnected; show an explicit message describing the outcome.
10. **Test strategy.** Fakes for `DisplayInventorying` / `DisplayModeApplying`; the two hardware-dependent tests are gated by `#if DEBUG && !CI`.
11. **`applySavedSetup` profile lookup** uses the in-memory `savedProfiles`; no extra store read.
12. **`CGMainDisplayID()`** is wrapped by `MainDisplayIDProviding`; the App layer never imports CoreGraphics directly.

## Acceptance criteria

After the v2 work lands:

1. `swift build` and `swift test` are green. The 24 existing tests still pass.
2. At least 6 new model-level tests cover `refresh`, `completeCapture`, `applySavedSetup`, `setLaunchAtLogin`, `handleDisplayChangeNotification`, `confirmReset`, using fakes.
3. The three P0 findings (Dock icon, HiDPI mode options, brief ↔ code sync) are fixed.
4. All ten P1 findings are resolved.
5. Hardware-dependent tests are gated and not part of the default `swift test` run.
6. Manual external-display verification is recorded in `docs/verification/2026-08-08-external-display.md` with: monitor model, mode-capture result, manual apply result, reset result, disconnect-all result.
7. Foundation `preflight`, `boundary`, and `secret scan` pass on the final commit.
8. Two independent review waves (`wrap-up` skill) record PASS results before any release tag.

## Slices (commit order)

| # | Slice | Files | Risk | Verifies |
|---|---|---|---|---|
| 1 | P0-A: `CGDisplayCopyAllDisplayModes` options; P0-B: drop `setActivationPolicy` | `DisplayCore/SystemDisplayInventory.swift`, `ScreenShifterApp/ScreenShifterApp.swift` | low | swift build, swift test |
| 2 | P1-10 + P1-9: extract `DisplayInventorying` / `DisplayModeApplying` / `MainDisplayIDProviding`; add fakes; move hardware-dependent tests behind `#if DEBUG && !CI` | `DisplayCore/*`, `ScreenShifterApp/ScreenShifterModel.swift`, tests | medium | swift test, 6+ new tests |
| 3 | P1-4: refresh rate in `DisplayModeDescriptor` and `DisplayProfile`; matching tiebreaker in `ProfileModeSelector` | `ScreenShifterDomain`, `DisplayCore`, `ScreenShifterApp`, tests | medium (schema change) | swift test, new profile round-trip test |
| 4 | P1-1, 2, 3: single Settings entry point; remove dead bulk-capture and duplicate reset alert | `ScreenShifterApp.swift` | low | swift build, swift test |
| 5 | P1-7: typed `ModelError`; clear error on success | `ScreenShifterModel`, `SettingsView` | medium | swift test |
| 6 | P1-5, 6, 8: sleep assertion in init; reset re-validates; `applySavedSetup` uses cached profiles | `ScreenShifterModel` | medium | swift test |
| 7 | P0-C: update `docs/project-brief.md` criterion 6; remove the manual-apply line from the brief | `docs/project-brief.md` | low | docs review |
| 8 | P2 cleanup pass: P2-8 log rotation, P2-9 typed decode errors, P2-12 `MainDisplayIDProviding`, P2-7 test file split, P2-11 NSScreen dictionary | various | low | swift test |
| 9 | P2 packaging nits: XML-escape plist values; quote `sign_options` | `scripts/package-dmg.sh` | low | package-dmg.sh dry run |
| 10 | Verification record on real external display | `docs/verification/2026-08-08-external-display.md` | requires hardware | manual |

Each slice must keep `swift build` and `swift test` green and be committed separately. Slice commits are merged sequentially into `feature/issue-1-screen-shifter-mvp`.

## Verification

- `swift build` and `swift test` after each slice.
- `agent-foundation/scripts/check-project-preflight.sh --config-root $HOME/.agent-foundation --profile personal` before any push.
- `agent-foundation/scripts/check-secrets.sh --repository . --staged` before any push.
- Two independent review waves before wrap-up (per the `wrap-up` skill).
- Manual external-display test recorded in `docs/verification/`.

## Boundaries

- Always: public macOS APIs only, no private CoreGraphics, no `pmset`, no arrangement / mirroring / rotation.
- Ask first: any change to the persisted profile format (slice 3 changes it — confirm before merge), any change to the Sparkle feed URL or appcast behavior, any change to the public release repository.
- Never: copy upstream `displayplacer` code without license review, commit secrets, introduce network calls during normal display operation, modify the `agent-foundation` repository (human-gated, per user direction).
