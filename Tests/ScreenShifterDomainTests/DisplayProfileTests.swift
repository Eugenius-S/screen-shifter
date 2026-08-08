import XCTest
@testable import ScreenShifterDomain

final class DisplayProfileTests: XCTestCase {
    func testDefaultsToZeroRefreshRate() {
        let profile = DisplayProfile(
            displayIdentity: .builtIn,
            logicalWidth: 1920,
            logicalHeight: 1080,
            isHiDPI: true
        )

        XCTAssertEqual(profile.refreshRate, 0)
    }

    func testDecodesBackwardCompatibleWithoutRefreshRateField() throws {
        // JSON that predates the refresh rate field in the v2 schema.
        let legacyJSON = """
        {
          "displayIdentity": { "storageKey": "builtin" },
          "logicalWidth": 1512,
          "logicalHeight": 982,
          "isHiDPI": true
        }
        """

        let profile = try JSONDecoder().decode(DisplayProfile.self, from: Data(legacyJSON.utf8))

        XCTAssertEqual(profile.displayIdentity, .builtIn)
        XCTAssertEqual(profile.logicalWidth, 1512)
        XCTAssertEqual(profile.logicalHeight, 982)
        XCTAssertEqual(profile.isHiDPI, true)
        XCTAssertEqual(profile.refreshRate, 0)
    }

    func testRoundTripsWithRefreshRate() throws {
        let original = DisplayProfile(
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
            refreshRate: 120
        )

        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(DisplayProfile.self, from: data)

        XCTAssertEqual(restored, original)
    }
}
