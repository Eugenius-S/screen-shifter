import XCTest
@testable import ScreenShifterDomain

final class LocalLogStoreTests: XCTestCase {
    func testPersistsEntriesAndCanClearThem() async throws {
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenShifterTests.\(UUID().uuidString).log")
        defer {
            try? FileManager.default.removeItem(at: logURL)
        }

        let store = LocalLogStore(fileURL: logURL)
        try await store.append(level: .error, message: "Mode unavailable")

        let logText = try await store.text()

        XCTAssertTrue(logText.contains("ERROR Mode unavailable"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: logURL.path))

        try await store.clear()

        let clearedText = try await store.text()

        XCTAssertEqual(clearedText, "")
    }

    func testRotatesWhenFileExceedsMaxBytes() async throws {
        // P2-8: when the on-disk file is larger than the cap, the next
        // append must rotate (drop the old file) and start fresh.
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenShifterTests.\(UUID().uuidString).log")
        defer {
            try? FileManager.default.removeItem(at: logURL)
        }

        let store = LocalLogStore(fileURL: logURL, maxLogBytes: 50)

        // First append fits and is preserved.
        try await store.append(level: .info, message: "first")
        let firstText = try await store.text()
        XCTAssertTrue(firstText.contains("first"))

        // Build a file larger than the cap, then append again. The store
        // must drop the previous contents before the new line.
        try Data(String(repeating: "x", count: 200).utf8).write(to: logURL, options: .atomic)
        try await store.append(level: .info, message: "second")

        let rotatedText = try await store.text()

        XCTAssertFalse(
            rotatedText.contains("first"),
            "Old entries should be rotated away; got: \(rotatedText)"
        )
        XCTAssertTrue(rotatedText.contains("second"))
    }
}
