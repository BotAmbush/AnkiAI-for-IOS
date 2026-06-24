import XCTest
@testable import AnkiAI

/// M2.10/M2.18 integration test: export the collection to an `.apkg` and import it
/// into a fresh collection (round-trip), verifying decks/cards survive.
final class BackendImportExportTests: XCTestCase {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testApkgExportProducesValidPackage() async throws {
        let dir = try makeTempDir()
        let srcPath = dir.appendingPathComponent("src.anki2").path
        try AnkiCollection.createFixture(path: srcPath)
        let source = BackendCollectionGateway(path: srcPath)

        let apkgPath = dir.appendingPathComponent("export.apkg").path
        try await source.exportApkg(toPath: apkgPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: apkgPath))

        let data = try Data(contentsOf: URL(fileURLWithPath: apkgPath))
        XCTAssertGreaterThan(data.count, 100)
        XCTAssertEqual(Array(data.prefix(2)), [0x50, 0x4B], "the .apkg should be a ZIP archive")
    }

    func testApkgExportImportRoundTrip() async throws {
        let dir = try makeTempDir()

        let srcPath = dir.appendingPathComponent("src.anki2").path
        try AnkiCollection.createFixture(path: srcPath)
        let source = BackendCollectionGateway(path: srcPath)

        let apkgPath = dir.appendingPathComponent("export.apkg").path
        try await source.exportApkg(toPath: apkgPath)

        // Fresh, empty destination collection.
        let dstPath = dir.appendingPathComponent("dst.anki2").path
        let dest = BackendCollectionGateway(path: dstPath)
        let before = try await dest.searchCardIds(query: "").count
        XCTAssertEqual(before, 0)

        try await dest.importApkg(fromPath: apkgPath)

        let after = try await dest.searchCardIds(query: "").count
        XCTAssertEqual(after, 7, "all 7 fixture cards should import")

        let names = Set(try await dest.deckTree().map { $0.name })
        XCTAssertTrue(names.contains("Math"), "decks: \(names)")
        XCTAssertTrue(names.contains("Languages::Hebrew"))
    }
}
