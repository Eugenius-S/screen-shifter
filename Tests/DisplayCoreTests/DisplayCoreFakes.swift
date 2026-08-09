import CoreGraphics
@testable import DisplayCore
import ScreenShifterDomain
import XCTest

@MainActor
final class FakeDisplayInventory: DisplayInventorying, @unchecked Sendable {
    var displaysToReturn: [ConnectedDisplay] = []
    var errorToThrow: Error?

    func connectedDisplays() throws -> [ConnectedDisplay] {
        if let errorToThrow { throw errorToThrow }
        return displaysToReturn
    }
}

@MainActor
final class FakeDisplayModeApplier: DisplayModeApplying, @unchecked Sendable {
    struct Call: Equatable {
        enum Kind: Equatable { case apply, reset }
        let kind: Kind
        let displayID: UInt32
    }

    private(set) var calls: [Call] = []
    var applyResult: DisplayApplicationOutcome = .alreadyApplied
    var applyError: Error?

    func apply(_ profile: DisplayProfile, to display: ConnectedDisplay) throws -> DisplayApplicationOutcome {
        calls.append(Call(kind: .apply, displayID: display.displayID))
        if let applyError { throw applyError }
        return applyResult
    }

    func reset(_ display: ConnectedDisplay) throws {
        calls.append(Call(kind: .reset, displayID: display.displayID))
    }
}

@MainActor
final class FakeMainDisplayIDProvider: MainDisplayIDProviding, @unchecked Sendable {
    var mainDisplayID: CGDirectDisplayID = 1
}
