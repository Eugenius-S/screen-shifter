import XCTest
import ScreenShifterDomain
import DisplayCore
@testable import ScreenShifterApp

@MainActor
final class ScreenShifterModelTests: XCTestCase {
    func testGitHubUpdateConfigurationUsesPublicURLs() {
        XCTAssertEqual(
            GitHubUpdateConfiguration.feedURL.absoluteString,
            "https://github.com/Eugenius-S/screen-shifter/releases/latest/download/appcast.xml"
        )
        XCTAssertNil(GitHubUpdateConfiguration.feedURL.user)
        XCTAssertNil(GitHubUpdateConfiguration.feedURL.password)
    }

    func testSparkleUpdaterDelegateUsesAppcastURL() {
        let delegate = SparkleUpdaterDelegate()

        XCTAssertEqual(
            delegate.appcastURLString,
            GitHubUpdateConfiguration.feedURL.absoluteString
        )
    }

    func testSystemSettingsDestinationsOpenSpecificPanes() {
        XCTAssertEqual(
            SystemSettingsDestination.displayResolution.url?.absoluteString,
            "x-apple.systempreferences:com.apple.Displays-Settings.extension"
        )
        XCTAssertEqual(
            SystemSettingsDestination.accessibilityDisplay.url?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.universalaccess?Seeing_Display"
        )
        XCTAssertEqual(
            SystemSettingsDestination.dock.url?.absoluteString,
            "x-apple.systempreferences:com.apple.Desktop-Settings.extension"
        )
    }

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

    func testCheckForUpdatesReportsSuccessWhenUpdateCheckStarts() {
        let checker = FakeUpdateChecker(result: true)
        let model = ScreenShifterModel(updateChecker: checker)

        model.checkForUpdates()

        XCTAssertEqual(checker.checkCallCount, 1)
        XCTAssertEqual(model.captureMessage, "Started update check.")
        XCTAssertNil(model.errorMessage)
    }

    func testCheckForUpdatesReportsFailureWhenUpdateCheckCannotStart() {
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
