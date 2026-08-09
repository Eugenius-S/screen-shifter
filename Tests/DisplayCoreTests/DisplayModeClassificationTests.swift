import XCTest
@testable import DisplayCore

final class DisplayModeClassificationTests: XCTestCase {
    // Plan 001 step 4: a mode where only one pixel dimension is greater
    // than its logical counterpart is a stretched non-HiDPI mode, not a
    // HiDPI mode. The previous `||` classifier misclassified these.
    func testStretchedModeIsNotHiDPI() {
        XCTAssertFalse(
            DisplayModeClassification.isHiDPI(
                pixelWidth: 3840,
                pixelHeight: 1080,
                logicalWidth: 1920,
                logicalHeight: 1080
            )
        )
        XCTAssertFalse(
            DisplayModeClassification.isHiDPI(
                pixelWidth: 1920,
                pixelHeight: 2160,
                logicalWidth: 1920,
                logicalHeight: 1080
            )
        )
    }

    // Plan 001 step 4: a normal HiDPI mode has *both* pixel dimensions
    // greater than their logical counterparts.
    func testNormalTwoDimensionHiDPIModeIsHiDPI() {
        XCTAssertTrue(
            DisplayModeClassification.isHiDPI(
                pixelWidth: 3840,
                pixelHeight: 2160,
                logicalWidth: 1920,
                logicalHeight: 1080
            )
        )
    }

    // Plan 001 step 4: 1:1 modes (no scaling) are not HiDPI.
    func testOneToOneModeIsNotHiDPI() {
        XCTAssertFalse(
            DisplayModeClassification.isHiDPI(
                pixelWidth: 1920,
                pixelHeight: 1080,
                logicalWidth: 1920,
                logicalHeight: 1080
            )
        )
    }
}
