import XCTest
@testable import AnkiAI

/// M2.17 integration test: rename and delete decks via the backend, verified
/// through the deck tree.
final class BackendDeckMgmtTests: XCTestCase {

    private func openFixture() throws -> BackendCollectionGateway {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try AnkiCollection.createFixture(path: dir.appendingPathComponent("collection.anki2").path)
        return BackendCollectionGateway(path: dir.appendingPathComponent("collection.anki2").path)
    }

    private func names(_ gateway: BackendCollectionGateway) async throws -> Set<String> {
        Set(try await gateway.deckTree().map { $0.name })
    }

    func testRenameDeck() async throws {
        let gateway = try openFixture()
        let deckId = try await gateway.resolveOrCreateDeck(name: "TempDeck")
        var current = try await names(gateway)
        XCTAssertTrue(current.contains("TempDeck"))

        try await gateway.renameDeck(deckId: deckId, newName: "RenamedDeck")
        current = try await names(gateway)
        XCTAssertTrue(current.contains("RenamedDeck"), "deck renamed")
        XCTAssertFalse(current.contains("TempDeck"), "old name gone")
    }

    func testDeleteDeck() async throws {
        let gateway = try openFixture()
        let deckId = try await gateway.resolveOrCreateDeck(name: "DeleteMe")
        var current = try await names(gateway)
        XCTAssertTrue(current.contains("DeleteMe"))

        try await gateway.removeDeck(deckId: deckId)
        current = try await names(gateway)
        XCTAssertFalse(current.contains("DeleteMe"), "deck deleted")
    }
}
