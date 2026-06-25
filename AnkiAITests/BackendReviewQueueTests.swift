import XCTest
@testable import AnkiAI

/// M2.32 — the reviewer studies the scheduler QUEUE (not all cards). Verifies that
/// suspended cards are excluded and that answers persist (an answered card leaves
/// today's queue), fixing the "shows all/suspended cards" and "answer not saved"
/// reports.
final class BackendReviewQueueTests: XCTestCase {

    private func openFixture() throws -> BackendCollectionGateway {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try AnkiCollection.createFixture(path: dir.appendingPathComponent("collection.anki2").path)
        return BackendCollectionGateway(path: dir.appendingPathComponent("collection.anki2").path)
    }

    func testQueueReturnsADueCard() async throws {
        let gateway = try openFixture()
        try await gateway.setStudyDeck(named: "Languages::Hebrew")
        let q = try await gateway.nextDueCard()
        XCTAssertNotNil(q.cardId, "the deck has due/new cards to study")
        XCTAssertGreaterThan(q.newCount + q.learnCount + q.reviewCount, 0)
    }

    func testSuspendedCardExcludedFromQueue() async throws {
        let gateway = try openFixture()
        try await gateway.setStudyDeck(named: "Languages::Hebrew")
        let first = try await gateway.nextDueCard()
        let suspended = try XCTUnwrap(first.cardId)

        try await gateway.suspendCard(cardId: suspended)

        try await gateway.setStudyDeck(named: "Languages::Hebrew")
        var guardLimit = 50
        while let cid = (try await gateway.nextDueCard()).cardId, guardLimit > 0 {
            XCTAssertNotEqual(cid, suspended, "a suspended card must never appear in the queue")
            try await gateway.answerCard(cardId: cid, rating: .easy)
            guardLimit -= 1
        }
    }

    func testAnsweringEasyRemovesCardFromTodaysQueue() async throws {
        let gateway = try openFixture()
        try await gateway.setStudyDeck(named: "Math")
        let first = try await gateway.nextDueCard()
        let answered = try XCTUnwrap(first.cardId)

        // "Easy" graduates the card to a multi-day interval → not due again today.
        try await gateway.answerCard(cardId: answered, rating: .easy)

        try await gateway.setStudyDeck(named: "Math")
        var reappeared = false
        var guardLimit = 50
        while let cid = (try await gateway.nextDueCard()).cardId, guardLimit > 0 {
            if cid == answered { reappeared = true; break }
            try await gateway.answerCard(cardId: cid, rating: .easy)
            guardLimit -= 1
        }
        XCTAssertFalse(reappeared, "an answered (Easy) card is no longer due today — the answer persisted")
    }
}
