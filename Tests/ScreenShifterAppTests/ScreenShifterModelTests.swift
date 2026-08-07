import XCTest
@testable import ScreenShifterApp

@MainActor
final class ScreenShifterModelTests: XCTestCase {
    func testCheckForUpdatesReportsSuccessWhenReleasePageOpens() {
        let opener = FakeUpdatePageOpener(result: true)
        let model = ScreenShifterModel(updatePageOpener: opener)

        model.checkForUpdates()

        XCTAssertEqual(opener.openCallCount, 1)
        XCTAssertEqual(model.captureMessage, "Opened the latest release page.")
        XCTAssertNil(model.errorMessage)
    }

    func testCheckForUpdatesReportsFailureWhenReleasePageCannotOpen() {
        let opener = FakeUpdatePageOpener(result: false)
        let model = ScreenShifterModel(updatePageOpener: opener)

        model.checkForUpdates()

        XCTAssertEqual(opener.openCallCount, 1)
        XCTAssertEqual(model.errorMessage, "Could not open the update page.")
    }
}

@MainActor
private final class FakeUpdatePageOpener: UpdatePageOpening {
    let result: Bool
    private(set) var openCallCount = 0

    init(result: Bool) {
        self.result = result
    }

    func openLatestReleasePage() -> Bool {
        openCallCount += 1
        return result
    }
}
