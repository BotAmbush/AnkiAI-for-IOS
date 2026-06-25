import XCTest
@testable import AnkiAI

/// M2.44 — read-only deck options (limits + retention) for a deck.
final class BackendDeckOptionsTests: XCTestCase {

    private func openFixture() throws -> BackendCollectionGateway {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try AnkiCollection.createFixture(path: dir.appendingPathComponent("collection.anki2").path)
        return BackendCollectionGateway(path: dir.appendingPathComponent("collection.anki2").path)
    }

    func testReadDeckOptions() async throws {
        let gateway = try openFixture()
        let decks = try await gateway.deckTree()
        let math = try XCTUnwrap(decks.first { $0.name == "Math" })

        let options = try await gateway.deckOptions(deckId: math.deckId)
        XCTAssertGreaterThan(options.newPerDay, 0, "default new-cards/day limit")
        XCTAssertGreaterThan(options.reviewsPerDay, 0, "default reviews/day limit")
        XCTAssertFalse(options.configName.isEmpty)
    }
}
