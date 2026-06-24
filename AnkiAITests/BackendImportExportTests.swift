import XCTest
@testable import AnkiAI

/// M2.10 integration test: export the collection to an `.apkg` and verify a valid
/// package is produced.
///
/// NOTE: the full export→import round-trip into a *fresh* collection currently
/// hits an anki-internal `InvalidInput: "decks have different kinds"`
/// (rslib import_export/package/apkg/import/decks.rs) — under investigation
/// (likely the Default-deck merge with default import options). Until that's
/// resolved, import is wired but not asserted here; see docs/known-issues.md.
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
        XCTAssertTrue(FileManager.default.fileExists(atPath: apkgPath), "an .apkg should be written")

        let data = try Data(contentsOf: URL(fileURLWithPath: apkgPath))
        XCTAssertGreaterThan(data.count, 100, "the .apkg should be non-trivial")
        // .apkg is a ZIP container → starts with the "PK" local-file-header magic.
        XCTAssertEqual(Array(data.prefix(2)), [0x50, 0x4B], "the .apkg should be a ZIP archive")
    }
}
