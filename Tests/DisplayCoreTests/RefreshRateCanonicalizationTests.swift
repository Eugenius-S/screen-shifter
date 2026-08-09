import XCTest
@testable import DisplayCore

final class RefreshRateCanonicalizationTests: XCTestCase {
    func testRoundsFinitePositiveRatesToHundredths() {
        XCTAssertEqual(RefreshRateCanonicalization.canonicalize(60.001), 60.0)
        XCTAssertEqual(RefreshRateCanonicalization.canonicalize(60.005), 60.01)
        XCTAssertEqual(RefreshRateCanonicalization.canonicalize(143.999), 144.0)
        XCTAssertEqual(RefreshRateCanonicalization.canonicalize(60.0049), 60.0)
        XCTAssertEqual(RefreshRateCanonicalization.canonicalize(60.0051), 60.01)
    }

    func testPreservesZeroAsLegacySentinel() {
        XCTAssertEqual(RefreshRateCanonicalization.canonicalize(0), 0)
        XCTAssertEqual(RefreshRateCanonicalization.canonicalize(-0.0), -0.0)
    }

    func testPreservesNonFiniteValues() {
        XCTAssertTrue(RefreshRateCanonicalization.canonicalize(.nan).isNaN)
        XCTAssertEqual(RefreshRateCanonicalization.canonicalize(.infinity), .infinity)
        XCTAssertEqual(RefreshRateCanonicalization.canonicalize(-.infinity), -.infinity)
    }

    func testPreservesExactRates() {
        XCTAssertEqual(RefreshRateCanonicalization.canonicalize(60.0), 60.0)
        XCTAssertEqual(RefreshRateCanonicalization.canonicalize(120.0), 120.0)
        XCTAssertEqual(RefreshRateCanonicalization.canonicalize(144.0), 144.0)
    }
}
