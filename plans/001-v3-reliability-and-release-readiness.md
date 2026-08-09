# Plan 001: Make automatic restoration reliable and release-ready

> **Executor instructions**: Follow this plan in order. Run each verification
> command before moving on. If a STOP condition occurs, stop and report it;
> do not broaden the change. When complete, update the status row for plan
> 001 in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 7865579..HEAD -- Sources/DisplayCore/SystemDisplayInventory.swift Sources/ScreenShifterApp/ScreenShifterApp.swift Sources/ScreenShifterApp/ScreenShifterModel.swift Tests docs/verification plans`
> If any in-scope source has changed, compare it with the excerpts below. A
> material mismatch is a STOP condition.

## Status

- **Priority**: P1
- **Effort**: L (one to two focused days plus a real-monitor session)
- **Risk**: MED. The plan changes the startup, reset, and mode-selection paths
  of a utility that changes display modes.
- **Depends on**: none
- **Category**: bug, tests, docs
- **Planned at**: commit `7865579`, 2026-08-08

## Why this matters

Screen Shifter promises quiet automatic restoration after a user has captured
a known display. Today the model can receive a display-change notification
before it has loaded persisted profiles, so its automatic path applies nothing.
A transient inventory error during Reset is also treated as a disconnect and
deletes the profile without resetting the display. The mode selector does not
implement the refresh-rate fallback committed in the v2 architecture spec.

The app must retain its safety principle: unknown displays are unchanged,
manual capture remains per-display, and no regular test changes a real display
mode. Finish with manual verification on a real external display; without that
record a release remains blocked.

## Current state

- `Sources/ScreenShifterApp/ScreenShifterApp.swift` owns production wiring.
  It creates the model in `ScreenShifterApp.init` (lines 12-28), but the only
  call to `refresh()` is a `.task` attached to the Quit button in
  `MenuBarContent` (lines 42-58):

  ```swift
  _model = StateObject(wrappedValue: ScreenShifterModel(...))
  // ...
  Button("Quit") { NSApplication.shared.terminate(nil) }
      .task { await model.refresh() }
  ```

- `Sources/ScreenShifterApp/ScreenShifterModel.swift` registers display
  observers in `init` (lines 153-178), but loads persisted profiles only in
  `refresh()` (lines 184-195). `applySavedSetup` builds its lookup solely from
  the in-memory `savedProfiles` cache (lines 324-328).
- In `confirmReset()` at lines 262-296, this expression collapses an inventory
  error into an empty list:

  ```swift
  let currentDisplays = (try? inventory.connectedDisplays()) ?? []
  ```

  The following code then removes the profile and reports a disconnect.
- `Sources/DisplayCore/SystemDisplayInventory.swift` reads the raw CoreGraphics
  refresh rate (lines 48-62) and `ProfileModeSelector` filters candidate modes
  using exact `Double` equality (lines 65-92). It has no fallback candidate
  when the saved rate is absent. The v2 decision requires rounding to 0.01 Hz
  and falling back to the current rate while retaining logical size and HiDPI
  matching (`docs/specs/screen-shifter-v2-architecture.md:35-36,92`).
- The same descriptor marks a mode HiDPI when either pixel dimension exceeds
  the logical dimension (line 60). This misclassifies stretched non-HiDPI
  modes; both dimensions must indicate backing-scale enlargement.
- `applySavedSetup(isAutomatic: true)` sets `cooldownUntil` before its
  inventory read (model lines 299-322), so a failed read suppresses the next
  valid automatic trigger for roughly three seconds.
- The product brief requires successful automatic application to be visible in
  the menu bar and local log (`docs/project-brief.md:27`). The menu currently
  contains only Settings and Quit; automatic success records only the generic
  log message `Automatic apply completed.`
- `docs/verification/2026-08-08-external-display.md` does not exist. The v2
  review identifies it as the remaining release gate.

### Conventions to preserve

- Keep model behaviour on `@MainActor`, inject `DisplayInventorying` and
  `DisplayModeApplying`, and use the existing fake implementations from
  `Tests/ScreenShifterAppTests/DisplayCoreFakes.swift`.
- Use `ModelError` for user-facing failures and keep error-only notifications.
  Do not add runtime dependencies, shell calls, private display APIs, or
  displayplacer.
- Retain SwiftUI system controls and the quiet menu-bar UX in `DESIGN.md`.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Build | `swift build` | exit 0 |
| Tests | `swift test` | all tests pass |
| Secret scan | `/Users/eugene/Yandex.Disk.localized/agent-foundation/scripts/check-secrets.sh --repository .` | `FOUNDATION_SECRET_SCAN=pass` |
| Package check | `./scripts/package-dmg.sh` | creates a DMG under `.build/package/` on a suitably configured Mac |

Run the package command only on a release-capable Mac. It writes ignored build
artifacts and is not a replacement for the real-monitor checks below.

## Scope

**In scope**:

- `Sources/ScreenShifterApp/ScreenShifterApp.swift`
- `Sources/ScreenShifterApp/ScreenShifterModel.swift`
- `Sources/DisplayCore/SystemDisplayInventory.swift`
- focused tests under `Tests/ScreenShifterAppTests/` and
  `Tests/DisplayCoreTests/`
- `docs/verification/2026-08-08-external-display.md` (create only after the
  real hardware checks)
- `plans/README.md`

**Out of scope**:

- Display arrangement, brightness, HDR, rotation, wallpapers, accounts,
  analytics, network services, or displayplacer integration.
- Refactoring `ScreenShifterModel` into separate coordinators or stores.
- Changing the persisted profile format beyond canonicalizing the existing
  `refreshRate` value in a backward-compatible way.
- Release publication, GitHub tags, notarization, or Sparkle key changes.

## Git workflow

- Branch: `codex/001-reliability-release-readiness`.
- Make logical commits with the repository's conventional style, for example
  `fix(model): load profiles before automatic restoration`.
- Do not push, open a pull request, tag, or publish a release unless the
  operator explicitly authorizes it outside this plan.

## Steps

### Step 1: Load durable state before observers can use it

Add an idempotent `bootstrap()` method on `ScreenShifterModel` that loads
profiles, inventory, and logs without requiring the menu to be opened. In
`ScreenShifterApp.init`, construct the model in a local constant, assign it to
`StateObject`, then start `Task { @MainActor in await model.bootstrap() }`.
Remove the `.task { await model.refresh() }` modifier from the Quit button;
opening the menu may still call `refresh()` later, but must not be the only
startup trigger.

Because observers are registered synchronously in model initialization while
profile loading is asynchronous, add an explicit bootstrap gate. A display
notification received before bootstrap completes must set a pending-topology
flag rather than apply an empty cache. After loading profiles and the initial
inventory, `bootstrap()` must process that pending notification once. Keep
`applySavedSetup` cache-based; the fix is to hydrate that cache before
automatic notifications are handled, not to re-read `UserDefaults` on every
topology event.

Add a model-level regression test that creates a model with a pre-populated
`InMemoryProfileStore`, does not call the menu-view refresh path, triggers the
automatic topology flow, and proves the fake applier receives the known
profile. Add an `automationDelayNanoseconds` initializer parameter with the
current two-second value as its production default and pass `0` from tests,
rather than adding another real-time wait.

**Verify**: `swift test --filter ScreenShifterModelTests` → all model tests
pass, including the new cold-start automatic-restoration regression.

### Step 2: Preserve a profile when inventory cannot be read during Reset

Replace the `try? ... ?? []` collapse in `confirmReset()` with explicit error
handling. A successful inventory read that does not contain the display still
means a disconnect: remove the saved profile and show the existing
disconnect-specific message. An inventory failure is neither evidence of a
disconnect nor permission to remove state: preserve the profile, clear the
pending confirmation state appropriately, set `.inventoryReadFailed`, and log
the error through the existing `record` path.

Add a fake-inventory test that first allows `prepareReset`, then throws during
`confirmReset`. Assert that no reset call occurs, the store still contains the
profile, and the model exposes `.inventoryReadFailed`.

**Verify**: `swift test --filter ScreenShifterModelTests` → all model tests
pass, including disconnected-display and inventory-failure Reset cases.

### Step 3: Implement the documented refresh-rate selection policy

Centralize refresh-rate canonicalization in `DisplayCore`: round finite
CoreGraphics rates to 0.01 Hz at descriptor creation and canonicalize the
profile-side comparison equivalently. Preserve `0` as the legacy sentinel that
means any rate is acceptable.

Change `ProfileModeSelector.matchingMode` to accept
`currentMode: DisplayModeDescriptor?` and pass `display.currentMode` from
`DisplayApplicationPlanner`. First prefer candidates matching logical size,
HiDPI state, and saved canonical rate. If none exists, fall back to candidates
matching logical size and HiDPI state, preferring the canonical refresh rate of
`currentMode`; if that is absent, use the first compatible candidate. Apply the
existing maximum-physical-resolution selection after either filtering pass for
external displays. Do not change the public requirement that external displays
use their maximum physical resolution.

Add pure selector tests for: rounded equivalent rates, an unavailable saved
rate falling back to a compatible candidate, legacy zero rate, and external
maximum-resolution selection after fallback. Update or add profile decoding
coverage only if canonicalization affects persisted values.

**Verify**: `swift test --filter ProfileModeSelectorTests` → all selector
tests pass; `swift test` → all tests pass.

### Step 4: Correct HiDPI classification and cooldown ordering

Classify a mode as HiDPI only when both pixel dimensions are greater than their
logical counterparts. Add a pure test for a stretched mode with only one larger
dimension and a normal two-dimension HiDPI mode.

Move the automatic cooldown assignment until after `inventory.connectedDisplays()`
has succeeded. Preserve the existing three-second value and existing
pause/wake checks. Add a deterministic model test showing that a failed
inventory read does not leave a subsequent automatic attempt in cooldown.

**Verify**: `swift test --filter DisplayCoreTests` → all DisplayCore tests
pass; `swift test --filter ScreenShifterModelTests` → all model tests pass.

### Step 5: Surface automatic success quietly in the menu bar

Add a concise, non-notifying menu-bar status derived from model state, such as
the last automatic result and timestamp or a neutral "Automation active"
status immediately after a successful automatic run. It must not reintroduce
the removed manual Apply or bulk Capture menu actions, prompts, dashboards, or
custom styling. Keep the local log as the detailed history.

Add a focused presentation/model test for the success state and retain the
existing error-only notification rule. Test that manual success and automatic
success remain distinguishable if the UI needs different copy.

**Verify**: `swift test --filter ScreenShifterModelTests` → all app-model
tests pass; `swift build` → exit 0.

### Step 6: Record real external-display acceptance evidence

On a MacBook with a known external monitor, create
`docs/verification/2026-08-08-external-display.md`. Record only non-sensitive
facts: macOS version, monitor model, captured logical/physical mode, manual
apply result, Reset result, disconnect-all MacBook fallback, reconnect result,
and whether unknown displays stayed unchanged. Include the exact build commit
and test/secret-scan result. Do not include serial numbers, account data,
keys, or local absolute paths.

If any expected behaviour differs, stop and report the observable result with
the reproduction conditions. Do not weaken assertions or mark the release gate
complete based on unit tests alone.

**Verify**: the new record has every field above and the monitor checks pass;
then run `swift build`, `swift test`, and the secret-scan command from the
table.

## Test plan

- Model: cold start with saved profiles, Reset inventory failure, failed
  inventory not arming cooldown, and automatic-success status.
- DisplayCore: refresh-rate normalization, exact-rate preference, compatible
  fallback, legacy zero rate, maximum-physical-resolution fallback, and the
  stretched-mode HiDPI edge case.
- Follow `Tests/ScreenShifterAppTests/ScreenShifterModelTests.swift` and
  `Tests/DisplayCoreTests/ProfileModeSelectorTests.swift` for fixture style.
- No regular test may call `CGDisplaySetDisplayMode` on real hardware.

## Done criteria

- [ ] Saved profiles are hydrated before an automatic notification can apply
  an empty cache.
- [ ] Reset preserves the profile when inventory reading fails.
- [ ] Mode selection implements 0.01-Hz canonicalization and compatible-rate
  fallback, while legacy zero-rate profiles remain valid.
- [ ] Stretched non-HiDPI modes are not classified as HiDPI.
- [ ] An inventory failure does not consume automatic cooldown.
- [ ] Successful automatic operation has quiet menu-bar visibility and remains
  detailed in the local log.
- [ ] `docs/verification/2026-08-08-external-display.md` records successful
  real-monitor acceptance, or the plan is marked BLOCKED with the observed
  failure.
- [ ] `swift build` and `swift test` exit 0.
- [ ] Foundation secret scan prints `FOUNDATION_SECRET_SCAN=pass`.
- [ ] No out-of-scope files are modified; `plans/README.md` is updated.

## STOP conditions

- The app lifecycle cannot guarantee bootstrap completion before display
  observers without adding an out-of-scope architectural dependency.
- A compatible refresh-rate fallback would select a display mode with a
  different logical size, HiDPI state, or lower-than-maximum physical
  resolution for an external display.
- The real-monitor test shows `CGDisplaySetDisplayMode` is unavailable or
  unreliable for the intended scaling mode.
- Any test requires changing a real display mode in regular CI.
- The current source differs materially from the excerpts above.

## Maintenance notes

- Keep profile cache hydration explicit whenever app startup or model ownership
  changes; an observer-first lifecycle can silently disable automation.
- Review mode-selection changes against real monitors with multiple refresh
  rates. The fallback is a resilience policy, not permission to change the
  user's scaling intent.
- If `ScreenShifterModel` is later split, preserve the tested boundaries:
  bootstrap ordering, reset error semantics, and automatic status reporting.
