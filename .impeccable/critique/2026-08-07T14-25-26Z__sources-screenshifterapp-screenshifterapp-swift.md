---
target: Settings window
total_score: 30
p0_count: 0
p1_count: 3
timestamp: 2026-08-07T14-25-26Z
slug: sources-screenshifterapp-screenshifterapp-swift
---
#### Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 3 | Capture status, messages, and errors are visible, but asynchronous work has no progress treatment. |
| 2 | Match System / Real World | 4 | Terminology and native macOS controls fit the display-settings task. |
| 3 | User Control and Freedom | 3 | Reset has confirmation and cancellation, but capture has no visible cancel path. |
| 4 | Consistency and Standards | 3 | The surface follows macOS conventions, but action and state presentation are uneven inside display sections. |
| 5 | Error Prevention | 4 | Completion and reset are constrained, and destructive reset is confirmed. |
| 6 | Recognition Rather Than Recall | 3 | Status labels are visible, but the capture sequence and primary action are not strongly signposted. |
| 7 | Flexibility and Efficiency of Use | 2 | The workflow requires several navigation actions and exposes no visible automation pause control. |
| 8 | Aesthetic and Minimalist Design | 3 | The grouped Form is restrained, but the settings surface gives maintenance controls similar weight to the capture task. |
| 9 | Error Recovery | 3 | Errors are plain and logged, but the UI does not provide a nearby retry or recovery action. |
| 10 | Help and Documentation | 2 | Supporting copy exists, but capture, HiDPI, and persistence behavior are not explained in context. |
| **Total** | | **30/40** | **Good foundation; address weak workflow hierarchy and state clarity.** |

#### Anti-Patterns Verdict

**Start here.** Does this look AI-generated?

**LLM assessment**: No. The interface is recognizably native macOS and avoids decorative gradients, custom cards, invented controls, and visual over-styling. Its weakness is not AI slop; it is an under-signposted workflow inside an otherwise conventional settings form.

**Deterministic scan**: The Impeccable detector returned zero findings for `Sources/ScreenShifterApp/ScreenShifterApp.swift`. The detector is markup-oriented, so this clean result is limited evidence for a native SwiftUI source file.

**Visual overlays**: Not available. Browser inspection and overlay injection were skipped because the target is a native SwiftUI/AppKit source file with no HTML page or dev-server URL.

#### Overall Impression

The Settings window has a solid native foundation and sensible safety states. The biggest opportunity is to make display capture read as a deliberate sequence rather than a flat list of seven equally weighted buttons, while keeping logs, power, login, and updates visibly secondary.

#### What's Working

- Native SwiftUI controls and `Form(.grouped)` make the screen immediately legible to macOS users.
- `Complete capture` and `Reset default` are correctly constrained by state, reducing accidental actions.
- Confirmation copy for reset and profile replacement names the affected display and the consequence.

#### Priority Issues

- **[P1] Capture actions have no clear hierarchy**
  - **Why it matters**: `Start capture settings`, four System Settings navigation buttons, `Complete capture`, and `Reset default` appear as one flat action list. A first-time user must infer the sequence and which settings actually persist.
  - **Fix**: Present capture as a staged flow with one prominent start action, a grouped adjustment area, and a clearly emphasized completion action; keep reset visually separate and destructive.
  - **Suggested command**: `$impeccable layout Settings display capture section`

- **[P1] Capture status icon can contradict the status text**
  - **Why it matters**: The text switches on `captureState`, but the icon switches only on `hasSavedProfile`. During capture, a display with an existing profile can show a saved checkmark beside `Capture in progress`; the icon does not describe the current state.
  - **Fix**: Resolve the icon from the same capture-state enum as the status text, with distinct capturing and completed treatments.
  - **Suggested command**: `$impeccable polish DisplayCaptureSection`

- **[P1] Automation pause is not discoverable in the Settings surface**
  - **Why it matters**: `ScreenShifterModel` persists `automationPaused`, and the product brief promises a Pause Automation control, but `SettingsView` exposes no toggle or menu action. Users cannot discover or control a safety switch that affects automatic restoration.
  - **Fix**: Add one visible Pause Automation control in the automation settings area and distinguish its paused state from ordinary display status.
  - **Suggested command**: `$impeccable harden automation settings`

- **[P2] Primary workflow and maintenance controls share one undifferentiated form**
  - **Why it matters**: Display capture is followed by log management, Login at Launch, power assertions, and update checking in the same vertical flow. This increases scanning cost and weakens the quiet background-utility character.
  - **Fix**: Group maintenance controls under named secondary sections and keep the display capture workflow as the first, visually dominant task.
  - **Suggested command**: `$impeccable layout Settings window`

#### Persona Red Flags

**Alex (Power User)**: The display section presents seven actions without a clear accelerator or primary path. Repeatedly opening System Settings for Display scaling, HiDPI mode, Font size, and Dock size creates a slow context-switch loop.

**Jordan (First-Timer)**: `Start capture settings` and `Complete capture` imply a sequence, but the UI does not number or group the steps. The user has to infer that only the display scaling and HiDPI state are captured while Font size and Dock size are navigation shortcuts.

**Morgan (Multi-display User)**: External displays are selected through a single picker, while only one external display section is shown at a time. The user must remember which display is selected while comparing or configuring multiple monitors.

#### Minor Observations

- `Launch at Login` is placed in an unlabelled Section, unlike the named `Power` section.
- The `Log` disclosure contains a read-only editor with no empty-state copy when no entries exist.
- `Check for updates` reports success through the shared capture message area, which can make unrelated status feedback feel coupled to display capture.
- The settings window uses a fixed 420-point width, so long display names and localized labels need a macOS localization pass.

#### Questions to Consider

- What if each display section had one explicit "Record this display" flow instead of a flat action list?
- Should Font size and Dock size remain inside the capture workflow when they are not persisted as display-profile data?
- Where should a user look first when automatic restoration is paused: the menu bar, the Settings window, or both?
