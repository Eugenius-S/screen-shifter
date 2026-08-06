import Foundation
import XCTest
@testable import ScreenShifterDomain

final class DisplayIdentityTests: XCTestCase {
    func testExternalDisplayWithSerialNumberUsesHardwareIdentifier() {
        let identity = DisplayIdentity.external(
            vendorID: 1552,
            productID: 504,
            serialNumber: 42,
            name: "Studio Display",
            physicalWidthMillimeters: 600,
            physicalHeightMillimeters: 340
        )

        XCTAssertEqual(identity.storageKey, "external:1552:504:serial:42")
    }

    func testProfileStoreReplacesProfileForSameDisplay() async {
        let identity = DisplayIdentity.external(
            vendorID: 1552,
            productID: 504,
            serialNumber: 42,
            name: "Studio Display",
            physicalWidthMillimeters: 600,
            physicalHeightMillimeters: 340
        )
        let store = InMemoryProfileStore()
        let initialProfile = DisplayProfile(
            displayIdentity: identity,
            logicalWidth: 1728,
            logicalHeight: 1117,
            isHiDPI: true
        )
        let updatedProfile = DisplayProfile(
            displayIdentity: identity,
            logicalWidth: 2560,
            logicalHeight: 1440,
            isHiDPI: true
        )

        await store.save(initialProfile)
        await store.save(updatedProfile)

        let storedProfile = await store.profile(for: identity)

        XCTAssertEqual(storedProfile, updatedProfile)
    }

    func testUserDefaultsProfileStorePersistsProfilesAcrossInstances() async {
        let suiteName = "ScreenShifterTests.\(UUID().uuidString)"
        defer {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }

        let identity = DisplayIdentity.external(
            vendorID: 1552,
            productID: 504,
            serialNumber: 42,
            name: "Studio Display",
            physicalWidthMillimeters: 600,
            physicalHeightMillimeters: 340
        )
        let profile = DisplayProfile(
            displayIdentity: identity,
            logicalWidth: 2560,
            logicalHeight: 1440,
            isHiDPI: true
        )

        let savingStore = UserDefaultsProfileStore(suiteName: suiteName)
        await savingStore.save(profile)

        let reloadedStore = UserDefaultsProfileStore(suiteName: suiteName)
        let restoredProfile = await reloadedStore.profile(for: identity)
        let savedProfiles = await reloadedStore.profiles()

        XCTAssertEqual(restoredProfile, profile)
        XCTAssertEqual(savedProfiles, [profile])
    }
}