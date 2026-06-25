import XCTest
@testable import AnkiAI

/// M2.35 — per-card reschedule: set a due date, and forget (reset to new).
final class BackendRescheduleTests: XCTestCase {

    private func openFixture() throws -> BackendCollectionGateway {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try AnkiCollection.createFixture(path: dir.appendingPathComponent("collection.anki2").path)
        return BackendCollectionGateway(path: dir.appendingPathComponent("collection.anki2").path)
    }

    func testSetDueDateThenForget() async throws {
        let gateway = try openFixture()
        let ids = try await gateway.cardIds(inDeckNamed: "Math")
        let cid = try XCTUnwrap(ids.first)

        // Schedule as a review card due in 5 days → it gets a due date.
        try await gateway.setDueDate(cardId: cid, spec: "5")
        let scheduled = try await gateway.cardInfo(cardId: cid)
        XCTAssertNotNil(scheduled.dueDate, "set-due-date makes it a review card with a due date")

        // Forget → reset to new (no review due date, has a new-queue position).
        try await gateway.forgetCard(cardId: cid)
        let forgotten = try await gateway.cardInfo(cardId: cid)
        XCTAssertNil(forgotten.dueDate, "a forgotten card is new — no review due date")
        XCTAssertNotNil(forgotten.duePosition, "a forgotten card has a new-queue position")
    }
}
