import ScreenShifterDomain
import XCTest
@testable import DisplayCore

final class ProfileCapturePlannerTests: XCTestCase {
    func testCreatesProfilesForDisplaysWithCurrentModes() {
        let builtInMode = DisplayModeDescriptor(
            pixelWidth: 3024,
            pixelHeight: 1964,
            logicalWidth: 1512,
            logicalHeight: 982,
            isHiDPI: true
        )
        let externalMode = DisplayModeDescriptor(
            pixelWidth: 5120,
            pixelHeight: 2880,
            logicalWidth: 2560,
            logicalHeight: 1440,
            isHiDPI: true
        )
        let externalIdentity = DisplayIdentity.external(
            vendorID: 1552,
            productID: 504,
            serialNumber: 42,
            name: "Studio Display",
            physicalWidthMillimeters: 600,
            physicalHeightMillimeters: 340
        )
        let displays = [
            ConnectedDisplay(
                displayID: 1,
                identity: .builtIn,
                name: "MacBook Air Display",
                isBuiltIn: true,
                currentMode: builtInMode,
                availableModes: [builtInMode]
            ),
            ConnectedDisplay(
                displayID: 2,
                identity: externalIdentity,
                name: "Studio Display",
                isBuiltIn: false,
                currentMode: externalMode,
                availableModes: [externalMode]
            )
        ]

        let profiles = ProfileCapturePlanner.profiles(for: displays)

        XCTAssertEqual(
            profiles,
            [
                DisplayProfile(
                    displayIdentity: .builtIn,
                    logicalWidth: 1512,
                    logicalHeight: 982,
                    isHiDPI: true
                ),
                DisplayProfile(
                    displayIdentity: externalIdentity,
                    logicalWidth: 2560,
                    logicalHeight: 1440,
                    isHiDPI: true
                )
            ]
        )
    }
}
