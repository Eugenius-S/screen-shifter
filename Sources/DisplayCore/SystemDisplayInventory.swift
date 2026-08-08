import AppKit
import CoreGraphics
import Foundation
import ScreenShifterDomain

// CoreGraphics' CGDisplayCopyAllDisplayModes takes a CFDictionary of options.
// Passing nil omits scaled and HiDPI modes on macOS 14+, which made saved
// external profiles appear unavailable even when the physical mode exists.
// See P0-A in docs/audits/2026-08-08-code-audit.md.
private func displayModeOptions() -> CFDictionary {
    [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
}

public struct DisplayModeDescriptor: Codable, Equatable, Sendable {
    public let pixelWidth: UInt32
    public let pixelHeight: UInt32
    public let logicalWidth: UInt32
    public let logicalHeight: UInt32
    public let isHiDPI: Bool
    public let refreshRate: Double

    public init(
        pixelWidth: UInt32,
        pixelHeight: UInt32,
        logicalWidth: UInt32,
        logicalHeight: UInt32,
        isHiDPI: Bool,
        refreshRate: Double = 0
    ) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.logicalWidth = logicalWidth
        self.logicalHeight = logicalHeight
        self.isHiDPI = isHiDPI
        self.refreshRate = refreshRate
    }
}

public struct ConnectedDisplay: Equatable, Sendable {
    public let displayID: UInt32
    public let identity: DisplayIdentity
    public let name: String
    public let isBuiltIn: Bool
    public let currentMode: DisplayModeDescriptor?
    public let availableModes: [DisplayModeDescriptor]
}

private func displayModeDescriptor(for mode: CGDisplayMode) -> DisplayModeDescriptor {
    let logicalWidth = UInt32(mode.width)
    let logicalHeight = UInt32(mode.height)
    let pixelWidth = UInt32(mode.pixelWidth)
    let pixelHeight = UInt32(mode.pixelHeight)
    // Plan 001 step 3: canonicalize the rate to 0.01 Hz so floating-point
    // artefacts in CoreGraphics do not break the equality check used by
    // `SystemDisplayModeApplier.apply`.
    let refreshRate = RefreshRateCanonicalization.canonicalize(mode.refreshRate)

    return DisplayModeDescriptor(
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
        logicalWidth: logicalWidth,
        logicalHeight: logicalHeight,
        isHiDPI: pixelWidth > logicalWidth || pixelHeight > logicalHeight,
        refreshRate: refreshRate
    )
}

/// Plan 001 step 3: round a finite CoreGraphics refresh rate to the
/// nearest 0.01 Hz. Floating-point noise in the source value would
/// otherwise break equality between a freshly captured descriptor and a
/// previously persisted profile. 0 and non-finite values are returned
/// unchanged: 0 is the legacy "any rate" sentinel used by profiles that
/// pre-date the refresh-rate field, and non-finite values must never
/// compare equal to anything sensible.
public enum RefreshRateCanonicalization {
    public static func canonicalize(_ rate: Double) -> Double {
        guard rate.isFinite, rate > 0 else {
            return rate
        }
        return (rate * 100).rounded() / 100
    }
}

public enum ProfileModeSelector {
    public static func matchingMode(
        for profile: DisplayProfile,
        availableModes: [DisplayModeDescriptor],
        currentMode: DisplayModeDescriptor?,
        requiresMaximumPhysicalResolution: Bool
    ) -> DisplayModeDescriptor? {
        // Plan 001 step 3: canonicalize the saved rate here so profiles
        // persisted before the field existed, or with floating-point
        // noise from a previous capture, still match cleanly.
        let savedCanonicalRate = RefreshRateCanonicalization.canonicalize(profile.refreshRate)
        let acceptsAnyRate = savedCanonicalRate == 0

        // First pass: size + HiDPI + saved rate. The legacy 0 sentinel
        // skips the rate check entirely.
        let exactMatches = availableModes.filter { mode in
            matchesSizeAndHiDPI(mode, profile)
                && (acceptsAnyRate
                    || RefreshRateCanonicalization.canonicalize(mode.refreshRate) == savedCanonicalRate)
        }

        let chosenPool: [DisplayModeDescriptor]
        if exactMatches.isEmpty {
            chosenPool = fallbackCandidates(
                profile: profile,
                availableModes: availableModes,
                currentMode: currentMode
            )
        } else {
            chosenPool = exactMatches
        }

        guard !chosenPool.isEmpty else {
            return nil
        }

        if requiresMaximumPhysicalResolution {
            return chosenPool.max { leftMode, rightMode in
                let leftArea = UInt64(leftMode.pixelWidth) * UInt64(leftMode.pixelHeight)
                let rightArea = UInt64(rightMode.pixelWidth) * UInt64(rightMode.pixelHeight)
                if leftArea == rightArea {
                    return leftMode.pixelWidth < rightMode.pixelWidth
                }
                return leftArea < rightArea
            }
        }

        return chosenPool.first
    }

    private static func matchesSizeAndHiDPI(
        _ mode: DisplayModeDescriptor,
        _ profile: DisplayProfile
    ) -> Bool {
        mode.logicalWidth == profile.logicalWidth
            && mode.logicalHeight == profile.logicalHeight
            && mode.isHiDPI == profile.isHiDPI
    }

    /// Plan 001 step 3: when no candidate matches the saved rate, fall
    /// back to size+HiDPI candidates and prefer the one whose canonical
    /// rate matches the current display rate. Without a current mode, or
    /// when no candidate shares the current rate, return the whole
    /// compatible set so the caller can pick `first` or the
    /// max-resolution mode.
    private static func fallbackCandidates(
        profile: DisplayProfile,
        availableModes: [DisplayModeDescriptor],
        currentMode: DisplayModeDescriptor?
    ) -> [DisplayModeDescriptor] {
        let compatible = availableModes.filter { mode in
            matchesSizeAndHiDPI(mode, profile)
        }
        guard !compatible.isEmpty else {
            return []
        }

        guard let currentMode else {
            return compatible
        }

        let currentCanonicalRate = RefreshRateCanonicalization.canonicalize(currentMode.refreshRate)
        guard currentCanonicalRate > 0 else {
            return compatible
        }

        let rateMatches = compatible.filter { mode in
            RefreshRateCanonicalization.canonicalize(mode.refreshRate) == currentCanonicalRate
        }
        return rateMatches.isEmpty ? compatible : rateMatches
    }
}

public enum ProfileCapturePlanner {
    public static func profiles(for displays: [ConnectedDisplay]) -> [DisplayProfile] {
        displays.compactMap { display in
            guard let currentMode = display.currentMode else {
                return nil
            }

            return DisplayProfile(
                displayIdentity: display.identity,
                logicalWidth: currentMode.logicalWidth,
                logicalHeight: currentMode.logicalHeight,
                isHiDPI: currentMode.isHiDPI,
                refreshRate: currentMode.refreshRate
            )
        }
    }
}

public enum DisplayCaptureState: Equatable, Sendable {
    case idle
    case capturing
    case completed(DisplayProfile)

    public var canComplete: Bool {
        if case .capturing = self {
            return true
        }

        return false
    }
}

public enum DisplayCaptureStateMachine {
    public static func start(from state: DisplayCaptureState) -> DisplayCaptureState {
        _ = state
        return .capturing
    }

    public static func cancel(from state: DisplayCaptureState) -> DisplayCaptureState {
        _ = state
        return .idle
    }

    public static func complete(
        from state: DisplayCaptureState,
        profile: DisplayProfile?
    ) -> DisplayCaptureState {
        guard state.canComplete, let profile else {
            return state
        }

        return .completed(profile)
    }
}

public enum DisplayApplicationDecision: Equatable, Sendable {
    case alreadyApplied
    case apply(DisplayModeDescriptor)
    case unavailable
}

public enum DisplayApplicationPlanner {
    public static func decision(
        for profile: DisplayProfile,
        display: ConnectedDisplay
    ) -> DisplayApplicationDecision {
        let currentModeMatchesProfile = display.currentMode.map {
            $0.logicalWidth == profile.logicalWidth
                && $0.logicalHeight == profile.logicalHeight
                && $0.isHiDPI == profile.isHiDPI
        } ?? false

        if display.isBuiltIn, currentModeMatchesProfile {
            return .alreadyApplied
        }

        guard let desiredMode = ProfileModeSelector.matchingMode(
            for: profile,
            availableModes: display.availableModes,
            currentMode: display.currentMode,
            requiresMaximumPhysicalResolution: !display.isBuiltIn
        ) else {
            return .unavailable
        }

        if display.currentMode == desiredMode {
            return .alreadyApplied
        }

        return .apply(desiredMode)
    }
}

public enum DisplayApplicationOutcome: Equatable, Sendable {
    case applied
    case alreadyApplied
    case unavailable
}

public enum AutomationPermission: Equatable, Sendable {
    case allowed
    case paused
    case wakeProtection
    case cooldown
}

public enum AutomationPolicy {
    public static func permission(
        isPaused: Bool,
        now: Date,
        cooldownUntil: Date?,
        wakeProtectionUntil: Date?
    ) -> AutomationPermission {
        if isPaused {
            return .paused
        }

        if let wakeProtectionUntil, now < wakeProtectionUntil {
            return .wakeProtection
        }

        if let cooldownUntil, now < cooldownUntil {
            return .cooldown
        }

        return .allowed
    }
}

public struct DisplayTopology: Equatable, Sendable {
    public let externalDisplayIdentities: [DisplayIdentity]

    public init(displays: [ConnectedDisplay]) {
        externalDisplayIdentities = displays
            .filter { !$0.isBuiltIn }
            .map(\.identity)
            .sorted { $0.storageKey < $1.storageKey }
    }
}

public enum AutomaticDisplayChangePolicy {
    public static func shouldApply(
        previous: DisplayTopology?,
        current: DisplayTopology
    ) -> Bool {
        guard let previous else {
            return true
        }

        return previous.externalDisplayIdentities != current.externalDisplayIdentities
    }
}

public enum ExternalDisplaySleepPolicy {
    public static func shouldPreventSystemSleep(
        isEnabled: Bool,
        displays: [ConnectedDisplay]
    ) -> Bool {
        isEnabled && displays.contains { !$0.isBuiltIn }
    }
}

public enum DisplayModeApplicationError: Error, Equatable, Sendable {
    case modeUnavailable
    case modeChangeFailed(Int32)
}

@MainActor
public struct SystemDisplayModeApplier: DisplayModeApplying {
    public init() {}

    public func reset(_ display: ConnectedDisplay) throws {
        let result = CGDisplaySetDisplayMode(display.displayID, nil, nil)
        guard result == .success else {
            throw DisplayModeApplicationError.modeChangeFailed(result.rawValue)
        }
    }

    public func apply(
        _ profile: DisplayProfile,
        to display: ConnectedDisplay
    ) throws -> DisplayApplicationOutcome {
        switch DisplayApplicationPlanner.decision(for: profile, display: display) {
        case .alreadyApplied:
            return .alreadyApplied
        case .unavailable:
            return .unavailable
        case let .apply(desiredMode):
            guard let nativeMode = (CGDisplayCopyAllDisplayModes(display.displayID, displayModeOptions()) as? [CGDisplayMode])?
                .first(where: { displayModeDescriptor(for: $0) == desiredMode })
            else {
                throw DisplayModeApplicationError.modeUnavailable
            }

            let result = CGDisplaySetDisplayMode(display.displayID, nativeMode, nil)
            guard result == .success else {
                throw DisplayModeApplicationError.modeChangeFailed(result.rawValue)
            }

            return .applied
        }
    }
}

public enum DisplayInventoryError: Error, Equatable, Sendable {
    case activeDisplayListUnavailable(Int32)
}

@MainActor
public struct SystemDisplayInventory: DisplayInventorying {
    public init() {}

    public func connectedDisplays() throws -> [ConnectedDisplay] {
        var displayCount: UInt32 = 0
        let countResult = CGGetActiveDisplayList(0, nil, &displayCount)
        guard countResult == .success else {
            throw DisplayInventoryError.activeDisplayListUnavailable(countResult.rawValue)
        }

        var displayIDs = Array(repeating: CGDirectDisplayID(), count: Int(displayCount))
        let listResult = CGGetActiveDisplayList(displayCount, &displayIDs, &displayCount)
        guard listResult == .success else {
            throw DisplayInventoryError.activeDisplayListUnavailable(listResult.rawValue)
        }

        // P2-11: build the screen map once so the per-display lookup in
        // `snapshot(for:)` is O(1) instead of O(N × M).
        let screenByID = screenMap()

        return displayIDs.prefix(Int(displayCount)).map {
            snapshot(for: $0, screenByID: screenByID)
        }
    }

    private func screenMap() -> [CGDirectDisplayID: NSScreen] {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen in
            guard let number = (screen.deviceDescription[key] as? NSNumber)?.uint32Value else {
                return nil
            }
            return (number, screen)
        })
    }

    private func snapshot(for displayID: CGDirectDisplayID, screenByID: [CGDirectDisplayID: NSScreen]) -> ConnectedDisplay {
        let isBuiltIn = CGDisplayIsBuiltin(displayID) != 0
        let displaySize = CGDisplayScreenSize(displayID)
        let screen = screenByID[displayID]
        let displayName = screen?.localizedName ?? "Display \(displayID)"
        let identity = isBuiltIn
            ? .builtIn
            : DisplayIdentity.external(
                vendorID: CGDisplayVendorNumber(displayID),
                productID: CGDisplayModelNumber(displayID),
                serialNumber: serialNumber(for: displayID),
                name: displayName,
                physicalWidthMillimeters: UInt32(displaySize.width.rounded()),
                physicalHeightMillimeters: UInt32(displaySize.height.rounded())
            )
        let availableModes = (CGDisplayCopyAllDisplayModes(displayID, displayModeOptions()) as? [CGDisplayMode] ?? [])
                .map(displayModeDescriptor(for:))

        return ConnectedDisplay(
            displayID: displayID,
            identity: identity,
            name: displayName,
            isBuiltIn: isBuiltIn,
            currentMode: CGDisplayCopyDisplayMode(displayID).map(displayModeDescriptor(for:)),
            availableModes: availableModes
        )
    }

    private func serialNumber(for displayID: CGDirectDisplayID) -> UInt32? {
        let serialNumber = CGDisplaySerialNumber(displayID)

        return serialNumber == 0 ? nil : serialNumber
    }

}

public struct SystemMainDisplayIDProvider: MainDisplayIDProviding, @unchecked Sendable {
    public init() {}

    public var mainDisplayID: CGDirectDisplayID {
        CGMainDisplayID()
    }
}
