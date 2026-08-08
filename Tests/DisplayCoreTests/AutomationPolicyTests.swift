import XCTest
@testable import DisplayCore

final class AutomationPolicyTests: XCTestCase {
    func testBlocksDuringWakeProtection() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)

        let permission = AutomationPolicy.permission(
            isPaused: false,
            now: now,
            cooldownUntil: now.addingTimeInterval(-1),
            wakeProtectionUntil: now.addingTimeInterval(5)
        )

        XCTAssertEqual(permission, .wakeProtection)
    }
}
