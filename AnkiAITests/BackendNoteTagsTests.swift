import XCTest
@testable import AnkiAI

/// M2.36 — editing a note's tags through the editor path (update_notes).
final class BackendNoteTagsTests: XCTestCase {

    private func openFixture() throws -> BackendCollectionGateway {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try AnkiCollection.createFixture(path: dir.appendingPathComponent("collection.anki2").path)
        return BackendCollectionGateway(path: dir.appendingPathComponent("collection.anki2").path)
    }

    func testEditNoteTagsRoundTrip() async throws {
        let gateway = try openFixture()
        let ids = try await gateway.cardIds(inDeckNamed: "Languages::Hebrew")
        let cid = try XCTUnwrap(ids.first)

        let editable = try await gateway.editableNote(cardId: cid)
        try await gateway.updateNote(
            NoteData(id: editable.noteId, notetypeId: 0, fields: editable.fields, tags: ["vocab", "hebrew"]))

        let reloaded = try await gateway.editableNote(cardId: cid)
        XCTAssertEqual(Set(reloaded.tags), Set(["vocab", "hebrew"]), "tags persisted")
    }

    func testNilTagsKeepsExistingTags() async throws {
        let gateway = try openFixture()
        let ids = try await gateway.cardIds(inDeckNamed: "Languages::Hebrew")
        let cid = try XCTUnwrap(ids.first)
        let editable = try await gateway.editableNote(cardId: cid)

        // Set a tag, then update fields-only (tags: nil) — the tag must survive.
        try await gateway.updateNote(
            NoteData(id: editable.noteId, notetypeId: 0, fields: editable.fields, tags: ["keepme"]))
        try await gateway.updateNote(
            NoteData(id: editable.noteId, notetypeId: 0, fields: editable.fields, tags: nil))

        let reloaded = try await gateway.editableNote(cardId: cid)
        XCTAssertTrue(reloaded.tags.contains("keepme"), "nil tags keeps existing tags")
    }
}
