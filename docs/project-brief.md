# Screen Shifter

## Objective

Build a native macOS menu bar application that captures and automatically restores a display scaling profile for the built-in MacBook display and each known external display. The app must work locally without accounts, network access, analytics, or LLM APIs.

## Classification

- Scope: Personal
- Source mode: files

## Known facts

- Target platform: macOS 14 Sonoma or newer; Apple Silicon is required and Universal Binary is desirable.
- UI: Swift and SwiftUI, with AppKit and CoreGraphics where needed; the Dock icon is hidden by default and Settings always remains available from the menu bar.
- The MVP manages scaling only. It does not manage display arrangement, primary display, rotation, refresh rate, HDR, color profile, brightness, or wallpaper.
- Every external display must use its maximum physical resolution. The saved setting is its logical resolution and HiDPI state, which define the visible size of UI elements.
- The built-in MacBook display has its own profile and may use a saved scaling mode.
- Identify an external display by vendor ID, product ID, and serial number when available. Fall back to vendor ID, product ID, display name, and stable characteristics when serial is unavailable.
- Profiles are independent per physical display. With multiple external displays, the app applies each known display profile independently.
- On first detection of an unknown display, do not change scaling. After the user configures macOS display settings and confirms Capture Current Setup, save profiles for all currently connected displays.
- Capture Current Setup shows the profiles to be updated and asks for confirmation before overwrite.
- After a profile is configured, automatically apply it about two seconds after a matching display configuration change.
- When no external displays remain connected, automatically apply the saved MacBook profile.
- Reset to Default for a display removes its saved profile and immediately restores the system default scaling for that display.
- Launch at Login is enabled after onboarding and can be disabled in Settings. Pause Automation persists across restarts and does not block manual application.
- Notify the user only about errors. Successful automatic application is visible in the menu bar and local log.
- Store configuration locally using UserDefaults or JSON. Include a local log viewer with Copy Logs, Clear Logs, and Open Log File.
- Prevent reapplication loops with a 1-2 second debounce, an approximately 3-second cooldown, current-mode comparison, and wake-state protection.
- Use an internal DisplayCore module based on displayplacer logic. Do not require Homebrew, displayplacer, Terminal commands, or any third-party app at runtime. Preserve upstream MIT license and attribution if code is incorporated.
- Distribute directly as a DMG, not through the Mac App Store. The app requires no internet connection to operate.

## Initial acceptance

1. The app discovers connected built-in and external displays and resolves stable identities for external displays.
2. The app captures scaling for all connected displays only after user confirmation and persists one profile per display.
3. Known profiles are restored automatically after a settled display change; unknown displays are never changed automatically.
4. Every external display uses maximum physical resolution while its saved scaling mode is applied.
5. The saved MacBook profile is restored when all external displays disconnect.
6. The menu bar exposes Settings, Apply Saved Setup, Capture Current Setup, Pause Automation, Launch at Login, and Quit.
7. Settings supports profile inspection, a destructive Reset to Default with confirmation, error states, and local log viewing.
8. The product can be packaged as a direct-install DMG and has no runtime dependency on external applications or network services.

## Gaps

- The verified implementation path for changing scaling on macOS must be proven on a real macOS host. Public APIs alone do not guarantee this capability.
- The specific licensing and source-integration plan for displayplacer must be reviewed before copying any upstream code.
- A macOS host is required to build, sign, package, and test the native application and its display behavior.