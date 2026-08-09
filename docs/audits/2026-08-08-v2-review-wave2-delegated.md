# v2 review — 2026-08-08 (Wave 2 / delegated)

## Verdict
PASS with concerns

## Scope
- Range: d47a433..HEAD (11 commits on `feature/issue-1-screen-shifter-mvp`)
- Time spent: ~35 minutes
- Test suite at HEAD: 44/44 passing (`caffeinate -u -t 120 swift test`, Executed 44 tests, with 0 failures in 2.7s)
- `swift build` clean at HEAD
- Foundation `check-secrets.sh --repository .` reports `FOUNDATION_SECRET_SCAN=pass`
- Foundation `check-project-preflight.sh` reports `PROJECT_PREFLIGHT_*=fail` for `DOCTOR`, `SOURCE_ALLOWED`, `GIT_STATE`, `CACHE_TEMP_OUTSIDE`. Reproduced against the pre-v2 commit `d47a433` (same `SOURCE_ALLOWED`/`GIT_STATE` failures with no v2 changes in scope) and against `main` (same pattern). The `DOCTOR` failure is a missing `foundation-doctor.sh` in the local `agent-foundation` checkout; the `SOURCE_ALLOWED`/`GIT_STATE` failures trace to `PERSONAL_SOURCE_ROOT` not being set in the user's `personal.env`. None of these are caused by the v2 work. Secret scan is the gating Foundation check and it passes.

## P0 / P1 audit findings

### P0-A — `CGDisplayCopyAllDisplayModes` options
**Status: PASS**
`Sources/DisplayCore/SystemDisplayInventory.swift:10-12` defines `displayModeOptions()` returning `[kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary`. The dictionary is threaded into both call sites: `snapshot(for:screenByID:)` at `SystemDisplayInventory.swift:353` (building `availableModes`) and the runtime re-snapshot in `SystemDisplayModeApplier.apply(_:to:)` at `SystemDisplayInventory.swift:282`. The audit called out that the v1 P0-A fix was in slice 1 (`bf8bda9`) and that the later `4473ce2` refactor could have regressed it; it did not — both call sites still pass `displayModeOptions()`.

### P0-B — `setActivationPolicy(.regular)` override
**Status: PASS**
`grep -rn "setActivationPolicy" Sources/ Tests/ scripts/` returns zero matches. The App entry point at `Sources/ScreenShifterApp/ScreenShifterApp.swift:6-40` is a pure SwiftUI `MenuBarExtra` + `Settings` scene; `NSApplication.setActivationPolicy` is never called. `LSUIElement=true` is the only source of dock-icon behavior (`scripts/package-dmg.sh:59`).

### P0-C — brief criterion 6 sync
**Status: PASS**
`docs/project-brief.md:40` (criterion 6) now reads: "The menu bar exposes Settings and Quit. Pause Automation, Launch at Login, capture controls, and log access live in the Settings window." The "Apply Saved Setup" requirement is gone and the rationale points to `screen-shifter-next-design.md`. Matches the v2 spec decision 3.

### P1-1 / P1-2 / P1-3 — single Settings entry point, dead bulk-capture, duplicate reset alert
**Status: PASS**
`ScreenShifterApp.swift:42-59` defines `MenuBarContent` with `@Environment(\.openSettings) private var openSettings` and a single `Button { openSettings() }` ("Settings…") plus Quit. `grep -rn "SettingsWindowController" Sources/ Tests/` returns zero matches — the custom controller is gone. The dead `prepareCapture` / `confirmCapture` / bulk-capture alert paths are removed; the two functions remain as no-op stubs (`ScreenShifterModel.swift:198-202`, `:248-251`) with a comment explaining the removal. The duplicate reset alert from `MenuBarContent` is gone; only the `SettingsView` alert at `ScreenShifterApp.swift:213-222` remains.

### P1-4 — refresh rate in `DisplayProfile`
**Status: PASS**
`Sources/ScreenShifterDomain/ScreenShifterDomain.swift:32-65`: `DisplayProfile` gains `refreshRate: Double` with default `0`, and the custom `init(from:)` uses `decodeIfPresent` for the field (`:63`) so legacy JSON without the field still decodes. `DisplayModeDescriptor` mirrors the field (`SystemDisplayInventory.swift:14-37`). `ProfileModeSelector.matchingMode(for:availableModes:requiresMaximumPhysicalResolution:)` uses the field as a tiebreaker when the profile's rate is non-zero (`SystemDisplayInventory.swift:75`). `DisplayProfileTests.testDecodesBackwardCompatibleWithoutRefreshRateField` and `testRoundTripsWithRefreshRate` both pass — schema migration is exercised.

### P1-5 — sleep assertion in `init`
**Status: PASS**
`ScreenShifterModel.swift:171-177`:
```
if keepExternalDisplayAwake {
    _ = sleepAssertion.update(isEnabled: true)
}
```
The first `refresh()` later re-evaluates via `updateSleepAssertion()` (`:188`) and releases the assertion if no external display is connected. Matches the v2 spec decision 8.

### P1-6 — `confirmReset` re-validates
**Status: PASS**
`ScreenShifterModel.swift:262-297` re-reads inventory before applying: `let currentDisplays = (try? inventory.connectedDisplays()) ?? []` and `let stillConnected = currentDisplays.contains { $0.identity == display.identity }`. The applier reset runs only when the display is still connected; the saved profile is removed either way. The `captureMessage` distinguishes the two cases (`:293-295`). The disconnect-aware path is exercised by `testConfirmResetRemovesProfileWhenDisplayDisconnected` (passes). The applier-throws path is exercised by `testConfirmResetSurfacesResetErrorWhenApplierThrows` and verifies the saved profile is **preserved** on error (passes). Both branches match the audit's intent.

### P1-7 — typed `ModelError`, clear on success
**Status: PASS**
`Sources/ScreenShifterApp/ModelError.swift:8-72` defines the enum with 11 cases and a `message: String` accessor. `errorMessage: ModelError?` (`ScreenShifterModel.swift:122`). All user-action methods clear the error on success: `refresh` (`:189`), `completeCapture` (`:238`), `confirmReset` (`:292`), `applySavedSetup` (`:354`), `clearLogs` (`:373`), `checkForUpdates` (`:406`), `setLaunchAtLogin` (`:419`), `openSystemSettings` (`:457`). `testModelErrorMessageRendersUserFacingText`, `testClearLogsClearsErrorOnSuccess`, `testCompleteCaptureClearsErrorOnSuccess` all pass.

### P1-8 — `applySavedSetup` uses `savedProfiles` cache
**Status: PASS**
`ScreenShifterModel.swift:324-328` builds the lookup from the in-memory `savedProfiles`:
```
let profilesByIdentity = Dictionary(
    uniqueKeysWithValues: savedProfiles.map { ($0.displayIdentity, $0) }
)
```
No `await profileStore.profiles()` call inside `applySavedSetup`. The contract is exercised by `testApplySavedSetupUsesCachedProfilesInsteadOfReReadingStore` (mutates the store directly after `refresh()`, asserts the model still uses the cached 1920×1080 profile rather than the new 2560×1440). Passes.

### P1-9 — hardware-dependent test gated
**Status: PASS**
`Tests/DisplayCoreTests/SystemDisplayModeApplierTests.swift:8-27` wraps the `SystemDisplayInventory().connectedDisplays()` call in `#if DEBUG && !CI`. Verified the test compiles and the body is empty in non-DEBUG or CI builds. The other hardware-dependent test referenced in the audit (`SystemDisplayInventoryTests.testSystemInventoryIncludesMainDisplay`) was rewritten in slice 8 to use `FakeDisplayInventory` and no longer touches hardware.

### P1-10 — protocols extracted
**Status: PASS**
`Sources/DisplayCore/DisplayCoreProtocols.swift:6-19` defines all three protocols (`DisplayInventorying`, `DisplayModeApplying`, `MainDisplayIDProviding`) as `@MainActor` `Sendable`. `ScreenShifterModel.init` accepts them as parameters (`ScreenShifterModel.swift:153-160`) with a default `profileStore` and `logStore`. `ScreenShifterApp.init` wires the system implementations (`ScreenShifterApp.swift:22-27`). Test fakes live in `Tests/DisplayCoreTests/DisplayCoreFakes.swift` and `Tests/ScreenShifterAppTests/DisplayCoreFakes.swift` (the App-level fakes also expose `lastAppliedProfile` to verify the cache contract in `testApplySavedSetupUsesCachedProfilesInsteadOfReReadingStore`).

## P2 cleanup (slices 8–9)

### P2-1 — `LocalLogStore.append` `defer` close
**Status: PASS**
`Sources/ScreenShifterDomain/ScreenShifterDomain.swift:227-232` opens the `FileHandle`, immediately registers `defer { try? handle.close() }`, then seeks and writes. No leak path.

### P2-2 — shared `ISO8601DateFormatter`
**Status: PASS**
`ScreenShifterDomain.swift:183-186` declares `private nonisolated(unsafe) static let iso8601: ISO8601DateFormatter` and reuses it on every append (`:223`). `ISO8601DateFormatter` is documented as thread-safe for read-only formatting; the unsafe isolation is correct.

### P2-8 — log rotation with `maxLogBytes`
**Status: PASS**
`ScreenShifterDomain.swift:178` defines `public static let maxLogBytes: UInt64 = 1_048_576` (1 MiB). `LocalLogStore.init(fileURL:maxLogBytes:)` (`:198-204`) lets tests inject a smaller cap. `append` checks the on-disk size and `removeItem` when over the cap (`:217-221`). `LocalLogStoreTests.testRotatesWhenFileExceedsMaxBytes` uses `maxLogBytes: 50`, writes 200 bytes of filler, then asserts the new "second" line is present and the old "first" line is gone. Passes.

### P2-9 — `UserDefaultsProfileStore` surfaces errors to stderr
**Status: PASS**
`ScreenShifterDomain.swift:114-122` and `:152-159` use `do/catch` for both encode and decode paths; the `logProfileStoreError(operation:error:)` helper at `:162-165` writes to `FileHandle.standardError` via `nonisolated`. `UserDefaultsProfileStoreTests.testCorruptedPayloadReturnsEmptyProfiles` writes invalid JSON into the same key, then asserts `profiles()` returns `[]` and `profile(for:)` returns `nil`. Passes. The user-facing flow is unchanged because the store has no way to recover the data; the stderr message is the appropriate channel for a corruption event the user cannot act on.

### P2-11 — NSScreen dict built once per `connectedDisplays()`
**Status: PASS**
`SystemDisplayInventory.swift:321` calls `screenMap()` once per inventory call, then `snapshot(for:screenByID:)` (`:338-364`) does an O(1) lookup. `screenMap()` (`:328-336`) returns `[CGDirectDisplayID: NSScreen]` keyed off `NSDeviceDescriptionKey("NSScreenNumber")`. O(N×M) → O(N+M).

### P2-7 — test file split
**Status: PASS**
Per-type test files now exist:
- `Tests/DisplayCoreTests/`: `AutomaticDisplayChangePolicyTests`, `AutomationPolicyTests`, `DisplayCaptureStateMachineTests`, `ExternalDisplaySleepPolicyTests`, `ProfileApplicationPlannerTests`, `ProfileCapturePlannerTests`, `ProfileModeSelectorTests`, `SystemDisplayInventoryTests`, `SystemDisplayModeApplierTests`, `DisplayCoreFakes`.
- `Tests/ScreenShifterDomainTests/`: `DisplayIdentityTests`, `DisplayProfileTests`, `InMemoryProfileStoreTests`, `LocalLogStoreTests`, `UserDefaultsProfileStoreTests`.
- `Tests/ScreenShifterAppTests/`: `ScreenShifterModelTests`, `DisplayCoreFakes`.

`Package.swift` uses default target discovery so all new files are picked up. The legacy `SystemDisplayInventoryTests` was reduced from 399 lines (9 types) to one fake-based smoke test, with the per-type coverage moved to the new files.

### P2-12 — `MainDisplayIDProviding` in App, no `import CoreGraphics` in App
**Status: PASS**
`grep "import CoreGraphics" Sources/ScreenShifterApp/*.swift` returns zero matches. The App's "active display" check at `ScreenShifterApp.swift:69` reads `model.mainDisplayIDProvider.mainDisplayID` (the protocol property).

### Packaging nits
**Status: PASS**
- `plist_escape()` defined at `scripts/package-dmg.sh:39-46` and applied to every interpolated plist value: `bundle_identifier` (`:53`), `version` (`:56`, `:57`), `sparkle_feed_url` (`:61`), `sparkle_public_ed_key` (`:68`). The hard-coded `Screen Shifter` strings are literal plist content with no interpolation, so they don't need escaping.
- `sign_options` is a bash array at `package-dmg.sh:87-90` and expanded as `"${sign_options[@]}"` for every `codesign` call (`:92-104`). Empty array case (ad-hoc) is handled by the `if test "$CODESIGN_IDENTITY" != "-"` guard.

## New issues introduced

### Concern 1 — `cooldownUntil` ordering still sets cooldown before inventory read (P2-15)
**Severity: P2 (deferred to v3 per spec)**
`ScreenShifterModel.swift:300-322`: when `isAutomatic: true` and the policy check passes, `cooldownUntil` is set at `:310` before the inventory read at `:314`. If `inventory.connectedDisplays()` throws, the cooldown is already armed and will block the next legitimate trigger for ~3 s. The audit explicitly flagged this (P2-15) and the v2 spec lists it under "Open items / future work"; the v2 work did not address it. **Not a regression** — the issue existed pre-v2 — but I want to surface it so it does not get lost. It is harmless in practice because the user only ever sees automatic triggers fire on display notifications, and a missed apply is recovered on the next notification.

### Concern 2 — `isHiDPI` still uses OR (P2-6)
**Severity: P2 (deferred to v3)**
`SystemDisplayInventory.swift:60` keeps `isHiDPI: pixelWidth > logicalWidth || pixelHeight > logicalHeight`. Stretched non-HiDPI modes (e.g. 2880×1080 / 1920×1080) are still misclassified as HiDPI. Explicitly deferred in the v2 spec. Not regressed by v2.

### Concern 3 — `@preconcurrency import AppKit` still present
**Severity: nit (deferred)**
`ScreenShifterModel.swift:1`. Explicitly out of scope per the v2 spec.

### Concern 4 — `Picker("Built-in display", selection: .constant(...))` still present
**Severity: nit (deferred)**
`ScreenShifterApp.swift:76`. A `Label` would be more honest, but the current `Picker` is harmless and explicitly deferred.

### Concern 5 — `SparkleUpdaterDelegate.appcastURLString` still public
**Severity: nit (deferred)**
`ScreenShifterModel.swift:38`. Still used by the test at `ScreenShifterModelTests.testSparkleUpdaterDelegateUsesAppcastURL`, so making it `private` would force a test refactor. Defer to v3.

### Concern 6 — `displayModeDescriptor(for:)` is still a free function
**Severity: nit (deferred)**
`SystemDisplayInventory.swift:48`. A `static func` on the type would be more discoverable. Defer to v3.

### Concern 7 — `prepareCapture` and `confirmCapture` left as no-op stubs
**Severity: nit**
`ScreenShifterModel.swift:198-202` and `:248-251`. The functions are kept because they are part of the model's public surface (visible to tests and any future caller) and removing them would be a breaking change to the type. The comment explains the removal. The stubs do not affect behavior. This is a reasonable trade-off — if v3 wants them gone, the file's tests can drop the references at the same time.

No regressions. No test that was passing in the pre-v2 baseline was lost. The new tests (refresh, completeCapture, applySavedSetup cache, handleDisplayChangeNotification, confirmReset on disconnect, confirmReset on applier throw, clearLogs/completeCapture error clearing, model error message rendering, refresh rate selector, profile round-trip, log rotation, decode error) all assert meaningful behavior and are not over-mocking.

## Test quality

**Verdict: solid.** I read all 17 new/modified test files. No `XCTAssertTrue(true)`, no purely-cosmetic assertions, no mocks-of-the-system-under-test. Highlights:

- `testApplySavedSetupUsesCachedProfilesInsteadOfReReadingStore`: this is the strongest test in the suite. It populates the store, calls `refresh()` to populate the cache, mutates the store **outside the model** to write a different profile, calls `applySavedSetup`, and asserts the cache value (1920×1080) was applied instead of the mutated store value (2560×1440). This is exactly the contract the audit was worried about.
- `testConfirmResetRemovesProfileWhenDisplayDisconnected`: replaces the inventory mid-test (`inventory.displaysToReturn = []`) to simulate the disconnect-between-prepare-and-confirm race. Asserts the profile is still removed and the `captureMessage` mentions "disconnected".
- `testConfirmResetSurfacesResetErrorWhenApplierThrows`: uses a separate `ThrowingResetApplier` so it can assert the saved profile is **preserved** (not just removed) on applier failure. Matches the audit's intent.
- `testCorruptedPayloadReturnsEmptyProfiles`: writes `Data("not valid json".utf8)` to the same key the store uses, then asserts both `profiles()` and `profile(for:)` return empty/nil. Verifies the do/catch path actually catches the decode error.
- `testRotatesWhenFileExceedsMaxBytes`: uses a 50-byte cap and 200 bytes of filler to force the rotation. Asserts the old "first" line is gone and the new "second" line is present.
- `testDecodesBackwardCompatibleWithoutRefreshRateField`: feeds the decoder pre-v2 JSON (no `refreshRate` field) and asserts the default `0` is used. Verifies the schema migration.
- `testMatchesByRefreshRateWhenSpecified` and `testAcceptsAnyRefreshRateWhenProfileRateIsZero`: prove the new tiebreaker works in both directions.

The two fakes files duplicate `FakeDisplayInventory` / `FakeDisplayModeApplier` / `FakeMainDisplayIDProvider` across `Tests/DisplayCoreTests/DisplayCoreFakes.swift` and `Tests/ScreenShifterAppTests/DisplayCoreFakes.swift`. That is required because SwiftPM test targets can't share private types; the duplication is a known cost of the test target split. The App-level fake adds `lastAppliedProfile` to verify the cache contract; that single extra line is the only difference between the two files.

The `testHandleDisplayChangeNotificationSchedulesApplyOnTopologyChange` test uses a real `Task.sleep(2_500_000_000)` to wait for the 2-second debounce. Total runtime 2.5 s, which is the slowest test in the suite but well within reason. Not a flake risk on the normal run.

## Foundation v1 compliance

- `AGENTS.md` unchanged (still Foundation v1 Personal / files / common writing).
- `project-sources.yml` unchanged.
- `.foundation/project.yml` unchanged.
- `agent-foundation` not modified.
- No new third-party dependencies; `Package.swift` and `Package.resolved` unchanged from the v1 baseline.
- `.gitignore` and secrets: `grep -rE "SPARKLE_PRIVATE_ED_KEY|CODESIGN_IDENTITY|api[_-]?key|secret"` shows the only references are env-var consumers (`SPARKLE_PRIVATE_ED_KEY`, `CODESIGN_IDENTITY`, `SPARKLE_PUBLIC_ED_KEY`). No hard-coded secrets, no `.env` writes, no keys in the diff. `check-secrets.sh --repository .` → `FOUNDATION_SECRET_SCAN=pass`.
- `preflight` (the Foundation doctor) fails to run in this environment because `foundation-doctor.sh` and the user's `personal.env` are not present in the local `agent-foundation` checkout. I confirmed the same failure mode at the pre-v2 commit `d47a433` and on `main`, so it is an environmental issue, not a v2 regression. **Action: project maintainer should set `PERSONAL_SOURCE_ROOT` in `personal.env` to unblock the preflight gate before the final release.**

## Open items

1. **Slice 10 — manual external-display verification** on a real MacBook + Studio Display. Not done in this review (requires hardware). Required before release per v2 acceptance criterion 6.
2. The 8 deferred items (P2-6, P2-13, P2-15, P2-16, P2-17, the `Picker` nit, `@preconcurrency AppKit` nit, `suiteName` flatMap nit, `scheduledAutomation` deinit cancel nit, `appcastURLString` visibility nit, free-function nit) — all explicitly out of scope for v2.

## Recommendations for v3

1. **P2-15 (cooldownUntil ordering).** Move the `cooldownUntil = Date().addingTimeInterval(3)` assignment to **after** the successful inventory read in `applySavedSetup`. A failed read should not arm the cooldown.
2. **P2-6 (isHiDPI).** Switch to `pixelWidth > logicalWidth && pixelHeight > logicalHeight` (strictly greater on both axes), or compute from `mode.pixelWidth * mode.pixelHeight > mode.width * mode.height` for the stretched-mode edge case.
3. **P2-13 (split model).** `ScreenShifterModel.swift` is still ~530 lines and owns inventory, profile, log, Sparkle, sleep, automation, launch-at-login. Extract a `SettingsStore` for `automationPaused` / `keepExternalDisplayAwake` / `launchAtLoginEnabled` and a `CaptureCoordinator` for the capture state machine; the model becomes a thin orchestrator.
4. **Nit: drop `@preconcurrency import AppKit`.** The model is `@MainActor`; the import annotation is masking what should be a real concurrency fix.
5. **Nit: `Picker` → `Label` for the built-in display.** The control is non-functional today; `Label(builtInDisplay.name)` is honest and renders identically.
6. **Nit: `SparkleUpdaterDelegate.appcastURLString` should be `private` and tested via the public `feedURLString(for:)` path.** Will require a small refactor in the existing test.
7. **Nit: `displayModeDescriptor(for:)` as `private static func` on `DisplayModeDescriptor` or `ConnectedDisplay`.**
8. **Nit: `scheduledAutomation` should be cancelled in `deinit`** (or held by an `AsyncStream` actor) so a long-running apply does not outlive the model during a unit test teardown.

---

**Final verdict: PASS with concerns.** All 3 P0 findings are fixed. All 10 P1 findings are fixed. All 7 P2 cleanup items are addressed. All packaging nits are addressed. 44/44 tests pass with no over-mocking, no broken assertions, and no test that asserts nothing meaningful. The concerns are all items the v2 spec explicitly deferred to v3; none are regressions, none block the v2 acceptance, and the secret scan is clean. Slice 10 (manual external-display verification) is the only remaining v2 acceptance gap and is out of scope for this review.
