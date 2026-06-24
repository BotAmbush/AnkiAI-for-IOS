import XCTest
import CryptoKit
@testable import AnkiAI

/// M2.6 integration test: move cards between decks via the backend and verify the
/// due counts shift accordingly, with the canonical fixture (copy) untouched.
final class BackendMoveCardTests: XCTestCase {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func dirHash(_ dir: URL) throws -> String {
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var hasher = SHA256()
        for f in files {
            hasher.update(data: Data(f.lastPathComponent.utf8))
            hasher.update(data: try Data(contentsOf: f))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func openedCopy() throws -> (gateway: BackendCollectionGateway, fixtureDir: URL, originalHash: String) {
        let fixtureDir = try makeTempDir()
        try AnkiCollection.createFixture(path: fixtureDir.appendingPathComponent("collection.anki2").path)
        let originalHash = try dirHash(fixtureDir)
        let copyDir = try makeTempDir()
        for f in try FileManager.default.contentsOfDirectory(at: fixtureDir, includingPropertiesForKeys: nil) {
            try FileManager.default.copyItem(at: f, to: copyDir.appendingPathComponent(f.lastPathComponent))
        }
        let gateway = BackendCollectionGateway(path: copyDir.appendingPathComponent("collection.anki2").path)
        return (gateway, fixtureDir, originalHash)
    }

    private func due(_ entry: DeckTreeEntry) -> Int { entry.newCount + entry.learnCount + entry.reviewCount }

    func testMovingCardsShiftsDeckCounts() async throws {
        let (gateway, fixtureDir, originalHash) = try openedCopy()

        let before = try await gateway.deckTree()
        let mathBefore = try XCTUnwrap(before.first { $0.name == "Math" })
        let hebBefore = try XCTUnwrap(before.first { $0.name == "Languages::Hebrew" })
        XCTAssertGreaterThan(due(mathBefore), 0)

        // Move every Math card into the Hebrew deck.
        for id in try await gateway.cardIds(inDeckNamed: "Math") {
            try await gateway.moveCard(cardId: id, toDeckId: hebBefore.deckId)
        }

        let after = try await gateway.deckTree()
        let mathAfter = after.first { $0.name == "Math" }
        // Math is now empty (0 due) — or removed from the tree entirely.
        if let mathAfter { XCTAssertEqual(due(mathAfter), 0) }

        let hebAfter = try XCTUnwrap(after.first { $0.name == "Languages::Hebrew" })
        XCTAssertGreaterThan(due(hebAfter), due(hebBefore), "Hebrew should gain the moved Math cards")

        XCTAssertEqual(try dirHash(fixtureDir), originalHash, "moves happen on the copy; original untouched")
    }
}
