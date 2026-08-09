# Code audit — 2026-08-08

Two independent review waves were run against the codebase at `9e23fd9 fix: make ad hoc Sparkle bundles launchable`. Wave 1 was a self review using the `code-review-and-quality` skill (5 axes: correctness, readability, architecture, security, performance). Wave 2 was a delegated senior-dev review per the Foundation v1 `subagent-policy` (`final-review` role, GPT-5.6 Luna High).

## Inputs

- `Sources/ScreenShifterDomain/ScreenShifterDomain.swift`
- `Sources/DisplayCore/SystemDisplayInventory.swift`
- `Sources/ScreenShifterApp/ScreenShifterApp.swift`
- `Sources/ScreenShifterApp/ScreenShifterModel.swift`
- `Tests/DisplayCoreTests/SystemDisplayInventoryTests.swift`
- `Tests/ScreenShifterAppTests/ScreenShifterModelTests.swift`
- `Tests/ScreenShifterDomainTests/DisplayIdentityTests.swift`
- `scripts/package-dmg.sh`
- `scripts/publish-release.sh`
- `Package.swift`
- `docs/project-brief.md` (acceptance criteria)
- `docs/specs/screen-shifter-mvp-design.md` (module boundary spec)
- `docs/specs/screen-shifter-next-design.md` (product evolution)
- `docs/plans/issue-1-screen-shifter-mvp.md` (active plan)
- `PRODUCT.md`, `DESIGN.md`, `AGENTS.md`
- `project-sources.yml`, `.foundation/project.yml`, `.gitignore`

## Cross-check vs `docs/project-brief.md` acceptance criteria

| # | Criterion | Status | Note |
|---|---|---|---|
| 1 | Discovers connected built-in and external displays and resolves stable identities | pass | covered by `testSystemInventoryIncludesMainDisplay` (built-in) and `testExternalDisplayWithSerialNumberUsesHardwareIdentifier` (external identity). |
| 2 | Captures scaling for all connected displays only after user confirmation; one profile per display | pass | bulk-capture alert and per-display capture both write through `DisplayProfileStoring`; tests cover store save/replace/remove. |
| 3 | Automatic restore of known profiles; unknown displays unchanged | pass | `applySavedSetup(isAutomatic:)` iterates only known identities; `AutomaticDisplayChangePolicy` filters built-in-only changes. No end-to-end test of debounce→apply path. |
| 4 | Every external display uses maximum physical resolution while saved scaling is applied | partial in tests, **fail in production** | `ProfileModeSelector` is correct, but `CGDisplayCopyAllDisplayModes(_, nil)` may not surface the max-physical mode — see P0-A. |
| 5 | MacBook profile restored when all external displays disconnect | pass | the `displays == [builtIn]` subset of `applySavedSetup` finds the saved built-in profile. No specific test. |
| 6 | Menu bar exposes Settings, Apply Saved Setup, Capture Current Setup, Pause Automation, Launch at Login, Quit | fail | menu bar has only Settings and Quit; bulk-capture is dead code. See P0-C. |
| 7 | Settings: profile inspection, destructive reset with confirmation, error states, local log | pass with caveat | all four present; `errorMessage` is not cleared on success — see P1-7. |
| 8 | Packaged DMG, no runtime deps | pass | `package-dmg.sh` is correct; secrets never touch disk; public-repo enforced. |

7/8 pass, 1 partial, 1 fail.

## P0 (Critical)

- **P0-A — `CGDisplayCopyAllDisplayModes(_, nil)` may exclude HiDPI/scaled modes.**
  - `Sources/DisplayCore/SystemDisplayInventory.swift:267` and `:324` pass `nil` options.
  - On macOS 14+ this can omit modes different from the user's current scaling preference.
  - Effect: saved external HiDPI profile is reported `.unavailable` even when the physical mode exists. Breaks criterion 4.
  - Unit tests use synthetic `DisplayModeDescriptor` arrays, so the gap is invisible to `swift test`.
  - Fix: pass explicit options used by `displayplacer`: `[.kCGDisplayShowDuplicateLowResolutionModes, .kCGDisplayModeIsValid, .kCGDisplayModeIsSafe, .kCGDisplayModeIsInterlaced, .kCGDisplayModeIsStretched, .kCGDisplayModeIsTelevisionOutput]`.
  - Verification requires a real MacBook+Studio Display before merge.

- **P0-B — `setActivationPolicy(.regular)` overrides `LSUIElement=true`, showing the Dock icon.**
  - `Sources/ScreenShifterApp/ScreenShifterApp.swift:27` calls `setActivationPolicy(.regular)` in `init`.
  - `scripts/package-dmg.sh:47` writes `<key>LSUIElement</key><true/>`.
  - Brief and PRODUCT.md say "Dock icon is hidden by default".
  - Fix: remove the call; let the Info.plist govern.

- **P0-C — `applySavedSetup(isAutomatic:)` has no manual UI entry point; brief and next-design are out of sync.**
  - Only call site for `applySavedSetup` is the scheduled automation `Task` (`ScreenShifterModel.swift:522`).
  - `docs/project-brief.md` line 42 (criterion 6) still requires "Apply Saved Setup" in the menu bar.
  - `docs/specs/screen-shifter-next-design.md:19` explicitly removed it.
  - Fix: update brief to reflect intentional removal and link to next-design rationale.

## P1 (Important)

| # | File:line | Finding | Source |
|---|---|---|---|
| 1 | `ScreenShifterApp.swift:35-37` + `:42-68` | Two Settings entry points: SwiftUI `Settings {…}` scene plus custom `SettingsWindowController` opened from MenuBarExtra. Two windows, separate `@State`, UI desync risk. | W1 + W2 |
| 2 | `ScreenShifterApp.swift:85-94` | Dead-code alert "Save Current Display Profiles" in `MenuBarContent`; `prepareCapture()` is unreachable from any UI. | W1 + W2 |
| 3 | `ScreenShifterApp.swift:95-104` | Duplicate alert "Reset Display to Default" attached to `MenuBarContent`; same binding also used in `SettingsView:260-269`. Unreachable from menu bar. | W1 + W2 |
| 4 | `SystemDisplayInventory.swift:267` | Refresh rate is not in `DisplayModeDescriptor`; `first(where:)` may pick a mode at a different refresh rate than what the user originally selected. | W1 |
| 5 | `ScreenShifterModel.swift:155, 161` | Sleep assertion not created in `init`; on cold start with `keepExternalDisplayAwake=true` and a connected external display the Mac can sleep before the first `refresh()` runs. | W2 |
| 6 | `ScreenShifterModel.swift:261` | Reset path uses `resetCandidate` snapshot; if the display disconnected between the user clicking Reset and confirming, the error is generic and the saved profile is not removed. | W2 |
| 7 | `ScreenShifterModel.swift:227-352, 400-415` | `errorMessage` is not cleared on success in `completeCapture`, `confirmCapture`, `clearLogs`, `refreshLogs`, `openSystemSettings`, `record`, `setLaunchAtLogin`. | W2 |
| 8 | `ScreenShifterModel.swift:301-305` | `applySavedSetup` re-reads `profileStore.profiles()` even though `savedProfiles` is already in memory. Double encode/decode, non-atomic. | W2 |
| 9 | `SystemDisplayInventoryTests.swift:8-12, 239-256` | Two hardware-dependent tests will fail in headless CI and violate `next-design.md:55` ("No test may change a real display mode or power setting as part of the regular unit suite"). | W1 + W2 |
| 10 | `mvp-design.md` vs code | `DisplayInventorying` / `DisplayModeApplying` protocols from the design spec are not extracted; `ScreenShifterModel` instantiates concrete `SystemDisplayInventory` / `SystemDisplayModeApplier` directly. | W1 |

## P2 (Nice to fix)

### Domain / persistence
- `LocalLogStore.append` (`ScreenShifterDomain.swift:150-169`): `FileHandle` leak on throw between `open` and `close`; no `defer { try? handle.close() }`. [W2]
- `LocalLogStore.append` (`ScreenShifterDomain.swift:157`): `ISO8601DateFormatter()` instantiated on every call; should be `static let`. [W2]
- `LocalLogStore`: no size cap or rotation; append-only file grows unbounded. [W1 + W2]
- `UserDefaultsProfileStore.decodedProfiles` (`ScreenShifterDomain.swift:122-128`): `try?` silently swallows decode errors without logging. [W1]

### DisplayCore
- `SystemDisplayInventory.snapshot` (`SystemDisplayInventory.swift:310-313`): NSScreen lookup is O(displays × screens); build `[CGDirectDisplayID: NSScreen]` once per `connectedDisplays()` call. [W2]
- `displayModeDescriptor` (`SystemDisplayInventory.swift:48`): `isHiDPI` uses OR; stretched non-HiDPI modes (e.g. 2880×1080 / 1920×1080) are misclassified as HiDPI. [W2]
- Module boundary: `SettingsView.body:116` directly calls `CGMainDisplayID()`; App layer should not import CoreGraphics. [W1]

### App model
- `ScreenShifterModel` is ~400 lines and owns inventory, profile, log, Sparkle, sleep assertion, automation, launch-at-login. Split into focused collaborators. [W1]
- `updateSleepAssertion` (`ScreenShifterModel.swift:488-501`): stringly-typed error clear (`if errorMessage == "..."`). [W1 + W2]
- `cooldownUntil` (`ScreenShifterModel.swift:288`) is set before the inventory read; if `inventory.connectedDisplays()` throws, the cooldown blocks a legitimate trigger. [W1 + W2]
- `SMAppService.mainApp.status == .enabled` (`ScreenShifterModel.swift:156`) does not distinguish `.requiresApproval`. [W2]
- `setLaunchAtLogin` (`ScreenShifterModel.swift:384-398`) errors are generic; the underlying `NSError` is discarded. [W2]
- `SettingsView.synchronizeExpandedDisplay` (`ScreenShifterApp.swift:281-294`) overwrites the user's manual section expansion on any display change. [W1]

### Tests / docs
- Test file names do not reflect content: `SystemDisplayInventoryTests.swift` covers 9 types; `DisplayIdentityTests.swift` covers 4. Split by type. [W2]
- No end-to-end model-level tests for `refresh`, `completeCapture`, `applySavedSetup`, `handleDisplayChangeNotification`, debounce/cooldown sequence, identity collision, log store corruption, reset on disconnected display, `setLaunchAtLogin` happy path, `SystemSleepAssertionController`, `SettingsWindowController`. [W2]
- `docs/project-brief.md` ↔ `docs/specs/screen-shifter-next-design.md` are out of sync on criterion 6 (see P0-C). [W2]

## Nits

- `ScreenShifterApp.swift:123-132` — `Picker("Built-in display", selection: .constant(...))` is non-functional; a `Label` is more honest. [W1 + W2]
- `scripts/package-dmg.sh:36-59` — `Info.plist` built with `printf`; `bundle_identifier`, `version`, `sparkle_public_ed_key` interpolated without XML escaping. Constrained today, fragile. [W2]
- `scripts/package-dmg.sh:69-81` — `sign_options` and `sign_timestamp` are unquoted; `shellcheck` will flag; build an array. [W2]
- `ScreenShifterModel.swift:1` — `@preconcurrency import AppKit` masks future concurrency regressions on non-isolated contexts. [W2]
- `ScreenShifterDomain.swift:90` — `suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard`; passing `suiteName: nil` writes to real UserDefaults. Latent. [W2]
- `ScreenShifterModel.swift:146, 516, 517` — `scheduledAutomation` Task is not cancelled in `deinit`; leak only at process exit. [W2]
- `SparkleUpdaterDelegate.appcastURLString` is public but used only inside. [W1]
- `displayModeDescriptor(for:)` is a free function; a `static func` on the type is more discoverable. [W1]

## Foundation v1 compliance

Confirmed: `AGENTS.md`, `project-sources.yml`, `.foundation/project.yml`, `.gitignore` all follow the v1 template. No secrets in code. `SPARKLE_PRIVATE_ED_KEY` is passed via env var and piped to `generate_appcast` via stdin, never written to disk. The DMG packaging script requires the public key to be set together with the signing identity.

## Process notes

- Wave 1 (self) and Wave 2 (delegated) ran independently with no shared context.
- Wave 2 elevated two Wave 1 P2 findings to P0/P1: P0-C (manual apply, brief vs code) and P1-9 (hardware-dependent tests).
- Wave 2 surfaced three P0/P1 findings Wave 1 did not catch: P0-A (CGDisplayCopyAllDisplayModes options), P1-5 (sleep assertion in init), P1-6 (reset path stale snapshot), P1-7 (stale errorMessage), P1-8 (applySavedSetup re-reads profile store).
- No wrap-up was performed; the audit closes the review step of the task-runner workflow but defers wrap-up to after the implementation slices land.
