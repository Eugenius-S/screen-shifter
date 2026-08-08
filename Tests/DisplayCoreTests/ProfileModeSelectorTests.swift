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
            currentMode: nil,
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
            currentMode: nil,
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
            currentMode: nil,
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
            currentMode: nil,
            requiresMaximumPhysicalResolution: false
        )

        XCTAssertEqual(selectedAtFirst, modeAt60)
    }

    // Plan 001 step 3: a saved rate with floating-point noise still
    // matches a freshly canonicalized mode rate.
    func testMatchesRoundedEquivalentRefreshRate() {
        let profile = DisplayProfile(
            displayIdentity: .builtIn,
            logicalWidth: 1920,
            logicalHeight: 1080,
            isHiDPI: true,
            refreshRate: 60.0001
        )
        let modeAt60 = DisplayModeDescriptor(pixelWidth: 3840, pixelHeight: 2160, logicalWidth: 1920, logicalHeight: 1080, isHiDPI: true, refreshRate: 60.0)
        let modeAt120 = DisplayModeDescriptor(pixelWidth: 3840, pixelHeight: 2160, logicalWidth: 1920, logicalHeight: 1080, isHiDPI: true, refreshRate: 120.0)

        let selected = ProfileModeSelector.matchingMode(
            for: profile,
            availableModes: [modeAt60, modeAt120],
            currentMode: nil,
            requiresMaximumPhysicalResolution: false
        )

        XCTAssertEqual(selected, modeAt60)
    }

    // Plan 001 step 3: when the saved rate is unavailable, fall back to
    // size+HiDPI candidates and prefer the one whose rate matches the
    // current display rate.
    func testFallsBackToCurrentRateWhenSavedRateUnavailable() {
        let profile = DisplayProfile(
            displayIdentity: .builtIn,
            logicalWidth: 1920,
            logicalHeight: 1080,
            isHiDPI: true,
            refreshRate: 144
        )
        let modeAt60 = DisplayModeDescriptor(pixelWidth: 3840, pixelHeight: 2160, logicalWidth: 1920, logicalHeight: 1080, isHiDPI: true, refreshRate: 60.0)
        let modeAt120 = DisplayModeDescriptor(pixelWidth: 3840, pixelHeight: 2160, logicalWidth: 1920, logicalHeight: 1080, isHiDPI: true, refreshRate: 120.0)
        let currentMode = DisplayModeDescriptor(pixelWidth: 3840, pixelHeight: 2160, logicalWidth: 1920, logicalHeight: 1080, isHiDPI: true, refreshRate: 60.0)

        let selected = ProfileModeSelector.matchingMode(
            for: profile,
            availableModes: [modeAt60, modeAt120],
            currentMode: currentMode,
            requiresMaximumPhysicalResolution: false
        )

        XCTAssertEqual(selected, modeAt60)
    }

    // Plan 001 step 3: when the saved rate is unavailable and the
    // candidates share the current rate, external displays still pick
    // the maximum physical resolution.
    func testExternalMaximumResolutionAfterFallback() {
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
            isHiDPI: true,
            refreshRate: 144
        )
        let lowResAt60 = DisplayModeDescriptor(pixelWidth: 2560, pixelHeight: 1440, logicalWidth: 2560, logicalHeight: 1440, isHiDPI: true, refreshRate: 60.0)
        let maxResAt60 = DisplayModeDescriptor(pixelWidth: 5120, pixelHeight: 2880, logicalWidth: 2560, logicalHeight: 1440, isHiDPI: true, refreshRate: 60.0)
        let currentMode = DisplayModeDescriptor(pixelWidth: 2560, pixelHeight: 1440, logicalWidth: 2560, logicalHeight: 1440, isHiDPI: true, refreshRate: 60.0)

        let selected = ProfileModeSelector.matchingMode(
            for: profile,
            availableModes: [lowResAt60, maxResAt60],
            currentMode: currentMode,
            requiresMaximumPhysicalResolution: true
        )

        XCTAssertEqual(selected, maxResAt60)
    }

    // Plan 001 step 3: when no candidate matches the current rate, the
    // selector still returns a compatible candidate (not nil) so the
    // applier has a fallback to try.
    func testFallbackReturnsFirstCompatibleWhenNoCurrentRateMatch() {
        let profile = DisplayProfile(
            displayIdentity: .builtIn,
            logicalWidth: 1920,
            logicalHeight: 1080,
            isHiDPI: true,
            refreshRate: 144
        )
        let modeAt60 = DisplayModeDescriptor(pixelWidth: 3840, pixelHeight: 2160, logicalWidth: 1920, logicalHeight: 1080, isHiDPI: true, refreshRate: 60.0)
        let modeAt120 = DisplayModeDescriptor(pixelWidth: 3840, pixelHeight: 2160, logicalWidth: 1920, logicalHeight: 1080, isHiDPI: true, refreshRate: 120.0)
        let currentMode = DisplayModeDescriptor(pixelWidth: 3840, pixelHeight: 2160, logicalWidth: 1920, logicalHeight: 1080, isHiDPI: true, refreshRate: 90.0)

        let selected = ProfileModeSelector.matchingMode(
            for: profile,
            availableModes: [modeAt60, modeAt120],
            currentMode: currentMode,
            requiresMaximumPhysicalResolution: false
        )

        // The 90 Hz current rate has no candidate, so the selector
        // returns the whole compatible set and the caller picks `first`.
        XCTAssertEqual(selected, modeAt60)
    }
}
