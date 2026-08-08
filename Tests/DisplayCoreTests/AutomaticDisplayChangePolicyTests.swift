import ScreenShifterDomain
import XCTest
@testable import DisplayCore

final class AutomaticDisplayChangePolicyTests: XCTestCase {
    func testIgnoresBuiltInOnlyChanges() {
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
        let builtInDisplay = ConnectedDisplay(
            displayID: 1,
            identity: .builtIn,
            name: "MacBook Air Display",
            isBuiltIn: true,
            currentMode: nil,
            availableModes: []
        )
        let previous = DisplayTopology(displays: [builtInDisplay, externalDisplay])
        let changedBuiltInDisplay = ConnectedDisplay(
            displayID: 1,
            identity: .builtIn,
            name: "MacBook Air Display",
            isBuiltIn: true,
            currentMode: DisplayModeDescriptor(
                pixelWidth: 2560,
                pixelHeight: 1664,
                logicalWidth: 1280,
                logicalHeight: 832,
                isHiDPI: true
            ),
            availableModes: []
        )
        let current = DisplayTopology(displays: [changedBuiltInDisplay, externalDisplay])

        XCTAssertFalse(
            AutomaticDisplayChangePolicy.shouldApply(
                previous: previous,
                current: current
            )
        )
    }
}
