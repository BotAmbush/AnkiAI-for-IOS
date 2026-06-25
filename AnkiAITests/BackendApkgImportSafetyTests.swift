import XCTest
@testable import AnkiAI

/// M2 — `.apkg` import SAFETY: a malformed/incompatible package must fail
/// gracefully (no crash) and leave the existing collection completely unchanged
/// (backend transaction rollback + a pre-import backup).
final class BackendApkgImportSafetyTests: XCTestCase {

    private func makeFixtureDir() throws -> (gateway: BackendCollectionGateway, dir: URL, path: String) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("collection.anki2").path
        try AnkiCollection.createFixture(path: path)
        return (BackendCollectionGateway(path: path), dir, path)
    }

    func testMalformedApkgFailsAndPreservesCollection() async throws {
        let (gateway, dir, _) = try makeFixtureDir()
        let bad = dir.appendingPathComponent("garbage.apkg")
        try Data("this is definitely not a zip archive".utf8).write(to: bad)

        do {
            try await gateway.importApkg(fromPath: bad.path)
            XCTFail("a malformed .apkg must not import successfully")
        } catch {
            // expected — graceful failure
        }

        let count = try await gateway.searchCardIds(query: "").count
        XCTAssertEqual(count, 7, "the existing collection is preserved after a failed import")
        let names = Set(try await gateway.deckTree().map { $0.name })
        XCTAssertTrue(names.contains("Math"), "decks intact after a failed import")
    }

    func testMissingApkgFileFailsGracefully() async throws {
        let (gateway, _, _) = try makeFixtureDir()
        do {
            try await gateway.importApkg(fromPath: "/nonexistent/path/none.apkg")
            XCTFail("a missing .apkg must fail")
        } catch {
            // expected
        }
        let count = try await gateway.searchCardIds(query: "").count
        XCTAssertEqual(count, 7, "collection preserved when the package file is missing")
    }
}
