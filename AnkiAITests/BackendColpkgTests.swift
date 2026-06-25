import XCTest
@testable import AnkiAI

/// M2.27 integration test: a `.colpkg` backup → restore round-trip. Unlike `.apkg`
/// import (which hits an anki deck-merge edge), whole-collection colpkg restore
/// replaces the target cleanly.
final class BackendColpkgTests: XCTestCase {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testBackupRestoreRoundTrip() async throws {
        let dir = try makeTempDir()

        let srcPath = dir.appendingPathComponent("src.anki2").path
        try AnkiCollection.createFixture(path: srcPath)
        let source = BackendCollectionGateway(path: srcPath)
        let cardsBefore = try await source.searchCardIds(query: "").count
        XCTAssertEqual(cardsBefore, 7)

        let colpkgPath = dir.appendingPathComponent("backup.colpkg").path
        try await source.backup(toPath: colpkgPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: colpkgPath))

        // Restore into a different (fresh) collection.
        let dstPath = dir.appendingPathComponent("dst.anki2").path
        let dest = BackendCollectionGateway(path: dstPath)
        try await dest.restore(fromColpkg: colpkgPath)

        let cardsAfter = try await dest.searchCardIds(query: "").count
        XCTAssertEqual(cardsAfter, 7, "all fixture cards restored")
        let names = Set(try await dest.deckTree().map { $0.name })
        XCTAssertTrue(names.contains("Math"), "decks restored: \(names)")
        XCTAssertTrue(names.contains("Languages::Hebrew"))
    }
}
