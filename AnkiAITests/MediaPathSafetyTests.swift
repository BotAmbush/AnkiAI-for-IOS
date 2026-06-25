import XCTest
@testable import AnkiAI

/// M2.43 — the appres://media handler must serve files only from the media folder
/// (CLAUDE.md security: guard media handling against path traversal).
final class MediaPathSafetyTests: XCTestCase {

    private let dir = URL(fileURLWithPath: "/var/collection.media")

    private func resolve(_ urlString: String) -> URL? {
        guard let url = URL(string: urlString) else { return nil }
        return AppResSchemeHandler.mediaFileURL(in: dir, requestURL: url)
    }

    func testNormalFilenameResolvesInsideMediaFolder() {
        let u = resolve("appres://media/cat.jpg")
        XCTAssertEqual(u?.path, "/var/collection.media/cat.jpg")
    }

    func testPercentEncodedSpaceIsDecoded() {
        let u = resolve("appres://media/my%20pic.jpg")
        XCTAssertEqual(u?.path, "/var/collection.media/my pic.jpg")
    }

    func testParentTraversalIsRejected() {
        // Even though lastPathComponent strips most of it, the guard must hold.
        XCTAssertNil(resolve("appres://media/..%2F..%2Fetc%2Fpasswd"))
        XCTAssertNil(resolve("appres://media/.."))
    }

    func testEmptyOrDotNameRejected() {
        XCTAssertNil(resolve("appres://media/"))
        XCTAssertNil(resolve("appres://media/."))
    }

    func testResolvedPathStaysUnderMediaFolder() {
        guard let u = resolve("appres://media/sub.png") else { return XCTFail() }
        XCTAssertTrue(u.path.hasPrefix("/var/collection.media/"))
        XCTAssertEqual(u.deletingLastPathComponent().path, "/var/collection.media")
    }
}
