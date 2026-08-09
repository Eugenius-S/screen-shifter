import ScreenShifterDomain
import XCTest
@testable import DisplayCore

final class ExternalDisplaySleepPolicyTests: XCTestCase {
    func testRequiresEnabledSettingAndExternalDisplay() {
        let builtInDisplay = ConnectedDisplay(
            displayID: 1,
            identity: .builtIn,
            name: "MacBook Air Display",
            isBuiltIn: true,
            currentMode: nil,
            availableModes: []
        )
        let externalDisplay = ConnectedDisplay(
            displayID: 2,
            identity: .external(
                vendorID: 1552,
                productID: 504,
                serialNumber: 42,
                name: "Studio Display",
                physicalWidthMillimeters: 600,
                physicalHeightMillimeters: 340
            ),
            name: "Studio Display",
            isBuiltIn: false,
            currentMode: nil,
            availableModes: []
        )

        XCTAssertTrue(
            ExternalDisplaySleepPolicy.shouldPreventSystemSleep(
                isEnabled: true,
                displays: [builtInDisplay, externalDisplay]
            )
        )
        XCTAssertFalse(
            ExternalDisplaySleepPolicy.shouldPreventSystemSleep(
                isEnabled: false,
                displays: [builtInDisplay, externalDisplay]
            )
        )
        XCTAssertFalse(
            ExternalDisplaySleepPolicy.shouldPreventSystemSleep(
                isEnabled: true,
                displays: [builtInDisplay]
            )
        )
    }
}
