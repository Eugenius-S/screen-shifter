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
        XCTAssertEqual(model.errorMessage, .updateCheckFailed)
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

        await model.refresh()
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

    func testInventoryReadFailureSetsInventoryReadFailedError() async throws {
        struct InventoryError: Error {}
        let inventory = FakeDisplayInventory()
        inventory.errorToThrow = InventoryError()
        let model = makeModel(inventory: inventory)

        await model.refresh()

        XCTAssertEqual(model.errorMessage, .inventoryReadFailed)
    }

    func testApplySavedSetupApplyErrorSetsTypedError() async throws {
        struct ApplyError: Error {}
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
        applier.applyError = ApplyError()
        let model = makeModel(inventory: inventory, modeApplier: applier, profileStore: store)

        await model.refresh()
        await model.applySavedSetup(isAutomatic: false)

        XCTAssertEqual(model.errorMessage, .applyFailed(displays: ["Ext"]))
    }

    func testClearLogsClearsErrorOnSuccess() async throws {
        struct InventoryError: Error {}
        let inventory = FakeDisplayInventory()
        inventory.errorToThrow = InventoryError()
        let logStore = makeTempLogStore()
        let model = makeModel(inventory: inventory, logStore: logStore)

        await model.refresh()
        XCTAssertEqual(model.errorMessage, .inventoryReadFailed)

        await model.clearLogs()
        XCTAssertNil(model.errorMessage)
    }

    func testCompleteCaptureClearsErrorOnSuccess() async throws {
        let inventory = FakeDisplayInventory()
        let mode = DisplayModeDescriptor(
            pixelWidth: 1920, pixelHeight: 1080,
            logicalWidth: 1920, logicalHeight: 1080,
            isHiDPI: false
        )
        let external = ConnectedDisplay(
            displayID: 2,
            identity: .external(vendorID: 1, productID: 2, serialNumber: 3, name: "Ext", physicalWidthMillimeters: 0, physicalHeightMillimeters: 0),
            name: "Ext", isBuiltIn: false, currentMode: mode, availableModes: [mode]
        )
        inventory.displaysToReturn = [external]
        let model = makeModel(inventory: inventory, profileStore: InMemoryProfileStore())

        await model.refresh()
        model.startCapture(for: external)
        await model.completeCapture(for: external)

        XCTAssertNil(model.errorMessage)
    }

    func testModelErrorMessageRendersUserFacingText() {
        XCTAssertEqual(
            ModelError.inventoryReadFailed.message,
            "Could not read connected displays."
        )
        XCTAssertEqual(
            ModelError.updateCheckFailed.message,
            "Could not start the update check."
        )
        XCTAssertEqual(
            ModelError.launchAtLoginFailed(reason: "Boom").message,
            "Boom"
        )
        XCTAssertEqual(
            ModelError.applyFailed(displays: ["A", "B"]).message,
            "Could not apply profiles for: A, B."
        )
        XCTAssertEqual(
            ModelError.sleepAssertionFailed.message,
            "Could not change the external-display sleep setting."
        )
    }

    func testConfirmResetRemovesProfileWhenDisplayDisconnected() async throws {
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

        // Display disconnected between prepareReset and confirmReset.
        inventory.displaysToReturn = []

        await model.confirmReset()

        let remaining = await store.profiles()
        XCTAssertTrue(remaining.isEmpty)
        // No reset call to the applier because the display is gone.
        XCTAssertEqual(applier.calls, [])
        XCTAssertTrue(
            model.captureMessage?.contains("disconnected") ?? false,
            "Expected disconnect-aware message, got \(model.captureMessage ?? "<nil>")"
        )
    }

    func testConfirmResetSurfacesResetErrorWhenApplierThrows() async throws {
        struct ResetError: Error {}
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

        // Swap the applier to one that throws on reset without
        // touching the rest of the model.
        let throwingApplier = ThrowingResetApplier(error: ResetError())
        let throwingModel = makeModel(
            inventory: inventory,
            modeApplier: throwingApplier,
            profileStore: store
        )
        await throwingModel.refresh()
        throwingModel.prepareReset(for: external)
        await throwingModel.confirmReset()

        // Profile is preserved when the reset fails.
        let remaining = await store.profiles()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(throwingModel.errorMessage, ModelError.resetFailed(display: "Ext"))
    }

    func testApplySavedSetupUsesCachedProfilesInsteadOfReReadingStore() async throws {
        let inventory = FakeDisplayInventory()
        let external = ConnectedDisplay(
            displayID: 2,
            identity: .external(vendorID: 1, productID: 2, serialNumber: 3, name: "Ext", physicalWidthMillimeters: 0, physicalHeightMillimeters: 0),
            name: "Ext", isBuiltIn: false, currentMode: nil, availableModes: []
        )
        inventory.displaysToReturn = [external]
        let cachedProfile = DisplayProfile(displayIdentity: external.identity, logicalWidth: 1920, logicalHeight: 1080, isHiDPI: false, refreshRate: 0)
        let store = InMemoryProfileStore()
        await store.save(cachedProfile)
        let applier = FakeDisplayModeApplier()
        let model = makeModel(inventory: inventory, modeApplier: applier, profileStore: store)

        // Refresh populates the in-memory `savedProfiles` cache from the
        // current store contents.
        await model.refresh()

        // Mutate the store directly without going through the model. The
        // cache should still hold the original profile.
        let newProfile = DisplayProfile(displayIdentity: external.identity, logicalWidth: 2560, logicalHeight: 1440, isHiDPI: true, refreshRate: 0)
        await store.save(newProfile)

        await model.applySavedSetup(isAutomatic: false)

        XCTAssertEqual(applier.lastAppliedProfile?.logicalWidth, 1920)
        XCTAssertEqual(applier.lastAppliedProfile?.logicalHeight, 1080)
        XCTAssertEqual(applier.lastAppliedProfile?.isHiDPI, false)
    }

    @MainActor
    private func makeModel(
        inventory: FakeDisplayInventory = FakeDisplayInventory(),
        modeApplier: DisplayModeApplying = FakeDisplayModeApplier(),
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

    @MainActor
    private func makeTempLogStore() -> LocalLogStore {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("screen-shifter-test-\(UUID().uuidString).log")
        return LocalLogStore(fileURL: tempURL)
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

@MainActor
private final class ThrowingResetApplier: DisplayModeApplying, @unchecked Sendable {
    private let error: Error

    init(error: Error) {
        self.error = error
    }

    func apply(_ profile: DisplayProfile, to display: ConnectedDisplay) throws -> DisplayApplicationOutcome {
        return .applied
    }

    func reset(_ display: ConnectedDisplay) throws {
        throw error
    }
}
