import XCTest
import CryptoKit
@testable import AnkiAI

/// M2.4 integration tests: bury / suspend / undo through the backend, verifying
/// the collection mutates and undo reverses it, with the canonical fixture
/// (opened only as a copy) staying byte-identical.
final class BackendBurySuspendUndoTests: XCTestCase {

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

    /// New-card count for the all-new Hebrew deck.
    private func hebNew(_ gateway: BackendCollectionGateway) async throws -> Int {
        let decks = try await gateway.deckTree()
        return try XCTUnwrap(decks.first { $0.name == "Languages::Hebrew" }).newCount
    }

    private func firstHebCard(_ gateway: BackendCollectionGateway) async throws -> Int64 {
        let ids = try await gateway.cardIds(inDeckNamed: "Languages::Hebrew")
        return try XCTUnwrap(ids.first)
    }

    func testSuspendReducesNewCount() async throws {
        let (gateway, fixtureDir, originalHash) = try openedCopy()
        let before = try await hebNew(gateway)
        XCTAssertGreaterThanOrEqual(before, 1)
        let id = try await firstHebCard(gateway)
        try await gateway.suspendCard(cardId: id)
        let after = try await hebNew(gateway)
        XCTAssertEqual(after, before - 1, "suspending a new card removes it from the new count")
        XCTAssertEqual(try dirHash(fixtureDir), originalHash)
    }

    func testBuryReducesNewCount() async throws {
        let (gateway, _, _) = try openedCopy()
        let before = try await hebNew(gateway)
        let id = try await firstHebCard(gateway)
        try await gateway.buryCard(cardId: id)
        let after = try await hebNew(gateway)
        XCTAssertEqual(after, before - 1, "burying a new card removes it from the new count")
    }

    func testSuspendThenUndoRestores() async throws {
        let (gateway, _, _) = try openedCopy()
        let before = try await hebNew(gateway)   // deckTree call happens BEFORE the mutation
        let id = try await firstHebCard(gateway)
        try await gateway.suspendCard(cardId: id) // last op
        try await gateway.undo()                  // undoes the suspend
        let after = try await hebNew(gateway)
        XCTAssertEqual(after, before, "undo must restore the suspended card to the new count")
    }
}
