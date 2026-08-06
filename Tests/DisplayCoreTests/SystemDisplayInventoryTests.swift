import CoreGraphics
import XCTest
@testable import DisplayCore

@MainActor
final class SystemDisplayInventoryTests: XCTestCase {
    func testSystemInventoryIncludesMainDisplay() throws {
        let displays = try SystemDisplayInventory().connectedDisplays()

        XCTAssertTrue(displays.contains { $0.displayID == CGMainDisplayID() })
    }
}