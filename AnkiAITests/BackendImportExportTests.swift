import XCTest
@testable import AnkiAI

/// M2.10 integration test: export the collection to an `.apkg`, import it into a
/// fresh collection, and verify the decks/cards survive the round-trip — proving
/// real Anki package format compatibility.
final class BackendImportExportTests: XCTestCase {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testApkgExportImportRoundTrip() async throws {
        let dir = try makeTempDir()

        // Source collection from the fixture.
        let srcPath = dir.appendingPathComponent("src.anki2").path
        try AnkiCollection.createFixture(path: srcPath)
        let source = BackendCollectionGateway(path: srcPath)

        // Export to .apkg.
        let apkgPath = dir.appendingPathComponent("export.apkg").path
        try await source.exportApkg(toPath: apkgPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: apkgPath), "an .apkg should be written")

        // Fresh, empty destination collection (opening creates it).
        let dstPath = dir.appendingPathComponent("dst.anki2").path
        let dest = BackendCollectionGateway(path: dstPath)
        let beforeCount = try await dest.searchCardIds(query: "").count
        XCTAssertEqual(beforeCount, 0, "fresh collection starts empty")

        // Import the package.
        try await dest.importApkg(fromPath: apkgPath)

        let afterCount = try await dest.searchCardIds(query: "").count
        XCTAssertEqual(afterCount, 7, "all 7 fixture cards should import")

        let names = Set(try await dest.deckTree().map { $0.name })
        XCTAssertTrue(names.contains("Math"), "decks: \(names)")
        XCTAssertTrue(names.contains("Languages::Hebrew"))
    }
}
