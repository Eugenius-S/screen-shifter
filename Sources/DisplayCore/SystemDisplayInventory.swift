import AppKit
import CoreGraphics
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
            .map(modeDescriptor(for:))

        return ConnectedDisplay(
            displayID: displayID,
            identity: identity,
            name: displayName,
            isBuiltIn: isBuiltIn,
            currentMode: CGDisplayCopyDisplayMode(displayID).map(modeDescriptor(for:)),
            availableModes: availableModes
        )
    }

    private func serialNumber(for displayID: CGDirectDisplayID) -> UInt32? {
        let serialNumber = CGDisplaySerialNumber(displayID)

        return serialNumber == 0 ? nil : serialNumber
    }

    private func modeDescriptor(for mode: CGDisplayMode) -> DisplayModeDescriptor {
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
}