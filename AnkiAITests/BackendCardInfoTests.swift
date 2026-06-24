import XCTest
@testable import AnkiAI

/// M2.12 integration tests: per-card scheduling info (due / interval / reviews /
/// lapses) from the backend — what the browser shows as "time until next".
final class BackendCardInfoTests: XCTestCase {

    private func openFixture() throws -> BackendCollectionGateway {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try AnkiCollection.createFixture(path: dir.appendingPathComponent("collection.anki2").path)
        return BackendCollectionGateway(path: dir.appendingPathComponent("collection.anki2").path)
    }

    func testNewCardInfo() async throws {
        let gateway = try openFixture()
        let ids = try await gateway.cardIds(inDeckNamed: "Languages::Hebrew")
        let id = try XCTUnwrap(ids.first)
        let info = try await gateway.cardInfo(cardId: id)

        XCTAssertEqual(info.reviews, 0, "a new card has no reviews")
        XCTAssertEqual(info.lapses, 0)
        XCTAssertFalse(info.cardType.isEmpty)
        XCTAssertTrue(info.deck.contains("Hebrew"), "deck: \(info.deck)")
        XCTAssertNotNil(info.duePosition, "a new card has a new-queue position")
        XCTAssertNil(info.dueDate, "a new card has no scheduled due date")
    }

    func testReviewedCardInfo() async throws {
        let gateway = try openFixture()
        let ids = try await gateway.cardIds(inDeckNamed: "Languages::Hebrew")
        let id = try XCTUnwrap(ids.first)

        try await gateway.answerCard(cardId: id, rating: .good)
        let info = try await gateway.cardInfo(cardId: id)

        XCTAssertGreaterThanOrEqual(info.reviews, 1, "after grading, reviews increases")
        XCTAssertNotNil(info.dueDate, "a reviewed card has a scheduled due date")
    }
}
