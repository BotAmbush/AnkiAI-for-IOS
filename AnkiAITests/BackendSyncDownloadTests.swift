import XCTest
@testable import AnkiAI

/// M2.29 — AnkiWeb full-sync DOWNLOAD endpoint-discovery + safety.
///
/// These run offline by forcing failure against an unreachable local endpoint
/// (127.0.0.1:9, the discard port → connection refused), so they deterministically
/// exercise the failure/safety/diagnostic paths without touching AnkiWeb. The
/// successful-download path and the live endpoint-redirect regression
/// (AnkiDroid #14935 / #19102) are device-verified with a real account.
final class BackendSyncDownloadTests: XCTestCase {

    private func makeFixture() throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("collection.anki2").path
        try AnkiCollection.createFixture(path: path)
        return path
    }

    /// 4 & 5: a failed download (here: unreachable endpoint) must leave the local
    /// collection completely intact — never wiped or replaced.
    func testFailedDownloadPreservesLocalCollection() async throws {
        let path = try makeFixture()

        XCTAssertThrowsError(
            try AnkiCollection.syncDownload(path: path, hkey: "bogus-key", endpoint: "http://127.0.0.1:9/"))

        let after = BackendCollectionGateway(path: path)
        let count = try await after.searchCardIds(query: "").count
        XCTAssertEqual(count, 7, "local collection preserved after a failed download")
        let names = Set(try await after.deckTree().map { $0.name })
        XCTAssertTrue(names.contains("Math"), "decks intact: \(names)")
    }

    /// 1 & 2 (offline portion): the provided/base endpoint is honored and NOT
    /// silently replaced by a default; diagnostics record the operation + host.
    /// 3 (no-secrets): the session key never appears in diagnostics.
    func testDiagnosticsHonorCustomEndpointAndHideSecrets() throws {
        let path = try makeFixture()
        let secret = "super-secret-session-key"

        do {
            try AnkiCollection.syncDownload(path: path, hkey: secret, endpoint: "http://127.0.0.1:9/")
            XCTFail("download against an unreachable endpoint should fail")
        } catch {
            let msg = "\(error)"
            XCTAssertTrue(msg.contains("op=download"), "diagnostics record the operation: \(msg)")
            XCTAssertTrue(msg.contains("base_endpoint=127.0.0.1"),
                          "the custom endpoint is used and not replaced by a default: \(msg)")
            XCTAssertFalse(msg.contains(secret), "the session key must never be logged")
            XCTAssertFalse(msg.lowercased().contains("password"), "no password in diagnostics")
        }
    }

    /// A clearly-invalid endpoint override is rejected up front (no network, local
    /// collection untouched).
    func testInvalidEndpointOverrideRejected() async throws {
        let path = try makeFixture()
        XCTAssertThrowsError(
            try AnkiCollection.syncDownload(path: path, hkey: "k", endpoint: "not a url"))
        let after = BackendCollectionGateway(path: path)
        XCTAssertEqual(try await after.searchCardIds(query: "").count, 7)
    }
}
