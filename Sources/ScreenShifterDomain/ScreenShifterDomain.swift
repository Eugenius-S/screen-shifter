import Foundation

public struct DisplayIdentity: Codable, Equatable, Hashable, Sendable {
	public let storageKey: String

	private init(storageKey: String) {
		self.storageKey = storageKey
	}

	public static let builtIn = DisplayIdentity(storageKey: "builtin")

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
	func profiles() async -> [DisplayProfile]
}

public actor InMemoryProfileStore: DisplayProfileStoring {
	private var storedProfiles: [DisplayIdentity: DisplayProfile] = [:]

	public init() {}

	public func save(_ profile: DisplayProfile) {
		storedProfiles[profile.displayIdentity] = profile
	}

	public func profile(for identity: DisplayIdentity) -> DisplayProfile? {
		storedProfiles[identity]
	}

	public func profiles() -> [DisplayProfile] {
		storedProfiles.values.sorted {
			$0.displayIdentity.storageKey < $1.displayIdentity.storageKey
		}
	}
}

public actor UserDefaultsProfileStore: DisplayProfileStoring {
	private let defaults: UserDefaults
	private let storageKey: String

	public init(
		suiteName: String? = nil,
		storageKey: String = "savedDisplayProfiles"
	) {
		self.defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
		self.storageKey = storageKey
	}

	public func save(_ profile: DisplayProfile) {
		var profiles = decodedProfiles()
		profiles[profile.displayIdentity.storageKey] = profile

		if let encodedProfiles = try? JSONEncoder().encode(profiles) {
			defaults.set(encodedProfiles, forKey: storageKey)
		}
	}

	public func profile(for identity: DisplayIdentity) -> DisplayProfile? {
		decodedProfiles()[identity.storageKey]
	}

	public func profiles() -> [DisplayProfile] {
		decodedProfiles().values.sorted {
			$0.displayIdentity.storageKey < $1.displayIdentity.storageKey
		}
	}

	private func decodedProfiles() -> [String: DisplayProfile] {
		guard let encodedProfiles = defaults.data(forKey: storageKey) else {
			return [:]
		}

		return (try? JSONDecoder().decode([String: DisplayProfile].self, from: encodedProfiles)) ?? [:]
	}
}