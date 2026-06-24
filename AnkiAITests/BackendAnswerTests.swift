import XCTest
import CryptoKit
@testable import AnkiAI

/// M2.3 integration tests: answer/grade real cards through the backend scheduler
/// (the first WRITE path) and verify the collection actually mutates, while the
/// canonical fixture (opened only as a copy) stays byte-identical.
final class BackendAnswerTests: XCTestCase {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func dirHash(_ dir: URL) throws -> String {
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var hasher = SHA256()
        for f in files {
            hasher.update(data: Data(f.lastPathComponent.utf8))
            hasher.update(data: try Data(contentsOf: f))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func openedCopy() throws -> (gateway: BackendCollectionGateway, fixtureDir: URL, originalHash: String) {
        let fixtureDir = try makeTempDir()
        try AnkiCollection.createFixture(path: fixtureDir.appendingPathComponent("collection.anki2").path)
        let originalHash = try dirHash(fixtureDir)
        let copyDir = try makeTempDir()
        for f in try FileManager.default.contentsOfDirectory(at: fixtureDir, includingPropertiesForKeys: nil) {
            try FileManager.default.copyItem(at: f, to: copyDir.appendingPathComponent(f.lastPathComponent))
        }
        let gateway = BackendCollectionGateway(path: copyDir.appendingPathComponent("collection.anki2").path)
        return (gateway, fixtureDir, originalHash)
    }

    private func mathNewCount(_ gateway: BackendCollectionGateway) async throws -> Int {
        let decks = try await gateway.deckTree()
        return try XCTUnwrap(decks.first { $0.name == "Math" }).newCount
    }

    func testAnsweringReducesDeckNewCount() async throws {
        let (gateway, fixtureDir, originalHash) = try openedCopy()

        let before = try await mathNewCount(gateway)
        XCTAssertGreaterThanOrEqual(before, 1, "fixture should leave new Math cards")

        // Grade every Math card "Easy" — new cards graduate out of the new queue.
        for id in try await gateway.cardIds(inDeckNamed: "Math") {
            try await gateway.answerCard(cardId: id, rating: .easy)
        }

        let after = try await mathNewCount(gateway)
        XCTAssertLessThan(after, before, "answering must reduce the deck's new count (real scheduler write)")

        // The canonical fixture (opened only as a copy) must be untouched.
        XCTAssertEqual(try dirHash(fixtureDir), originalHash)
    }

    func testInvalidRatingNotExposed() async throws {
        // AnswerRating is a closed enum (1...4); ensure the mapping is intact.
        XCTAssertEqual(AnswerRating.again.rawValue, 1)
        XCTAssertEqual(AnswerRating.easy.rawValue, 4)
        XCTAssertEqual(AnswerRating.allCases.count, 4)
    }

    func testAnswerSingleCardIsDeterministicMutation() async throws {
        let (gateway, _, _) = try openedCopy()
        let before = try await gateway.deckTree()
        let mathIds = try await gateway.cardIds(inDeckNamed: "Math")
        let id = try XCTUnwrap(mathIds.first)
        try await gateway.answerCard(cardId: id, rating: .good)
        let after = try await gateway.deckTree()
        XCTAssertNotEqual(before, after, "grading a card must change the deck tree")
    }
}
