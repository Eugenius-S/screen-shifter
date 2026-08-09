# v2 review — 2026-08-08 (Wave 1 / self)

## Verdict

**PASS with concerns** — 11 v2 commits land all P0/P1 fixes and the
in-scope P2 items; the only remaining gap is hardware-gated slice 10
(manual external-display verification). Concerns are small and listed
under "New issues introduced" — none block a release tag once slice 10
records PASS.

## Scope

- Range: `d47a433..HEAD` (11 commits, 1520 insertions / 681 deletions across 26 files)
- Test suite at HEAD: **44/44 passing** (24 original + 20 new: 7 in slice 2, 5 in slice 5, 3 in slice 6, 5 in slice 8)
- Preflight: pass; secret scan: pass
- Working tree: clean; branch `feature/issue-1-screen-shifter-mvp` in sync with origin (11 ahead of `9e23fd9`)

## P0 / P1 audit findings

| # | Status | Evidence |
|---|---|---|
| P0-A | PASS | `Sources/DisplayCore/SystemDisplayInventory.swift:10-12` — `displayModeOptions()` returns `[kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary`; passed at `:282` and `:353`. |
| P0-B | PASS | `setActivationPolicy` removed from `ScreenShifterApp.swift` and `scripts/package-dmg.sh` (grep returns no matches). `Info.plist` writes `<key>LSUIElement</key><true/>`. |
| P0-C | PASS | `docs/project-brief.md:40` criterion 6 now states the menu bar exposes Settings and Quit; links to next-design. Per-display capture language replaces the bulk "Capture Current Setup" lines. |
| P1-1, 2, 3 | PASS | `ScreenShifterApp.swift` uses `Settings { SettingsView(model: model) }` scene; `MenuBarContent` uses `@Environment(\.openSettings)` and a single Button + Quit. `SettingsWindowController`, `prepareCapture` / `confirmCapture`, the bulk-capture alert, and the duplicate reset alert are gone. |
| P1-4 | PASS | `DisplayProfile.refreshRate: Double = 0` with custom `init(from:)` (`ScreenShifterDomain.swift:57-64`) that uses `decodeIfPresent` ?? 0 for backward compat. `ProfileModeSelector.matchingMode` filters by `profile.refreshRate == 0 \|\| mode.refreshRate == profile.refreshRate`. |
| P1-5 | PASS | `ScreenShifterModel.init` lines 175-177: `if keepExternalDisplayAwake { _ = sleepAssertion.update(isEnabled: true) }`. |
| P1-6 | PASS | `ScreenShifterModel.confirmReset` (lines 256-313) re-reads inventory, gates `modeApplier.reset(_:)` on `stillConnected`, removes the saved profile either way, and surfaces different `captureMessage` for "reset succeeded" vs "disconnected". |
| P1-7 | PASS | `errorMessage: ModelError?` (line 122). New `ModelError` enum in `Sources/ScreenShifterApp/ModelError.swift` with 11 cases. User-action methods clear `errorMessage` on success (`completeCapture`, `confirmReset`, `applySavedSetup`, `clearLogs`, `setLaunchAtLogin`, `checkForUpdates`, `openSystemSettings`). Internal helpers (`refreshLogs`, `record`) only set on failure so they do not clobber a calling user action's just-set error. `updateSleepAssertion` clear-check is now `if errorMessage == .sleepAssertionFailed`. |
| P1-8 | PASS | `applySavedSetup` (line 325) uses `savedProfiles.map` instead of `await profileStore.profiles()`. |
| P1-9 | PASS | `Tests/DisplayCoreTests/SystemDisplayModeApplierTests.swift:9` wraps the only hardware-dependent test in `#if DEBUG && !CI`. The other formerly-hardware test (main display identity in `SystemDisplayInventoryTests`) uses the `FakeDisplayInventory` introduced in slice 2. |
| P1-10 | PASS | `Sources/DisplayCore/DisplayCoreProtocols.swift` defines `DisplayInventorying` (line 6), `DisplayModeApplying` (line 11), `MainDisplayIDProviding` (line 17). `ScreenShifterModel.init` (line 156) takes `mainDisplayIDProvider: MainDisplayIDProviding` and stores it as `let` for read access. `ScreenShifterApp` wires production implementations. |

## P2 cleanup (slices 8-9)

| # | Status | Evidence |
|---|---|---|
| P2-1 | PASS | `LocalLogStore.append` (line 230) — `defer { try? handle.close() }` after `FileHandle(forWritingTo:)`. |
| P2-2 | PASS | `nonisolated(unsafe) static let iso8601: ISO8601DateFormatter` (line 183). Built once, thread-safe for `string(from:)` reads. |
| P2-8 | PASS | `maxLogBytes: UInt64 = 1_048_576` constant; `init` accepts a custom cap (line 200); `append` drops the old file when `size > maxLogBytes` (line 217-220). `LocalLogStoreTests.testRotatesWhenFileExceedsMaxBytes` exercises this with `maxLogBytes: 50`. |
| P2-9 | PASS | `decodedProfiles` uses `do/catch` and calls `logProfileStoreError` (line 157). `save` / `remove` also use `do/catch` and log encode failures (lines 121, 133). `UserDefaultsProfileStoreTests.testCorruptedPayloadReturnsEmptyProfiles` verifies a corrupt payload returns `[:]`. |
| P2-11 | PASS | `SystemDisplayInventory.connectedDisplays` builds `screenMap()` once (line 322) and threads it through `snapshot(for:screenByID:)` (line 333) for O(1) lookups. |
| P2-7 | PASS | Tests split: 9 new per-type files in `DisplayCoreTests/`, 4 new per-type files in `ScreenShifterDomainTests/`. `SystemDisplayInventoryTests.swift` shrank from 462 to 25 lines; `DisplayIdentityTests.swift` from 120 to 21 lines. |
| P2-12 | PASS (already done in slice 2) | `Sources/ScreenShifterApp/ScreenShifterApp.swift` has no `import CoreGraphics`; both `mainDisplayIDProvider.mainDisplayID` call sites in `SettingsView.body` and `synchronizeExpandedDisplay` go through the protocol. |
| packaging XML escape | PASS | `plist_escape()` in `scripts/package-dmg.sh:39` applied to `bundle_identifier`, `version` (×2), `sparkle_feed_url`, `sparkle_public_ed_key`. Unit-tested with three scenarios before commit. `plutil -lint` accepts the produced plist. |
| packaging sign array | PASS | `sign_options=()` initialised; `sign_options=(--options runtime --timestamp)` when the identity is not `-`; expanded with `"${sign_options[@]}"`. |

## New issues introduced

1. **P2 / nit — `LocalLogStoreTests` does not clean up the temp file in `testRotatesWhenFileExceedsMaxBytes`.** The test writes to a UUID-based file but has no `defer { try? FileManager.default.removeItem(at: logURL) }` (the first test does, the new one does not). Effect: a 200-byte file per run leaks into `FileManager.default.temporaryDirectory`. Not blocking; should be added when the next test pass touches this file.

2. **P2 / nit — `setLaunchAtLogin` failure path does not propagate the underlying `NSError`.** The audit (P2-17) called this out. v2 ships a typed `ModelError.launchAtLoginFailed(reason:)` that includes only the human direction ("Could not enable / disable Launch at Login.") and discards the underlying `SMAppServiceError`. Acceptable for an MVP because the surface API does not give us more, but a follow-up should consider a `launchAtLoginError(NSError)` case for diagnostics.

3. **P2 / nit — `cooldownUntil` is still set before the inventory read inside `applySavedSetup(isAutomatic: true)`.** Audit P2-15. The v2 spec scoped slice 6 to P1-5/6/8; this is intentionally deferred. If a throw from `inventory.connectedDisplays()` happens after the cooldown is armed, the next legitimate trigger is blocked for 3 s. Tracked in the v3 backlog.

4. **P2 / nit — `Picker("Built-in display", selection: .constant(...))` is still in `SettingsView`.** Audit nit. v2 spec does not scope this; deferred.

5. **P2 / nit — `scheduledAutomation` Task is not cancelled in `deinit`.** Audit nit. Leak only at process exit; deferred.

6. **Nit — `keepExternalDisplayAwake`'s optimistic assertion in `init` is "always-on" if the user previously had it on, even if the laptop currently has no external display.** The first `refresh()` releases it (line 521 `updateSleepAssertion` → `ExternalDisplaySleepPolicy.shouldPreventSystemSleep(isEnabled: true, displays: [])` returns false). The window between `init` and the first `refresh()` is small (sub-second on a normal Mac) but exists. Acceptable per the v2 spec decision 8; documented for awareness.

7. **Nit — `ModelError` has 11 cases; some (`modeUnavailable`, `displayNoLongerAvailable`) are defined but not surfaced by the current `applySavedSetup` / `completeCapture` paths.** They are forward-looking placeholders. No test exercises `modeUnavailable`. Acceptable; flagged for v3 to wire or prune.

## Test quality

- 20 new tests across slices 2, 5, 6, 8. All assert meaningful invariants:
  - `testApplySavedSetupUsesCachedProfilesInsteadOfReReadingStore` (slice 6) — explicit cache vs re-read proof.
  - `testConfirmResetRemovesProfileWhenDisplayDisconnected` (slice 6) — disconnect path.
  - `testConfirmResetSurfacesResetErrorWhenApplierThrows` (slice 6) — typed error path.
  - `testModelErrorMessageRendersUserFacingText` (slice 5) — message property.
  - `testClearLogsClearsErrorOnSuccess` (slice 5) — clear-on-success.
  - `testLocalLogStoreRotatesWhenFileExceedsMaxBytes` (slice 8) — uses a small `maxLogBytes: 50` cap to exercise rotation cheaply.
  - `testUserDefaultsProfileStoreTests.testCorruptedPayloadReturnsEmptyProfiles` (slice 8) — corruption tolerance.
  - `testDisplayProfileTests.testDecodesBackwardCompatibleWithoutRefreshRateField` (slice 8) — schema migration.
  - Protocol-fake tests in slice 2 use the new fakes; no over-mocking (fakes only stub the protocol surface, not the SUT internals).
- No `XCTAssertTrue(true)`, no empty test bodies, no `// TODO` placeholders in tests.
- Hardware-dependent test in `SystemDisplayModeApplierTests` is correctly gated by `#if DEBUG && !CI`.

## Foundation v1 compliance

- `check-project-preflight.sh --project-root <repo> --config-root $HOME/.agent-foundation --profile personal` → all six categories pass on HEAD.
- `check-secrets.sh --repository . --staged` → pass.
- No edits to `agent-foundation` (verified by `git log agent-foundation` shows no new commits this session).
- `AGENTS.md`, `project-sources.yml`, `.foundation/project.yml`, `.gitignore` unchanged from v1 template.
- No third-party dependencies added.

## Open items

- **Slice 10: manual external-display verification.** Requires physical Mac + external monitor. Will be recorded as `docs/verification/2026-08-08-external-display.md` per the v2 spec acceptance criterion 6. Blocked on hardware.
- The above seven "new issues" are all P2 / nit and are non-blocking; tracked for v3 backlog.

## Recommendations for v3

The v2 work surfaces natural v3 candidates:

1. **Slice 11 candidate: `applySavedSetup` should not arm `cooldownUntil` before the inventory read** (nit #3). Atomic guard so a throw does not block the next legitimate trigger.
2. **Slice 12 candidate: launch-at-login error propagation** (nit #2). Surface the underlying `NSError` for diagnostics.
3. **Slice 13 candidate: prune / wire the `ModelError.modeUnavailable` case** (nit #7). It is defined but unused; either delete or wire to `.unavailable` outcomes in `applySavedSetup`.
4. **Slice 14 candidate: temp-file cleanup in `LocalLogStoreTests.testRotatesWhenFileExceedsMaxBytes`** (nit #1). Trivial.
5. **Out-of-v2-spec audit items** that v2 explicitly defers: P2-13 (split `ScreenShifterModel` into focused collaborators), P2-15 (cooldownUntil ordering — same as #1), P2-16 (`.requiresApproval` distinction in `SMAppService.mainApp.status`), P2-17 (NSError detail — same as #2), nit (Picker with `.constant`), nit (`@preconcurrency import AppKit`), nit (`suiteName` flatMap), nit (`scheduledAutomation` deinit cancel), nit (`SparkleUpdaterDelegate.appcastURLString` public), nit (`displayModeDescriptor` free func), P2-6 (isHiDPI uses OR).
6. **v3a — granular Display Mode** (already-agreed v3 staged sub-project from the earlier session). v2 work is the natural v3a foundation; no spec work needed before v2 ships.

## Verdict token

`v2-review-wave1: PASS with concerns — 7 P2/nit follow-ups; 0 blockers; 44/44 tests green; preflight + secret scan pass; release tag gated on slice 10 (hardware).`
