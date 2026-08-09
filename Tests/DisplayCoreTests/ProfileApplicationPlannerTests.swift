import ScreenShifterDomain
import XCTest
@testable import DisplayCore

final class ProfileApplicationPlannerTests: XCTestCase {
    func testRequestsExactMatchingModeForKnownProfile() {
        let currentMode = DisplayModeDescriptor(
            pixelWidth: 5120,
            pixelHeight: 2880,
            logicalWidth: 1920,
            logicalHeight: 1080,
            isHiDPI: true
        )
        let savedMode = DisplayModeDescriptor(
            pixelWidth: 5120,
            pixelHeight: 2880,
            logicalWidth: 2560,
            logicalHeight: 1440,
            isHiDPI: true
        )
        let identity = DisplayIdentity.external(
            vendorID: 1552,
            productID: 504,
            serialNumber: 42,
            name: "Studio Display",
            physicalWidthMillimeters: 600,
            physicalHeightMillimeters: 340
        )
        let display = ConnectedDisplay(
            displayID: 2,
            identity: identity,
            name: "Studio Display",
            isBuiltIn: false,
            currentMode: currentMode,
            availableModes: [currentMode, savedMode]
        )
        let profile = DisplayProfile(
            displayIdentity: identity,
            logicalWidth: 2560,
            logicalHeight: 1440,
            isHiDPI: true
        )

        let decision = DisplayApplicationPlanner.decision(for: profile, display: display)

        XCTAssertEqual(decision, .apply(savedMode))
    }

    func testUpgradesExternalDisplayToMaximumPhysicalMode() {
        let lowerResolutionMode = DisplayModeDescriptor(
            pixelWidth: 2560,
            pixelHeight: 1440,
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
        let identity = DisplayIdentity.external(
            vendorID: 1552,
            productID: 504,
            serialNumber: 42,
            name: "Studio Display",
            physicalWidthMillimeters: 600,
            physicalHeightMillimeters: 340
        )
        let display = ConnectedDisplay(
            displayID: 2,
            identity: identity,
            name: "Studio Display",
            isBuiltIn: false,
            currentMode: lowerResolutionMode,
            availableModes: [lowerResolutionMode, maximumResolutionMode]
        )
        let profile = DisplayProfile(
            displayIdentity: identity,
            logicalWidth: 2560,
            logicalHeight: 1440,
            isHiDPI: true
        )

        let decision = DisplayApplicationPlanner.decision(for: profile, display: display)

        XCTAssertEqual(decision, .apply(maximumResolutionMode))
    }
}
