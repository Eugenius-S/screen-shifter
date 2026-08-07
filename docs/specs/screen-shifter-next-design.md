# Screen Shifter Next Design

## Objective

Evolve the Screen Shifter MVP into a display-specific capture workflow. The user selects the built-in or connected external display, starts a capture session, adjusts macOS display settings manually, and completes the capture for that display. Known scaling profiles are restored automatically without interfering with macOS power management.

## Product Decisions

- The built-in display is always available in the first display selector.
- The external display selector shows `Not detected` and is disabled until an external display is connected.
- Display discovery is automatic through the existing CoreGraphics inventory.
- Each display section has `Start capture settings`, a list of navigation actions, `Complete capture`, and `Reset default`.
- `Complete capture` is disabled until capture has started.
- `Reset default` is disabled until a saved profile exists for that display.
- Capture persists the display scaling mode and HiDPI state that the public macOS API can read and restore.
- `Font size` and `Dock size` are navigation actions to System Settings. They are not persisted as independent display profiles because public APIs do not provide a reliable per-display capture and restore contract for them.
- The log is a collapsible section below the display sections.
- `Check for updates` is a Settings action. The update implementation is a separate slice.
- `Saved profiles`, `Apply Saved Setup`, and `Capture Current Setup` are removed from the primary Settings workflow after the new capture flow is complete.
- The menu bar exposes `Settings` and `Quit`.
- Automatic display restoration reacts to external-display topology changes and wake stabilization. A change affecting only the built-in display must not call `CGDisplaySetDisplayMode`.
- An opt-in `Keep Mac Awake with External Display` setting uses a system sleep assertion only while an external display is connected. It does not change `pmset`, prevent display sleep, or manage power policy.
- Updates will use Sparkle with signed releases and an appcast hosted by a public release repository. This is outside the first UI slices.

## Architecture

`ScreenShifterDomain` owns capture state values, display identities, profiles, persistence contracts, and logs. `DisplayCore` owns display discovery, topology comparisons, mode planning, and pure capture transitions. `ScreenShifterApp` owns Settings presentation, system-settings navigation, update actions, and the IOKit sleep assertion lifecycle.

The capture UI is display-specific but continues to use the existing profile store. A capture session reads the current inventory only when the user completes capture, then saves the profile for the selected display after validating that the selected display is still connected.

## Commands

- Build: `swift build`
- Test: `swift test`
- Package: `./scripts/package-dmg.sh`
- Secret scan before push: `/Users/eugene/Documents/agent-foundation/scripts/check-secrets.sh --repository . --staged`

## Increment Plan

1. Add pure capture state transitions and tests: `idle -> capturing -> completed`, with invalid completion remaining disabled.
2. Add per-display capture session state to `ScreenShifterModel` and preserve the existing capture behavior behind the new state.
3. Replace the Settings display section with built-in and external display selectors and one reusable display capture section.
4. Add display-specific `Complete capture` and `Reset default` actions, including unavailable and disconnected-display errors.
5. Add System Settings navigation rows and the collapsible local log section.
6. Add `Check for updates` behind a protocol and deterministic fake.
7. Integrate Sparkle, signed appcast metadata, and public release-feed packaging.
8. Run real hardware checks for cable connect, clamshell, wake, reset, disconnect, and multiple external displays.

Each increment must keep `swift build` and `swift test` passing and should be committed separately.

## Testing Strategy

- Unit tests cover capture transitions, topology filtering, display identity matching, profile persistence, and mode planning.
- App behavior is verified with model-level tests where possible and manual macOS checks for SwiftUI presentation, System Settings URLs, IOKit assertions, and real monitor transitions.
- No test may change a real display mode or power setting as part of the regular unit suite.

## Boundaries

- Always: use public macOS APIs, keep unknown displays unchanged, validate the selected display before capture, and run build plus tests after each increment.
- Ask first: adding third-party runtime dependencies, changing the release repository, changing power assertion semantics, or changing the persisted profile format.
- Never: use private display APIs, change `pmset`, add mirroring or arrangement control, commit secrets, or make the app require network access for normal display operation.

## Success Criteria

- The built-in selector is usable with no external display connected.
- The external selector is disabled and displays `Not detected` until a monitor is connected.
- A user can start and complete a capture for each connected display independently.
- Reset is available only for a display with a saved profile.
- Closing the lid does not cause Screen Shifter to reapply a mode solely because the built-in display changed state.
- The optional sleep assertion is active only when enabled and an external display is connected, and it is released when either condition becomes false.
- All unit tests and the Swift build pass after each increment.
