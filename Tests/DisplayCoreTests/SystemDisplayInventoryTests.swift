import CoreGraphics
import ScreenShifterDomain
import XCTest
@testable import DisplayCore

@MainActor
final class SystemDisplayInventoryTests: XCTestCase {
    func testSystemInventoryIncludesMainDisplay() throws {
        let mainDisplayID = CGMainDisplayID()
        let inventory = FakeDisplayInventory()
        inventory.displaysToReturn = [
            ConnectedDisplay(
                displayID: mainDisplayID,
                identity: .builtIn,
                name: "Main Display",
                isBuiltIn: true,
                currentMode: nil,
                availableModes: []
            )
        ]

        let displays = try inventory.connectedDisplays()

        XCTAssertTrue(displays.contains { $0.displayID == mainDisplayID })
    }
}
