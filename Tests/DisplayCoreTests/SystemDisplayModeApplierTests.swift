import CoreGraphics
import ScreenShifterDomain
import XCTest
@testable import DisplayCore

@MainActor
final class SystemDisplayModeApplierTests: XCTestCase {
    func testSkipsDisplayAlreadyAtSavedMode() throws {
#if DEBUG && !CI
        let display = try XCTUnwrap(
            try SystemDisplayInventory().connectedDisplays().first {
                $0.displayID == CGMainDisplayID()
            }
        )
        let currentMode = try XCTUnwrap(display.currentMode)
        let profile = DisplayProfile(
            displayIdentity: display.identity,
            logicalWidth: currentMode.logicalWidth,
            logicalHeight: currentMode.logicalHeight,
            isHiDPI: currentMode.isHiDPI
        )

        let outcome = try SystemDisplayModeApplier().apply(profile, to: display)

        XCTAssertEqual(outcome, .alreadyApplied)
#endif
    }
}
