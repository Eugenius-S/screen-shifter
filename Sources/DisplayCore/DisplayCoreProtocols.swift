import CoreGraphics
import Foundation
import ScreenShifterDomain

@MainActor
public protocol DisplayInventorying: Sendable {
    func connectedDisplays() throws -> [ConnectedDisplay]
}

@MainActor
public protocol DisplayModeApplying: Sendable {
    func apply(_ profile: DisplayProfile, to display: ConnectedDisplay) throws -> DisplayApplicationOutcome
    func reset(_ display: ConnectedDisplay) throws
}

@MainActor
public protocol MainDisplayIDProviding: Sendable {
    var mainDisplayID: CGDirectDisplayID { get }
}
