import XCTest
import CryptoKit
@testable import AnkiAI

/// M2.5 integration tests: add a note through the backend (the path the AI card
/// creator uses), and verify it becomes a real, renderable card in a real deck —
/// while the canonical fixture (opened only as a copy) stays byte-identical.
final class BackendAddNoteTests: XCTestCase {

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

    func testBasicNotetypeAndDeckResolution() async throws {
        let (gateway, _, _) = try openedCopy()
        let ntid = try await gateway.basicNotetypeId()
        XCTAssertGreaterThan(ntid, 0)
        let deckId = try await gateway.resolveOrCreateDeck(name: "Math") // existing
        XCTAssertGreaterThan(deckId, 0)
        // Resolving the same name twice returns the same id (idempotent).
        let again = try await gateway.resolveOrCreateDeck(name: "Math")
        XCTAssertEqual(deckId, again)
    }

    func testAddNoteCreatesRealRenderableCard() async throws {
        let (gateway, fixtureDir, originalHash) = try openedCopy()
        let ntid = try await gateway.basicNotetypeId()
        let deckId = try await gateway.resolveOrCreateDeck(name: "AI Test Deck")

        let front = #"<div dir="rtl">שאלת AI</div>"#
        let noteId = try await gateway.addNote(notetypeId: ntid, fields: [front, "AI answer"], deckId: deckId)
        XCTAssertGreaterThan(noteId, 0)

        // The new deck now shows exactly one new card.
        let decks = try await gateway.deckTree()
        let deck = try XCTUnwrap(decks.first { $0.name == "AI Test Deck" })
        XCTAssertEqual(deck.newCount, 1)

        // The card is searchable and renders the content we added.
        let ids = try await gateway.cardIds(inDeckNamed: "AI Test Deck")
        XCTAssertEqual(ids.count, 1)
        let rendered = try await gateway.renderCard(cardId: try XCTUnwrap(ids.first))
        XCTAssertTrue(rendered.questionHTML.contains("שאלת AI"), "question should contain the added front")
        XCTAssertTrue(rendered.answerHTML.contains("AI answer"), "answer should contain the added back")

        // The canonical fixture must be untouched (writes happen on the copy).
        XCTAssertEqual(try dirHash(fixtureDir), originalHash)
    }
}
