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
	public let refreshRate: Double

	public init(
		displayIdentity: DisplayIdentity,
		logicalWidth: UInt32,
		logicalHeight: UInt32,
		isHiDPI: Bool,
		refreshRate: Double = 0
	) {
		self.displayIdentity = displayIdentity
		self.logicalWidth = logicalWidth
		self.logicalHeight = logicalHeight
		self.isHiDPI = isHiDPI
		self.refreshRate = refreshRate
	}

	private enum CodingKeys: String, CodingKey {
		case displayIdentity, logicalWidth, logicalHeight, isHiDPI, refreshRate
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		displayIdentity = try container.decode(DisplayIdentity.self, forKey: .displayIdentity)
		logicalWidth = try container.decode(UInt32.self, forKey: .logicalWidth)
		logicalHeight = try container.decode(UInt32.self, forKey: .logicalHeight)
		isHiDPI = try container.decode(Bool.self, forKey: .isHiDPI)
		refreshRate = try container.decodeIfPresent(Double.self, forKey: .refreshRate) ?? 0
	}
}

public protocol DisplayProfileStoring: Sendable {
	func save(_ profile: DisplayProfile) async
	func remove(for identity: DisplayIdentity) async
	func profile(for identity: DisplayIdentity) async -> DisplayProfile?
	func profiles() async -> [DisplayProfile]
}

public actor InMemoryProfileStore: DisplayProfileStoring {
	private var storedProfiles: [DisplayIdentity: DisplayProfile] = [:]

	public init() {}

	public func save(_ profile: DisplayProfile) {
		storedProfiles[profile.displayIdentity] = profile
	}

	public func remove(for identity: DisplayIdentity) {
		storedProfiles.removeValue(forKey: identity)
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

		do {
			let encodedProfiles = try JSONEncoder().encode(profiles)
			defaults.set(encodedProfiles, forKey: storageKey)
		} catch {
			// P2-9: surface encode errors instead of silently dropping
			// the write. Without this a corrupt in-memory profile would
			// look like a successful save.
			logProfileStoreError(operation: "encode", error: error)
		}
	}

	public func remove(for identity: DisplayIdentity) {
		var profiles = decodedProfiles()
		profiles.removeValue(forKey: identity.storageKey)

		do {
			let encodedProfiles = try JSONEncoder().encode(profiles)
			defaults.set(encodedProfiles, forKey: storageKey)
		} catch {
			logProfileStoreError(operation: "encode", error: error)
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

		do {
			return try JSONDecoder().decode([String: DisplayProfile].self, from: encodedProfiles)
		} catch {
			// P2-9: surface decode errors so silent profile-store
			// corruption does not look like a clean start.
			logProfileStoreError(operation: "decode", error: error)
			return [:]
		}
	}

	private nonisolated func logProfileStoreError(operation: String, error: Error) {
		let message = "UserDefaultsProfileStore: profile \(operation) failed: \(error)\n"
		FileHandle.standardError.write(Data(message.utf8))
	}
}

public enum LogLevel: String, Codable, Sendable {
	case info = "INFO"
	case error = "ERROR"
}

public actor LocalLogStore {
	/// P2-8: cap the on-disk log so it cannot grow without bound. When the
	/// existing file is larger than this, `append(_:)` rotates it before
	/// writing the new line. 1 MiB is a reasonable upper bound for a
	/// menu-bar utility that logs user-facing events.
	public static let maxLogBytes: UInt64 = 1_048_576

	// P2-2: share a single ISO-8601 formatter across all appends; it is
	// expensive to build and the format never changes. NSFormatter is
	// safe to use from multiple threads for read-only formatting.
	private nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = {
		let formatter = ISO8601DateFormatter()
		return formatter
	}()

	public static var defaultFileURL: URL {
		FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
			.appendingPathComponent("Application Support", isDirectory: true)
			.appendingPathComponent("Screen Shifter", isDirectory: true)
			.appendingPathComponent("screen-shifter.log")
	}

	private let fileURL: URL
	private let maxLogBytes: UInt64

	public init(
		fileURL: URL = LocalLogStore.defaultFileURL,
		maxLogBytes: UInt64 = LocalLogStore.maxLogBytes
	) {
		self.fileURL = fileURL
		self.maxLogBytes = maxLogBytes
	}

	public func append(level: LogLevel, message: String, date: Date = Date()) throws {
		let directoryURL = fileURL.deletingLastPathComponent()
		try FileManager.default.createDirectory(
			at: directoryURL,
			withIntermediateDirectories: true
		)

		// P2-8: rotate the file when it has grown past the cap. The simplest
		// viable policy: drop the existing file before writing the new line
		// when the on-disk size is over the cap. We accept losing the old
		// entries in exchange for a bounded, predictable log.
		if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
		   let size = attributes[.size] as? UInt64,
		   size > maxLogBytes {
			try FileManager.default.removeItem(at: fileURL)
		}

		let line = "\(Self.iso8601.string(from: date)) \(level.rawValue) \(message)\n"
		let data = Data(line.utf8)

		if FileManager.default.fileExists(atPath: fileURL.path) {
			let handle = try FileHandle(forWritingTo: fileURL)
			// P2-1: guarantee the handle is closed even if write throws,
			// so a partial append does not leak the file descriptor.
			defer { try? handle.close() }
			try handle.seekToEnd()
			try handle.write(contentsOf: data)
		} else {
			try data.write(to: fileURL, options: .atomic)
		}
	}

	public func text() throws -> String {
		guard FileManager.default.fileExists(atPath: fileURL.path) else {
			return ""
		}

		return try String(contentsOf: fileURL, encoding: .utf8)
	}

	public func clear() throws {
		let directoryURL = fileURL.deletingLastPathComponent()
		try FileManager.default.createDirectory(
			at: directoryURL,
			withIntermediateDirectories: true
		)
		try Data().write(to: fileURL, options: .atomic)
	}
}
