import XCTest
@testable import AnkiAI

/// M2.9 integration tests: set card flags and add note tags through the backend,
/// verified via `flag:` / `tag:` search.
final class BackendFlagsTagsTests: XCTestCase {

    private func openedFixture() throws -> BackendCollectionGateway {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try AnkiCollection.createFixture(path: dir.appendingPathComponent("collection.anki2").path)
        return BackendCollectionGateway(path: dir.appendingPathComponent("collection.anki2").path)
    }

    func testSetAndClearFlag() async throws {
        let gateway = try openedFixture()
        let id = try XCTUnwrap(try await gateway.cardIds(inDeckNamed: "Math").first)

        XCTAssertEqual(try await gateway.searchCardIds(query: "flag:1").count, 0)
        try await gateway.setFlag(cardId: id, flag: 1)
        let flagged = try await gateway.searchCardIds(query: "flag:1")
        XCTAssertTrue(flagged.contains(id), "card should be flag:1")

        try await gateway.setFlag(cardId: id, flag: 0)
        XCTAssertEqual(try await gateway.searchCardIds(query: "flag:1").count, 0, "clearing the flag removes it")
    }

    func testAddTagToNote() async throws {
        let gateway = try openedFixture()
        let ntid = try await gateway.basicNotetypeId()
        let deckId = try await gateway.resolveOrCreateDeck(name: "Default")
        let noteId = try await gateway.addNote(notetypeId: ntid, fields: ["Q", "A"], deckId: deckId)

        XCTAssertEqual(try await gateway.searchCardIds(query: "tag:m29tag").count, 0)
        try await gateway.addTags(noteId: noteId, tags: "m29tag")
        XCTAssertEqual(try await gateway.searchCardIds(query: "tag:m29tag").count, 1, "tag should be searchable")
    }
}
