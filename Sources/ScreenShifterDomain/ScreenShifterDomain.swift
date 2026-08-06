public struct DisplayIdentity: Codable, Equatable, Hashable, Sendable {
	public let storageKey: String

	private init(storageKey: String) {
		self.storageKey = storageKey
	}

	public static func external(
		vendorID: UInt32,
		productID: UInt32,
		serialNumber: UInt32?,
		name: String,
		physicalWidthMillimeters: UInt32,
		physicalHeightMillimeters: UInt32
	) -> DisplayIdentity {
		if let serialNumber {
			return DisplayIdentity(
				storageKey: "external:\(vendorID):\(productID):serial:\(serialNumber)"
			)
		}

		return DisplayIdentity(
			storageKey: "external:\(vendorID):\(productID):fallback:\(name):\(physicalWidthMillimeters)x\(physicalHeightMillimeters)"
		)
	}
}

public struct DisplayProfile: Codable, Equatable, Sendable {
	public let displayIdentity: DisplayIdentity
	public let logicalWidth: UInt32
	public let logicalHeight: UInt32
	public let isHiDPI: Bool

	public init(
		displayIdentity: DisplayIdentity,
		logicalWidth: UInt32,
		logicalHeight: UInt32,
		isHiDPI: Bool
	) {
		self.displayIdentity = displayIdentity
		self.logicalWidth = logicalWidth
		self.logicalHeight = logicalHeight
		self.isHiDPI = isHiDPI
	}
}

public protocol DisplayProfileStoring: Sendable {
	func save(_ profile: DisplayProfile) async
	func profile(for identity: DisplayIdentity) async -> DisplayProfile?
}

public actor InMemoryProfileStore: DisplayProfileStoring {
	private var profiles: [DisplayIdentity: DisplayProfile] = [:]

	public init() {}

	public func save(_ profile: DisplayProfile) {
		profiles[profile.displayIdentity] = profile
	}

	public func profile(for identity: DisplayIdentity) -> DisplayProfile? {
		profiles[identity]
	}
}