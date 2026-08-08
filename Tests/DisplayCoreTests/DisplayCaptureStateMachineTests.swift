import ScreenShifterDomain
import XCTest
@testable import DisplayCore

final class DisplayCaptureStateMachineTests: XCTestCase {
    func testStartsCapturingAndCompletesWithProfile() {
        let profile = DisplayProfile(
            displayIdentity: .builtIn,
            logicalWidth: 1512,
            logicalHeight: 982,
            isHiDPI: true
        )

        let capturing = DisplayCaptureStateMachine.start(from: .idle)
        let completed = DisplayCaptureStateMachine.complete(
            from: capturing,
            profile: profile
        )

        XCTAssertEqual(capturing, .capturing)
        XCTAssertTrue(capturing.canComplete)
        XCTAssertEqual(completed, .completed(profile))
        XCTAssertFalse(completed.canComplete)
    }

    func testDoesNotCompleteBeforeCaptureStarts() {
        let profile = DisplayProfile(
            displayIdentity: .builtIn,
            logicalWidth: 1512,
            logicalHeight: 982,
            isHiDPI: true
        )

        let completed = DisplayCaptureStateMachine.complete(
            from: .idle,
            profile: profile
        )

        XCTAssertEqual(completed, .idle)
    }

    func testCancelsWhenDisplayBecomesUnavailable() {
        let cancelled = DisplayCaptureStateMachine.cancel(from: .capturing)

        XCTAssertEqual(cancelled, .idle)
        XCTAssertFalse(cancelled.canComplete)
    }
}
