import XCTest
@testable import ScreenShifterDomain

final class UserDefaultsProfileStoreTests: XCTestCase {
    func testPersistsProfilesAcrossInstances() async {
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

    func testCorruptedPayloadReturnsEmptyProfiles() async {
        let suiteName = "ScreenShifterTests.\(UUID().uuidString)"
        defer {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }

        // P2-9: write invalid JSON into the same key the store uses. The
        // store must not crash; it should return an empty map and surface
        // the decode error.
        UserDefaults.standard.set(Data("not valid json".utf8), forKey: "savedDisplayProfiles")

        let store = UserDefaultsProfileStore(suiteName: suiteName)
        let profiles = await store.profiles()
        let profile = await store.profile(for: .builtIn)

        XCTAssertTrue(profiles.isEmpty)
        XCTAssertNil(profile)
    }
}
