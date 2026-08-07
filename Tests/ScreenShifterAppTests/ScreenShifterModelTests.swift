import XCTest
import ScreenShifterDomain
import DisplayCore
@testable import ScreenShifterApp

@MainActor
final class ScreenShifterModelTests: XCTestCase {
    func testCaptureStatusSymbolReflectsCaptureState() {
        let profile = DisplayProfile(
            displayIdentity: .builtIn,
            logicalWidth: 1512,
            logicalHeight: 982,
            isHiDPI: true
        )

        XCTAssertEqual(
            DisplayCapturePresentation.statusSymbol(
                for: .capturing,
                hasSavedProfile: true
            ),
            "record.circle"
        )
        XCTAssertEqual(
            DisplayCapturePresentation.statusSymbol(
                for: .completed(profile),
                hasSavedProfile: false
            ),
            "checkmark.circle.fill"
        )
    }

    func testCheckForUpdatesReportsSuccessWhenReleasePageOpens() {
        let checker = FakeUpdateChecker(result: true)
        let model = ScreenShifterModel(updateChecker: checker)

        model.checkForUpdates()

        XCTAssertEqual(checker.checkCallCount, 1)
        XCTAssertEqual(model.captureMessage, "Started update check.")
        XCTAssertNil(model.errorMessage)
    }

    func testCheckForUpdatesReportsFailureWhenReleasePageCannotOpen() {
        let checker = FakeUpdateChecker(result: false)
        let model = ScreenShifterModel(updateChecker: checker)

        model.checkForUpdates()

        XCTAssertEqual(checker.checkCallCount, 1)
        XCTAssertEqual(model.errorMessage, "Could not start the update check.")
    }
}

@MainActor
private final class FakeUpdateChecker: UpdateChecking {
    let result: Bool
    private(set) var checkCallCount = 0

    init(result: Bool) {
        self.result = result
    }

    func checkForUpdates() -> Bool {
        checkCallCount += 1
        return result
    }
}
