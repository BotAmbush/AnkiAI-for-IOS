import XCTest
@testable import AnkiAI

/// Issue 2 — manual note creation goes through the REAL backend (the same path the
/// ManualAddCardView uses): pick note type, add fields + tags to a deck, and the
/// note appears in Browse with its tags and renders correctly.
final class BackendManualAddTests: XCTestCase {

    private func openFixture() throws -> BackendCollectionGateway {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try AnkiCollection.createFixture(path: dir.appendingPathComponent("collection.anki2").path)
        return BackendCollectionGateway(path: dir.appendingPathComponent("collection.anki2").path)
    }

    func testManualBasicNoteWithTagsAppearsInBrowse() async throws {
        let gateway = try openFixture()
        let deckId = try await gateway.resolveOrCreateDeck(name: "Manual")
        let before = try await gateway.searchCardIds(query: "deck:Manual").count

        let nt = try await gateway.notetypeId(named: "Basic")
        let noteId = try await gateway.addNote(notetypeId: nt, fields: ["Manual front", "Manual back"], deckId: deckId)
        try await gateway.addTags(noteId: noteId, tags: "manual added")

        let after = try await gateway.searchCardIds(query: "deck:Manual").count
        XCTAssertEqual(after, before + 1, "the new card appears in the deck (Browse search)")

        let cid = try XCTUnwrap(try await gateway.cardIds(inDeckNamed: "Manual").last)
        let rendered = try await gateway.renderCard(cardId: cid)
        XCTAssertTrue(rendered.questionHTML.contains("Manual front"))

        let editable = try await gateway.editableNote(cardId: cid)
        XCTAssertTrue(editable.tags.contains("manual"))
        XCTAssertTrue(editable.tags.contains("added"))
    }

    func testManualClozeNoteRenders() async throws {
        let gateway = try openFixture()
        let deckId = try await gateway.resolveOrCreateDeck(name: "ManualCloze")
        let nt = try await gateway.notetypeId(named: "Cloze")
        _ = try await gateway.addNote(notetypeId: nt, fields: ["The sky is {{c1::blue}}.", ""], deckId: deckId)

        let cid = try XCTUnwrap(try await gateway.cardIds(inDeckNamed: "ManualCloze").first)
        let rendered = try await gateway.renderCard(cardId: cid)
        XCTAssertTrue(rendered.questionHTML.contains("[...]"), "cloze question shows the blank")
        XCTAssertTrue(rendered.answerHTML.contains("blue"), "cloze answer reveals the word")
    }
}
