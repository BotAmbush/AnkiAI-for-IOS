import XCTest
@testable import AnkiAI

/// M2.25 integration test: custom study creates a filtered deck that gathers
/// matching cards, verified through the deck tree.
final class BackendFilteredDeckTests: XCTestCase {

    private func openFixture() throws -> BackendCollectionGateway {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try AnkiCollection.createFixture(path: dir.appendingPathComponent("collection.anki2").path)
        return BackendCollectionGateway(path: dir.appendingPathComponent("collection.anki2").path)
    }

    func testCreateFilteredDeck() async throws {
        let gateway = try openFixture()
        let deckId = try await gateway.createFilteredDeck(name: "Custom Study", search: "deck:Math", limit: 50)
        XCTAssertGreaterThan(deckId, 0)

        let names = Set(try await gateway.deckTree().map { $0.name })
        XCTAssertTrue(names.contains("Custom Study"), "filtered deck shows in the tree: \(names)")
    }
}
