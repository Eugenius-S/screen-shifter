import XCTest
@testable import ScreenShifterDomain

final class DisplayIdentityTests: XCTestCase {
    func testExternalDisplayWithSerialNumberUsesHardwareIdentifier() {
        let identity = DisplayIdentity.external(
            vendorID: 1552,
            productID: 504,
            serialNumber: 42,
            name: "Studio Display",
            physicalWidthMillimeters: 600,
            physicalHeightMillimeters: 340
        )

        XCTAssertEqual(identity.storageKey, "external:1552:504:serial:42")
    }
}