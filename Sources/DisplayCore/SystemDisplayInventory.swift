import AppKit
import CoreGraphics
import Foundation
import ScreenShifterDomain

public struct DisplayModeDescriptor: Codable, Equatable, Sendable {
    public let pixelWidth: UInt32
    public let pixelHeight: UInt32
    public let logicalWidth: UInt32
    public let logicalHeight: UInt32
    public let isHiDPI: Bool

    public init(
        pixelWidth: UInt32,
        pixelHeight: UInt32,
        logicalWidth: UInt32,
        logicalHeight: UInt32,
        isHiDPI: Bool
    ) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.logicalWidth = logicalWidth
        self.logicalHeight = logicalHeight
        self.isHiDPI = isHiDPI
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

    return DisplayModeDescriptor(
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
        logicalWidth: logicalWidth,
        logicalHeight: logicalHeight,
        isHiDPI: pixelWidth > logicalWidth || pixelHeight > logicalHeight
    )
}

public enum ProfileModeSelector {
    public static func matchingMode(
        for profile: DisplayProfile,
        availableModes: [DisplayModeDescriptor],
        requiresMaximumPhysicalResolution: Bool
    ) -> DisplayModeDescriptor? {
        let matchingModes = availableModes.filter { mode in
            mode.logicalWidth == profile.logicalWidth
                && mode.logicalHeight == profile.logicalHeight
                && mode.isHiDPI == profile.isHiDPI
        }

        guard requiresMaximumPhysicalResolution else {
            return matchingModes.first
        }

        guard let maximumPixelWidth = availableModes.map(\.pixelWidth).max(),
              let maximumPixelHeight = availableModes.map(\.pixelHeight).max()
        else {
            return nil
        }

        return matchingModes.first { mode in
            mode.pixelWidth == maximumPixelWidth && mode.pixelHeight == maximumPixelHeight
        }
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
                isHiDPI: currentMode.isHiDPI
            )
        }
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
        if let currentMode = display.currentMode,
           currentMode.logicalWidth == profile.logicalWidth,
           currentMode.logicalHeight == profile.logicalHeight,
           currentMode.isHiDPI == profile.isHiDPI
        {
            return .alreadyApplied
        }

        guard let desiredMode = ProfileModeSelector.matchingMode(
            for: profile,
            availableModes: display.availableModes,
            requiresMaximumPhysicalResolution: !display.isBuiltIn
        ) else {
            return .unavailable
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

public enum DisplayModeApplicationError: Error, Equatable, Sendable {
    case modeUnavailable
    case modeChangeFailed(Int32)
}

@MainActor
public struct SystemDisplayModeApplier {
    public init() {}

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
            guard let nativeMode = (CGDisplayCopyAllDisplayModes(display.displayID, nil) as? [CGDisplayMode])?
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
public struct SystemDisplayInventory {
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

        return displayIDs.prefix(Int(displayCount)).map(snapshot(for:))
    }

    private func snapshot(for displayID: CGDirectDisplayID) -> ConnectedDisplay {
        let isBuiltIn = CGDisplayIsBuiltin(displayID) != 0
        let displaySize = CGDisplayScreenSize(displayID)
        let screen = NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }
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
        let availableModes = (CGDisplayCopyAllDisplayModes(displayID, nil) as? [CGDisplayMode] ?? [])
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