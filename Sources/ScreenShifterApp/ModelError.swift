import Foundation

/// Errors surfaced by `ScreenShifterModel` to SwiftUI views.
///
/// The model publishes the current error; views render a system-red message for
/// any non-nil error and clear it on success. Each case carries enough context
/// to build a user-facing message without needing a stringly-typed payload.
enum ModelError: Equatable, Sendable {
    /// `IOPMAssertionCreateWithName` failed or another sleep-assertion error.
    case sleepAssertionFailed

    /// The saved mode is no longer listed in the display's mode set.
    case modeUnavailable(display: String)

    /// `SMAppService.mainApp.register()` / `unregister()` failed.
    /// `reason` is a human-readable summary of the failure direction.
    case launchAtLoginFailed(reason: String)

    /// The local log store rejected an append, clear, or read.
    case logWriteFailed

    /// Capturing settings for a display failed unexpectedly.
    case captureFailed(display: String)

    /// The target display disconnected between `startCapture` and `completeCapture`.
    case displayNoLongerAvailable(display: String)

    /// `modeApplier.reset(_:)` threw.
    case resetFailed(display: String)

    /// `modeApplier.apply(_:to:)` threw for one or more displays.
    /// `displays` is the joined list of display names.
    case applyFailed(displays: [String])

    /// The system settings URL failed to open.
    case systemSettingsUnavailable

    /// `updateChecker.checkForUpdates()` returned false.
    case updateCheckFailed

    /// `inventory.connectedDisplays()` threw.
    case inventoryReadFailed
}

extension ModelError {
    /// User-facing text rendered in the Settings window error section.
    var message: String {
        switch self {
        case .sleepAssertionFailed:
            return "Could not change the external-display sleep setting."
        case .modeUnavailable(let display):
            return "Saved mode for \(display) is no longer available on this display."
        case .launchAtLoginFailed(let reason):
            return reason
        case .logWriteFailed:
            return "Could not access the local log."
        case .captureFailed(let display):
            return "Could not capture settings for \(display)."
        case .displayNoLongerAvailable(let display):
            return "Could not capture \(display); the display is no longer available."
        case .resetFailed(let display):
            return "Could not reset \(display) to the system default."
        case .applyFailed(let displays):
            return "Could not apply profiles for: \(displays.joined(separator: ", "))."
        case .systemSettingsUnavailable:
            return "Could not open System Settings."
        case .updateCheckFailed:
            return "Could not start the update check."
        case .inventoryReadFailed:
            return "Could not read connected displays."
        }
    }
}
