# Screen Shifter MVP Design

## Decision

Build Screen Shifter as a macOS 14+ Swift Package that opens directly in Xcode. The package contains an executable SwiftUI app target and focused library targets so the domain and display logic can be tested without changing a connected display.

The app uses a menu-bar-first SwiftUI lifecycle with a persistent Settings scene. It stores all state locally and has no network, account, analytics, or runtime executable dependency.

## Module Boundaries

### ScreenShifterDomain

Owns display identity, discovered display snapshots, saved scaling profiles, and profile-store contracts. A display identity is stable when vendor ID, product ID, and serial number are present; otherwise it includes the display name and stable physical characteristics.

### DisplayCore

Owns CoreGraphics display discovery and mode operations behind `DisplayInventorying` and `DisplayModeApplying` protocols. The production implementation calls public CoreGraphics APIs only. It compares the current mode before applying a profile and reports unsupported or unavailable modes as typed errors.

The first runtime capability check must use a real external display. Until it passes, `DisplayCore` must not import or copy `displayplacer` code, call private APIs, or claim that every macOS display can be scaled programmatically.

### ScreenShifterApp

Owns the SwiftUI menu bar, Settings scene, application state, and user actions. It depends on protocols from the library targets, making previews and unit tests use deterministic in-memory fakes.

## Data Flow

1. `DisplayCore` discovers the active displays and builds immutable snapshots.
2. The app reads saved profiles from the local profile store and matches them by stable identity.
3. Capture shows the candidate profiles before any write, then persists only after confirmation.
4. Manual Apply and automation ask `DisplayCore` to apply only known profiles.
5. Failed applications are retained in the local log and presented as error notifications. Successful automatic actions remain visible only in the menu status and log.

## Automation Safety

Display-change callbacks feed a coordinator that debounces events for two seconds, compares the desired and current modes, and rejects repeated applications during a three-second cooldown. Automation is disabled while paused, while the Mac is waking, and for unknown displays. When no external display remains, the coordinator evaluates the saved built-in-display profile.

## First Delivery

The first implementation slice creates the package, test targets, app shell, domain value types, in-memory profile storage, and public-API capability probe. It proves the project builds and that the public mode API is available on this Xcode SDK. It does not yet apply a display mode automatically.

## Verification

- `swift test` covers identity formation, profile matching, and in-memory persistence.
- `swift build` compiles the SwiftUI menu-bar shell for macOS.
- A real external-display test is required before marking mode application complete.
- No external source is incorporated without a reviewed license and attribution plan.
