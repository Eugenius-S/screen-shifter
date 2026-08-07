import CoreGraphics
import ScreenShifterDomain
import XCTest
@testable import DisplayCore

@MainActor
final class SystemDisplayInventoryTests: XCTestCase {
    func testSystemInventoryIncludesMainDisplay() throws {
        let displays = try SystemDisplayInventory().connectedDisplays()

        XCTAssertTrue(displays.contains { $0.displayID == CGMainDisplayID() })
    }

    func testModeSelectorKeepsExternalDisplayAtMaximumPhysicalResolution() {
        let profile = DisplayProfile(
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
            isHiDPI: true
        )
        let maximumResolutionMode = DisplayModeDescriptor(
            pixelWidth: 5120,
            pixelHeight: 2880,
            logicalWidth: 2560,
            logicalHeight: 1440,
            isHiDPI: true
        )
        let lowerResolutionMode = DisplayModeDescriptor(
            pixelWidth: 2560,
            pixelHeight: 1440,
            logicalWidth: 2560,
            logicalHeight: 1440,
            isHiDPI: false
        )

        let selectedMode = ProfileModeSelector.matchingMode(
            for: profile,
            availableModes: [lowerResolutionMode, maximumResolutionMode],
            requiresMaximumPhysicalResolution: true
        )

        XCTAssertEqual(selectedMode, maximumResolutionMode)
    }

    func testModeSelectorChoosesLargestAvailablePhysicalMode() {
        let profile = DisplayProfile(
            displayIdentity: .external(
                vendorID: 1552,
                productID: 504,
                serialNumber: 42,
                name: "Ultrawide Display",
                physicalWidthMillimeters: 800,
                physicalHeightMillimeters: 340
            ),
            logicalWidth: 2560,
            logicalHeight: 1440,
            isHiDPI: true
        )
        let widerMode = DisplayModeDescriptor(
            pixelWidth: 5120,
            pixelHeight: 2160,
            logicalWidth: 2560,
            logicalHeight: 1440,
            isHiDPI: true
        )
        let tallerMode = DisplayModeDescriptor(
            pixelWidth: 3840,
            pixelHeight: 2880,
            logicalWidth: 2560,
            logicalHeight: 1440,
            isHiDPI: true
        )

        let selectedMode = ProfileModeSelector.matchingMode(
            for: profile,
            availableModes: [tallerMode, widerMode],
            requiresMaximumPhysicalResolution: true
        )

        XCTAssertEqual(selectedMode, widerMode)
    }

    func testCapturePlannerCreatesProfilesForDisplaysWithCurrentModes() {
        let builtInMode = DisplayModeDescriptor(
            pixelWidth: 3024,
            pixelHeight: 1964,
            logicalWidth: 1512,
            logicalHeight: 982,
            isHiDPI: true
        )
        let externalMode = DisplayModeDescriptor(
            pixelWidth: 5120,
            pixelHeight: 2880,
            logicalWidth: 2560,
            logicalHeight: 1440,
            isHiDPI: true
        )
        let externalIdentity = DisplayIdentity.external(
            vendorID: 1552,
            productID: 504,
            serialNumber: 42,
            name: "Studio Display",
            physicalWidthMillimeters: 600,
            physicalHeightMillimeters: 340
        )
        let displays = [
            ConnectedDisplay(
                displayID: 1,
                identity: .builtIn,
                name: "MacBook Air Display",
                isBuiltIn: true,
                currentMode: builtInMode,
                availableModes: [builtInMode]
            ),
            ConnectedDisplay(
                displayID: 2,
                identity: externalIdentity,
                name: "Studio Display",
                isBuiltIn: false,
                currentMode: externalMode,
                availableModes: [externalMode]
            )
        ]

        let profiles = ProfileCapturePlanner.profiles(for: displays)

        XCTAssertEqual(
            profiles,
            [
                DisplayProfile(
                    displayIdentity: .builtIn,
                    logicalWidth: 1512,
                    logicalHeight: 982,
                    isHiDPI: true
                ),
                DisplayProfile(
                    displayIdentity: externalIdentity,
                    logicalWidth: 2560,
                    logicalHeight: 1440,
                    isHiDPI: true
                )
            ]
        )
    }

    func testApplicationPlannerRequestsExactMatchingModeForKnownProfile() {
        let currentMode = DisplayModeDescriptor(
            pixelWidth: 5120,
            pixelHeight: 2880,
            logicalWidth: 1920,
            logicalHeight: 1080,
            isHiDPI: true
        )
        let savedMode = DisplayModeDescriptor(
            pixelWidth: 5120,
            pixelHeight: 2880,
            logicalWidth: 2560,
            logicalHeight: 1440,
            isHiDPI: true
        )
        let identity = DisplayIdentity.external(
            vendorID: 1552,
            productID: 504,
            serialNumber: 42,
            name: "Studio Display",
            physicalWidthMillimeters: 600,
            physicalHeightMillimeters: 340
        )
        let display = ConnectedDisplay(
            displayID: 2,
            identity: identity,
            name: "Studio Display",
            isBuiltIn: false,
            currentMode: currentMode,
            availableModes: [currentMode, savedMode]
        )
        let profile = DisplayProfile(
            displayIdentity: identity,
            logicalWidth: 2560,
            logicalHeight: 1440,
            isHiDPI: true
        )

        let decision = DisplayApplicationPlanner.decision(for: profile, display: display)

        XCTAssertEqual(decision, .apply(savedMode))
    }

    func testApplicationPlannerUpgradesExternalDisplayToMaximumPhysicalMode() {
        let lowerResolutionMode = DisplayModeDescriptor(
            pixelWidth: 2560,
            pixelHeight: 1440,
            logicalWidth: 2560,
            logicalHeight: 1440,
            isHiDPI: true
        )
        let maximumResolutionMode = DisplayModeDescriptor(
            pixelWidth: 5120,
            pixelHeight: 2880,
            logicalWidth: 2560,
            logicalHeight: 1440,
            isHiDPI: true
        )
        let identity = DisplayIdentity.external(
            vendorID: 1552,
            productID: 504,
            serialNumber: 42,
            name: "Studio Display",
            physicalWidthMillimeters: 600,
            physicalHeightMillimeters: 340
        )
        let display = ConnectedDisplay(
            displayID: 2,
            identity: identity,
            name: "Studio Display",
            isBuiltIn: false,
            currentMode: lowerResolutionMode,
            availableModes: [lowerResolutionMode, maximumResolutionMode]
        )
        let profile = DisplayProfile(
            displayIdentity: identity,
            logicalWidth: 2560,
            logicalHeight: 1440,
            isHiDPI: true
        )

        let decision = DisplayApplicationPlanner.decision(for: profile, display: display)

        XCTAssertEqual(decision, .apply(maximumResolutionMode))
    }

    func testModeApplierSkipsDisplayAlreadyAtSavedMode() throws {
        let display = try XCTUnwrap(
            try SystemDisplayInventory().connectedDisplays().first {
                $0.displayID == CGMainDisplayID()
            }
        )
        let currentMode = try XCTUnwrap(display.currentMode)
        let profile = DisplayProfile(
            displayIdentity: display.identity,
            logicalWidth: currentMode.logicalWidth,
            logicalHeight: currentMode.logicalHeight,
            isHiDPI: currentMode.isHiDPI
        )

        let outcome = try SystemDisplayModeApplier().apply(profile, to: display)

        XCTAssertEqual(outcome, .alreadyApplied)
    }

    func testAutomationPolicyBlocksDuringWakeProtection() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)

        let permission = AutomationPolicy.permission(
            isPaused: false,
            now: now,
            cooldownUntil: now.addingTimeInterval(-1),
            wakeProtectionUntil: now.addingTimeInterval(5)
        )

        XCTAssertEqual(permission, .wakeProtection)
    }

    func testAutomaticDisplayChangeIgnoresBuiltInOnlyChanges() {
        let externalDisplay = ConnectedDisplay(
            displayID: 2,
            identity: .external(
                vendorID: 1552,
                productID: 504,
                serialNumber: 42,
                name: "Studio Display",
                physicalWidthMillimeters: 600,
                physicalHeightMillimeters: 340
            ),
            name: "Studio Display",
            isBuiltIn: false,
            currentMode: nil,
            availableModes: []
        )
        let builtInDisplay = ConnectedDisplay(
            displayID: 1,
            identity: .builtIn,
            name: "MacBook Air Display",
            isBuiltIn: true,
            currentMode: nil,
            availableModes: []
        )
        let previous = DisplayTopology(displays: [builtInDisplay, externalDisplay])
        let changedBuiltInDisplay = ConnectedDisplay(
            displayID: 1,
            identity: .builtIn,
            name: "MacBook Air Display",
            isBuiltIn: true,
            currentMode: DisplayModeDescriptor(
                pixelWidth: 2560,
                pixelHeight: 1664,
                logicalWidth: 1280,
                logicalHeight: 832,
                isHiDPI: true
            ),
            availableModes: []
        )
        let current = DisplayTopology(displays: [changedBuiltInDisplay, externalDisplay])

        XCTAssertFalse(
            AutomaticDisplayChangePolicy.shouldApply(
                previous: previous,
                current: current
            )
        )
    }

    func testExternalSleepPolicyRequiresEnabledSettingAndExternalDisplay() {
        let builtInDisplay = ConnectedDisplay(
            displayID: 1,
            identity: .builtIn,
            name: "MacBook Air Display",
            isBuiltIn: true,
            currentMode: nil,
            availableModes: []
        )
        let externalDisplay = ConnectedDisplay(
            displayID: 2,
            identity: .external(
                vendorID: 1552,
                productID: 504,
                serialNumber: 42,
                name: "Studio Display",
                physicalWidthMillimeters: 600,
                physicalHeightMillimeters: 340
            ),
            name: "Studio Display",
            isBuiltIn: false,
            currentMode: nil,
            availableModes: []
        )

        XCTAssertTrue(
            ExternalDisplaySleepPolicy.shouldPreventSystemSleep(
                isEnabled: true,
                displays: [builtInDisplay, externalDisplay]
            )
        )
        XCTAssertFalse(
            ExternalDisplaySleepPolicy.shouldPreventSystemSleep(
                isEnabled: false,
                displays: [builtInDisplay, externalDisplay]
            )
        )
        XCTAssertFalse(
            ExternalDisplaySleepPolicy.shouldPreventSystemSleep(
                isEnabled: true,
                displays: [builtInDisplay]
            )
        )
    }

    func testCaptureStateStartsCapturingAndCompletesWithProfile() {
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

    func testCaptureStateDoesNotCompleteBeforeCaptureStarts() {
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

    func testCaptureStateCancelsWhenDisplayBecomesUnavailable() {
        let cancelled = DisplayCaptureStateMachine.cancel(from: .capturing)

        XCTAssertEqual(cancelled, .idle)
        XCTAssertFalse(cancelled.canComplete)
    }
}
