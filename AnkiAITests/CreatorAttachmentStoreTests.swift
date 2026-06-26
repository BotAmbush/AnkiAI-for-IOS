import XCTest
@testable import AnkiAI

/// Repair 2 — file-backed, validated, scoped creator attachments.
final class CreatorAttachmentStoreTests: XCTestCase {

    private let sessionId = "att-test"

    override func setUp() { CreatorAttachmentStore.clear(sessionId: sessionId) }
    override func tearDown() { CreatorAttachmentStore.clear(sessionId: sessionId) }

    private func payload(_ bytes: [UInt8], type: String = "image/png") -> ImagePayload {
        ImagePayload(base64: Data(bytes).base64EncodedString(), mediaType: type)
    }

    func testSaveWritesScopedFileAndRestores() throws {
        let p = payload(Array("hello world".utf8))
        let ref = try CreatorAttachmentStore.save(payload: p, sessionId: sessionId)

        let dir = try CreatorAttachmentStore.attachmentsDir(sessionId)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent(ref.filename).path))
        XCTAssertEqual(ref.byteSize, 11)
        XCTAssertFalse(ref.sha256.isEmpty)

        // "Relaunch": load + validate.
        let restored = try CreatorAttachmentStore.load(ref: ref, sessionId: sessionId)
        XCTAssertEqual(restored.base64, p.base64)
        XCTAssertEqual(restored.mediaType, "image/png")
    }

    func testChecksumMismatchRejected() throws {
        let ref = try CreatorAttachmentStore.save(payload: payload(Array("data".utf8)), sessionId: sessionId)
        var bad = ref; bad = CreatorAttachmentRef(id: ref.id, filename: ref.filename, contentType: ref.contentType,
                                                  byteSize: ref.byteSize, sha256: "00", createdAt: ref.createdAt)
        XCTAssertThrowsError(try CreatorAttachmentStore.load(ref: bad, sessionId: sessionId)) {
            XCTAssertEqual($0 as? CreatorAttachmentError, .checksumMismatch)
        }
    }

    func testSizeMismatchRejected() throws {
        let ref = try CreatorAttachmentStore.save(payload: payload(Array("data".utf8)), sessionId: sessionId)
        let bad = CreatorAttachmentRef(id: ref.id, filename: ref.filename, contentType: ref.contentType,
                                       byteSize: 999, sha256: ref.sha256, createdAt: ref.createdAt)
        XCTAssertThrowsError(try CreatorAttachmentStore.load(ref: bad, sessionId: sessionId)) {
            XCTAssertEqual($0 as? CreatorAttachmentError, .sizeMismatch)
        }
    }

    func testMissingFileRejected() {
        let ref = CreatorAttachmentRef(id: "x", filename: "does-not-exist.png", contentType: "image/png",
                                       byteSize: 1, sha256: "00", createdAt: Date())
        XCTAssertThrowsError(try CreatorAttachmentStore.load(ref: ref, sessionId: sessionId)) {
            XCTAssertEqual($0 as? CreatorAttachmentError, .missingFile)
        }
    }

    func testPathTraversalRejected() {
        let ref = CreatorAttachmentRef(id: "x", filename: "../../escape.png", contentType: "image/png",
                                       byteSize: 1, sha256: "00", createdAt: Date())
        XCTAssertThrowsError(try CreatorAttachmentStore.load(ref: ref, sessionId: sessionId)) {
            XCTAssertEqual($0 as? CreatorAttachmentError, .pathEscape)
        }
    }

    func testOversizedFileRejected() {
        let big = [UInt8](repeating: 0, count: CreatorAttachmentStore.maxFileBytes + 1)
        XCTAssertThrowsError(try CreatorAttachmentStore.save(payload: payload(big), sessionId: sessionId)) {
            XCTAssertEqual($0 as? CreatorAttachmentError, .tooLarge)
        }
    }

    func testClearRemovesAllAttachmentFiles() throws {
        _ = try CreatorAttachmentStore.save(payload: payload(Array("a".utf8)), sessionId: sessionId)
        _ = try CreatorAttachmentStore.save(payload: payload(Array("b".utf8)), sessionId: sessionId)
        XCTAssertGreaterThan(CreatorAttachmentStore.totalBytes(sessionId), 0)
        CreatorAttachmentStore.clear(sessionId: sessionId)
        XCTAssertEqual(CreatorAttachmentStore.totalBytes(sessionId), 0)
    }
}
