import XCTest
@testable import AnkiAI

/// M2.42 — date-boundary behavior: the scheduler's day rollover (via the
/// collection's timezone config) determines what counts as "due today".
final class BackendDateBoundaryTests: XCTestCase {

    private func openFixture() throws -> BackendCollectionGateway {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try AnkiCollection.createFixture(path: dir.appendingPathComponent("collection.anki2").path)
        return BackendCollectionGateway(path: dir.appendingPathComponent("collection.anki2").path)
    }

    func testDueTomorrowIsNotDueToday() async throws {
        let gateway = try openFixture()
        let ids = try await gateway.cardIds(inDeckNamed: "Math")
        let cid = try XCTUnwrap(ids.first)

        // Scheduled for tomorrow → must NOT be due today (day boundary respected).
        try await gateway.setDueDate(cardId: cid, spec: "1")
        let dueTomorrow = try await gateway.searchCardIds(query: "deck:Math is:due")
        XCTAssertFalse(dueTomorrow.contains(cid), "a card due tomorrow is not due today")

        // Scheduled for today → IS due today.
        try await gateway.setDueDate(cardId: cid, spec: "0")
        let dueToday = try await gateway.searchCardIds(query: "deck:Math is:due")
        XCTAssertTrue(dueToday.contains(cid), "a card due today is due today")
    }

    func testReviewLoggedCountsAsRatedToday() async throws {
        let gateway = try openFixture()
        let ids = try await gateway.cardIds(inDeckNamed: "Math")
        let cid = try XCTUnwrap(ids.first)

        try await gateway.answerCard(cardId: cid, rating: .good)
        let ratedToday = try await gateway.searchCardIds(query: "rated:1")
        XCTAssertTrue(ratedToday.contains(cid), "a review answered now is within today's date boundary")
    }
}
