import XCTest
@testable import AnkiAI

/// Repair 4 — real `.apkg` export → fresh-import round trip (the happy path the
/// second audit required). Uses the large fixture (Basic + Cloze, many decks +
/// subdecks, Hebrew/MathJax/Unicode, varied scheduling incl. suspended).
final class BackendApkgRoundTripTests: XCTestCase {

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testApkgRoundTripIntoFreshCollection() async throws {
        let dir = try tempDir()
        let srcPath = dir.appendingPathComponent("src.anki2").path
        try AnkiCollection.createLargeFixture(path: srcPath, scale: 60)
        let source = BackendCollectionGateway(path: srcPath)

        let srcCards = try await source.searchCardIds(query: "").count
        let srcDecks = Set(try await source.deckTree().map { $0.name })
        let srcSuspended = try await source.searchCardIds(query: "is:suspended").count
        XCTAssertGreaterThan(srcCards, 50)

        // Export to .apkg (with scheduling + deck configs).
        let apkg = dir.appendingPathComponent("export.apkg").path
        try await source.exportApkg(toPath: apkg)
        XCTAssertTrue(FileManager.default.fileExists(atPath: apkg))

        // Fresh target collection (only the Default deck).
        let tgtPath = dir.appendingPathComponent("tgt.anki2").path
        let target = BackendCollectionGateway(path: tgtPath)
        _ = try await target.searchCardIds(query: "")          // force create/open

        // Import the package — the happy path.
        try await target.importApkg(fromPath: apkg)

        // Notes / cards preserved.
        let tgtCards = try await target.searchCardIds(query: "").count
        XCTAssertEqual(tgtCards, srcCards, "all cards imported")

        // Decks + subdecks preserved.
        let tgtDecks = Set(try await target.deckTree().map { $0.name })
        for deck in ["Languages::Hebrew", "Science::Physics", "Math::Calculus"] {
            XCTAssertTrue(tgtDecks.contains(deck), "deck \(deck) missing after import; have \(tgtDecks)")
        }
        XCTAssertTrue(srcDecks.isSubset(of: tgtDecks), "every source deck present after import")

        // Scheduling (suspended) preserved.
        let tgtSuspended = try await target.searchCardIds(query: "is:suspended").count
        XCTAssertEqual(tgtSuspended, srcSuspended, "suspended scheduling state preserved")

        // Hebrew/RTL content renders after import.
        let hebIds = try await target.cardIds(inDeckNamed: "Languages::Hebrew")
        var foundRTL = false
        for id in hebIds.prefix(20) {
            let r = try await target.renderCard(cardId: id)
            if r.questionHTML.contains(#"dir="rtl""#) || r.answerHTML.contains(#"dir="rtl""#) { foundRTL = true; break }
        }
        XCTAssertTrue(foundRTL, "imported Hebrew card renders RTL")
    }

    /// Repair 4 — a failed mandatory pre-import backup ABORTS the import (the
    /// collection is not modified). Here the target path is a directory, so the
    /// backup export cannot open it.
    func testImportBlockedWhenPreImportBackupFails() async throws {
        let dir = try tempDir()
        let srcPath = dir.appendingPathComponent("src.anki2").path
        try AnkiCollection.createFixture(path: srcPath)
        let apkg = dir.appendingPathComponent("e.apkg").path
        try await BackendCollectionGateway(path: srcPath).exportApkg(toPath: apkg)

        // A path that is a directory — exportColpkg(path:) will fail to open it.
        let badPath = dir.appendingPathComponent("not-a-collection-dir")
        try FileManager.default.createDirectory(at: badPath, withIntermediateDirectories: true)
        let gateway = BackendCollectionGateway(path: badPath.path)
        do {
            try await gateway.importApkg(fromPath: apkg)
            XCTFail("import must be blocked when the mandatory pre-import backup fails")
        } catch let error as GatewayError {
            guard case .backupRequired = error else { return XCTFail("expected backupRequired, got \(error)") }
        }
    }

    /// Export the imported result again and confirm a second round trip is stable.
    func testApkgDoubleRoundTrip() async throws {
        let dir = try tempDir()
        let srcPath = dir.appendingPathComponent("src.anki2").path
        try AnkiCollection.createFixture(path: srcPath)
        let source = BackendCollectionGateway(path: srcPath)
        let n = try await source.searchCardIds(query: "").count

        let apkg1 = dir.appendingPathComponent("a1.apkg").path
        try await source.exportApkg(toPath: apkg1)

        let midPath = dir.appendingPathComponent("mid.anki2").path
        let mid = BackendCollectionGateway(path: midPath)
        _ = try await mid.searchCardIds(query: "")
        try await mid.importApkg(fromPath: apkg1)

        let apkg2 = dir.appendingPathComponent("a2.apkg").path
        try await mid.exportApkg(toPath: apkg2)
        let finalPath = dir.appendingPathComponent("final.anki2").path
        let final = BackendCollectionGateway(path: finalPath)
        _ = try await final.searchCardIds(query: "")
        try await final.importApkg(fromPath: apkg2)

        let finalCount = try await final.searchCardIds(query: "").count
        XCTAssertEqual(finalCount, n, "card count stable across two round trips")
    }
}
