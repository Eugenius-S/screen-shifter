import XCTest
@testable import ScreenShifterDomain

final class InMemoryProfileStoreTests: XCTestCase {
    func testReplacesProfileForSameDisplay() async {
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

    func testRemovesProfileForDisplay() async {
        let store = InMemoryProfileStore()
        let profile = DisplayProfile(
            displayIdentity: .builtIn,
            logicalWidth: 1512,
            logicalHeight: 982,
            isHiDPI: true
        )

        await store.save(profile)
        await store.remove(for: .builtIn)

        let removedProfile = await store.profile(for: .builtIn)

        XCTAssertNil(removedProfile)
    }
}
