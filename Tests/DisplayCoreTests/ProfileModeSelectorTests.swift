import ScreenShifterDomain
import XCTest
@testable import DisplayCore

final class ProfileModeSelectorTests: XCTestCase {
    func testKeepsExternalDisplayAtMaximumPhysicalResolution() {
        let profile = DisplayProfile(
            displayIdentity: .external(
                vendorID: 1552,
                productID: 504,
                serialNumber: 42,
                name: "Studio Display",
                physicalWidthMillimeters: 600,
                physicalHeightMillimeters: 340
            ),
            logicalWidth: 2560,
            logicalHeight: 1440,
            isHiDPI: true
        )
        let maximumResolutionMode = DisplayModeDescriptor(
            pixelWidth: 5120,
            pixelHeight: 2880,
            logicalWidth: 2560,
            logicalHeight: 1440,
            isHiDPI: true
        )
        let lowerResolutionMode = DisplayModeDescriptor(
            pixelWidth: 2560,
            pixelHeight: 1440,
            logicalWidth: 2560,
            logicalHeight: 1440,
            isHiDPI: false
        )

        let selectedMode = ProfileModeSelector.matchingMode(
            for: profile,
            availableModes: [lowerResolutionMode, maximumResolutionMode],
            requiresMaximumPhysicalResolution: true
        )

        XCTAssertEqual(selectedMode, maximumResolutionMode)
    }

    func testChoosesLargestAvailablePhysicalMode() {
        let profile = DisplayProfile(
            displayIdentity: .external(
                vendorID: 1552,
                productID: 504,
                serialNumber: 42,
                name: "Ultrawide Display",
                physicalWidthMillimeters: 800,
                physicalHeightMillimeters: 340
            ),
            logicalWidth: 2560,
            logicalHeight: 1440,
            isHiDPI: true
        )
        let widerMode = DisplayModeDescriptor(
            pixelWidth: 5120,
            pixelHeight: 2160,
            logicalWidth: 2560,
            logicalHeight: 1440,
            isHiDPI: true
        )
        let tallerMode = DisplayModeDescriptor(
            pixelWidth: 3840,
            pixelHeight: 2880,
            logicalWidth: 2560,
            logicalHeight: 1440,
            isHiDPI: true
        )

        let selectedMode = ProfileModeSelector.matchingMode(
            for: profile,
            availableModes: [tallerMode, widerMode],
            requiresMaximumPhysicalResolution: true
        )

        XCTAssertEqual(selectedMode, widerMode)
    }

    func testMatchesByRefreshRateWhenSpecified() {
        let profile = DisplayProfile(
            displayIdentity: .builtIn,
            logicalWidth: 1920,
            logicalHeight: 1080,
            isHiDPI: true,
            refreshRate: 120
        )
        let modeAt60 = DisplayModeDescriptor(pixelWidth: 3840, pixelHeight: 2160, logicalWidth: 1920, logicalHeight: 1080, isHiDPI: true, refreshRate: 60)
        let modeAt120 = DisplayModeDescriptor(pixelWidth: 3840, pixelHeight: 2160, logicalWidth: 1920, logicalHeight: 1080, isHiDPI: true, refreshRate: 120)

        let selected = ProfileModeSelector.matchingMode(
            for: profile,
            availableModes: [modeAt60, modeAt120],
            requiresMaximumPhysicalResolution: false
        )

        XCTAssertEqual(selected, modeAt120)
    }

    func testAcceptsAnyRefreshRateWhenProfileRateIsZero() {
        let profile = DisplayProfile(
            displayIdentity: .builtIn,
            logicalWidth: 1920,
            logicalHeight: 1080,
            isHiDPI: true,
            refreshRate: 0
        )
        let modeAt60 = DisplayModeDescriptor(pixelWidth: 3840, pixelHeight: 2160, logicalWidth: 1920, logicalHeight: 1080, isHiDPI: true, refreshRate: 60)
        let modeAt120 = DisplayModeDescriptor(pixelWidth: 3840, pixelHeight: 2160, logicalWidth: 1920, logicalHeight: 1080, isHiDPI: true, refreshRate: 120)

        let selectedAtFirst = ProfileModeSelector.matchingMode(
            for: profile,
            availableModes: [modeAt60, modeAt120],
            requiresMaximumPhysicalResolution: false
        )

        XCTAssertEqual(selectedAtFirst, modeAt60)
    }
}
