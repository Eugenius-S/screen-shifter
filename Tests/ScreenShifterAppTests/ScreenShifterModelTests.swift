import XCTest
import ScreenShifterDomain
@testable import DisplayCore
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
        let model = makeModel(checker: checker)

        model.checkForUpdates()

        XCTAssertEqual(checker.checkCallCount, 1)
        XCTAssertEqual(model.captureMessage, "Started update check.")
        XCTAssertNil(model.errorMessage)
    }

    func testCheckForUpdatesReportsFailureWhenUpdateCheckCannotStart() {
        let checker = FakeUpdateChecker(result: false)
        let model = makeModel(checker: checker)

        model.checkForUpdates()

        XCTAssertEqual(checker.checkCallCount, 1)
        XCTAssertEqual(model.errorMessage, "Could not start the update check.")
    }

    func testRefreshPopulatesDisplaysFromInventory() async throws {
        let inventory = FakeDisplayInventory()
        inventory.displaysToReturn = [
            ConnectedDisplay(displayID: 1, identity: .builtIn, name: "Built-in", isBuiltIn: true, currentMode: nil, availableModes: []),
            ConnectedDisplay(displayID: 2, identity: .external(vendorID: 1, productID: 2, serialNumber: 3, name: "Ext", physicalWidthMillimeters: 0, physicalHeightMillimeters: 0), name: "Ext", isBuiltIn: false, currentMode: nil, availableModes: [])
        ]
        let model = makeModel(inventory: inventory, profileStore: InMemoryProfileStore())

        await model.refresh()

        XCTAssertEqual(model.displays.count, 2)
        XCTAssertNil(model.errorMessage)
    }

    func testApplySavedSetupCallsApplierForEachKnownProfile() async throws {
        let inventory = FakeDisplayInventory()
        let external = ConnectedDisplay(
            displayID: 2,
            identity: .external(vendorID: 1, productID: 2, serialNumber: 3, name: "Ext", physicalWidthMillimeters: 0, physicalHeightMillimeters: 0),
            name: "Ext", isBuiltIn: false, currentMode: nil, availableModes: []
        )
        inventory.displaysToReturn = [external]
        let profile = DisplayProfile(displayIdentity: external.identity, logicalWidth: 1920, logicalHeight: 1080, isHiDPI: false)
        let store = InMemoryProfileStore()
        await store.save(profile)
        let applier = FakeDisplayModeApplier()
        let model = makeModel(inventory: inventory, modeApplier: applier, profileStore: store)

        await model.applySavedSetup(isAutomatic: false)

        XCTAssertEqual(applier.calls.count, 1)
        XCTAssertEqual(applier.calls.first?.kind, .apply)
        XCTAssertEqual(applier.calls.first?.displayID, 2)
    }

    func testApplySavedSetupSkipsDisplaysWithoutProfile() async throws {
        let inventory = FakeDisplayInventory()
        inventory.displaysToReturn = [
            ConnectedDisplay(displayID: 2, identity: .external(vendorID: 1, productID: 2, serialNumber: 3, name: "Ext", physicalWidthMillimeters: 0, physicalHeightMillimeters: 0), name: "Ext", isBuiltIn: false, currentMode: nil, availableModes: [])
        ]
        let applier = FakeDisplayModeApplier()
        let model = makeModel(inventory: inventory, modeApplier: applier, profileStore: InMemoryProfileStore())

        await model.applySavedSetup(isAutomatic: false)

        XCTAssertTrue(applier.calls.isEmpty)
    }

    func testConfirmResetCallsApplierAndRemovesProfile() async throws {
        let inventory = FakeDisplayInventory()
        let external = ConnectedDisplay(
            displayID: 7,
            identity: .external(vendorID: 1, productID: 2, serialNumber: 3, name: "Ext", physicalWidthMillimeters: 0, physicalHeightMillimeters: 0),
            name: "Ext", isBuiltIn: false, currentMode: nil, availableModes: []
        )
        inventory.displaysToReturn = [external]
        let profile = DisplayProfile(displayIdentity: external.identity, logicalWidth: 1920, logicalHeight: 1080, isHiDPI: false)
        let store = InMemoryProfileStore()
        await store.save(profile)
        let applier = FakeDisplayModeApplier()
        let model = makeModel(inventory: inventory, modeApplier: applier, profileStore: store)

        await model.refresh()
        model.prepareReset(for: external)
        await model.confirmReset()

        let expected = [FakeDisplayModeApplier.Call(kind: .reset, displayID: 7)]
        XCTAssertEqual(applier.calls, expected)
        let remaining = await store.profiles()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testHandleDisplayChangeNotificationSchedulesApplyOnTopologyChange() async throws {
        let inventory = FakeDisplayInventory()
        let builtIn = ConnectedDisplay(displayID: 1, identity: .builtIn, name: "Built-in", isBuiltIn: true, currentMode: nil, availableModes: [])
        let external = ConnectedDisplay(
            displayID: 2,
            identity: .external(vendorID: 1, productID: 2, serialNumber: 3, name: "Ext", physicalWidthMillimeters: 0, physicalHeightMillimeters: 0),
            name: "Ext", isBuiltIn: false, currentMode: nil, availableModes: []
        )
        inventory.displaysToReturn = [builtIn]
        let profile = DisplayProfile(displayIdentity: external.identity, logicalWidth: 1920, logicalHeight: 1080, isHiDPI: false)
        let store = InMemoryProfileStore()
        await store.save(profile)
        let applier = FakeDisplayModeApplier()
        let model = makeModel(inventory: inventory, modeApplier: applier, profileStore: store)

        await model.refresh()
        XCTAssertTrue(applier.calls.isEmpty)

        inventory.displaysToReturn = [builtIn, external]
        model.handleDisplayChangeNotification()
        try await Task.sleep(nanoseconds: 2_500_000_000)

        XCTAssertFalse(applier.calls.isEmpty)
        XCTAssertEqual(applier.calls.first?.displayID, 2)
    }

    @MainActor
    private func makeModel(
        inventory: FakeDisplayInventory = FakeDisplayInventory(),
        modeApplier: FakeDisplayModeApplier = FakeDisplayModeApplier(),
        mainDisplayIDProvider: FakeMainDisplayIDProvider = FakeMainDisplayIDProvider(),
        profileStore: DisplayProfileStoring = InMemoryProfileStore(),
        logStore: LocalLogStore = LocalLogStore(),
        checker: UpdateChecking = FakeUpdateChecker(result: true)
    ) -> ScreenShifterModel {
        ScreenShifterModel(
            inventory: inventory,
            modeApplier: modeApplier,
            mainDisplayIDProvider: mainDisplayIDProvider,
            profileStore: profileStore,
            logStore: logStore,
            updateChecker: checker
        )
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
