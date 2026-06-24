import XCTest
@testable import AnkiAI

/// M2.14 integration tests: read and edit raw note fields through the backend
/// NotesService (get_note / update_notes) — the path the AI "improve card"
/// proposal and the note editor use. No rendered-HTML workaround.
final class BackendNoteEditTests: XCTestCase {

    private func openFixture() throws -> BackendCollectionGateway {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try AnkiCollection.createFixture(path: dir.appendingPathComponent("collection.anki2").path)
        return BackendCollectionGateway(path: dir.appendingPathComponent("collection.anki2").path)
    }

    func testNoteReadUpdateRoundTrip() async throws {
        let gateway = try openFixture()
        let ntid = try await gateway.basicNotetypeId()
        let deckId = try await gateway.resolveOrCreateDeck(name: "Default")
        let noteId = try await gateway.addNote(notetypeId: ntid, fields: ["Front Q", "Back A"], deckId: deckId)

        var note = try await gateway.note(id: noteId)
        XCTAssertEqual(note.fields, ["Front Q", "Back A"], "raw fields read back exactly")
        XCTAssertEqual(note.notetypeId, ntid)

        note.fields[0] = "Edited Q"
        try await gateway.updateNote(note)

        let after = try await gateway.note(id: noteId)
        XCTAssertEqual(after.fields[0], "Edited Q", "the field edit persisted")

        // The rendered card reflects the edit.
        let ids = try await gateway.searchCardIds(query: "deck:Default")
        let cid = try XCTUnwrap(ids.first)
        let rendered = try await gateway.renderCard(cardId: cid)
        XCTAssertTrue(rendered.questionHTML.contains("Edited Q"))
    }

    func testCardContextUsesRealRawNote() async throws {
        let gateway = try openFixture()
        let ids = try await gateway.cardIds(inDeckNamed: "Languages::Hebrew")
        let cid = try XCTUnwrap(ids.first)

        let info = try await gateway.cardInfo(cardId: cid)
        XCTAssertGreaterThan(info.noteId, 0, "card_stats exposes the note id")

        let ctx = try await gateway.cardContext(cardId: cid)
        let unwrapped = try XCTUnwrap(ctx)
        XCTAssertEqual(unwrapped.noteId, info.noteId, "context targets the real note (not 0)")
        XCTAssertTrue(unwrapped.fields[0].contains("dir=\"rtl\""), "raw front field, not rendered HTML")
    }
}
