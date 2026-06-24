import XCTest
@testable import AnkiAI

/// M2.16 integration test: create a cloze card and verify the backend renders it
/// correctly — the question hides the deletion, the answer reveals it.
final class BackendClozeTests: XCTestCase {

    private func openFixture() throws -> BackendCollectionGateway {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try AnkiCollection.createFixture(path: dir.appendingPathComponent("collection.anki2").path)
        return BackendCollectionGateway(path: dir.appendingPathComponent("collection.anki2").path)
    }

    func testClozeCardRendersHiddenThenRevealed() async throws {
        let gateway = try openFixture()
        let clozeNt = try await gateway.notetypeId(named: "Cloze")
        XCTAssertGreaterThan(clozeNt, 0, "the Cloze notetype exists by default")

        let deckId = try await gateway.resolveOrCreateDeck(name: "Default")
        let text = "The capital of France is {{c1::Paris}}."
        _ = try await gateway.addNote(notetypeId: clozeNt, fields: [text, ""], deckId: deckId)

        let ids = try await gateway.searchCardIds(query: "deck:Default")
        let cid = try XCTUnwrap(ids.first)
        let rendered = try await gateway.renderCard(cardId: cid)

        // Question hides the deletion; answer reveals "Paris".
        XCTAssertFalse(rendered.questionHTML.contains("Paris"), "the cloze answer is hidden on the question")
        XCTAssertTrue(rendered.questionHTML.contains("["), "the cloze blank renders as [...]")
        XCTAssertTrue(rendered.answerHTML.contains("Paris"), "the answer reveals the deletion")
    }
}
