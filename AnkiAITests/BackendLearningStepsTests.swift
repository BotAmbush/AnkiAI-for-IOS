import XCTest
@testable import AnkiAI

/// M2.25: learning/relearning step transitions run in the backend scheduler.
/// Answering a new card "Again" keeps it in learning (no multi-day graduation),
/// while a positive answer advances it.
final class BackendLearningStepsTests: XCTestCase {

    private func openFixture() throws -> BackendCollectionGateway {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try AnkiCollection.createFixture(path: dir.appendingPathComponent("collection.anki2").path)
        return BackendCollectionGateway(path: dir.appendingPathComponent("collection.anki2").path)
    }

    func testAgainKeepsNewCardInLearning() async throws {
        let gateway = try openFixture()
        let nt = try await gateway.basicNotetypeId()
        let deckId = try await gateway.resolveOrCreateDeck(name: "StepTest")
        _ = try await gateway.addNote(notetypeId: nt, fields: ["Q", "A"], deckId: deckId)

        let ids = try await gateway.cardIds(inDeckNamed: "StepTest")
        let cid = try XCTUnwrap(ids.first)

        // Answering a brand-new card "Again" enters/keeps it in a learning step;
        // it must NOT jump to a multi-day review interval.
        try await gateway.answerCard(cardId: cid, rating: .again)
        let info = try await gateway.cardInfo(cardId: cid)
        XCTAssertLessThanOrEqual(info.interval, 1, "learning card should not graduate to a multi-day interval")
    }
}
