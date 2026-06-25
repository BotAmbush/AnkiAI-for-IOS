import XCTest
@testable import AnkiAI

/// M2.37 — unsuspend restores a suspended card.
final class BackendUnsuspendTests: XCTestCase {

    private func openFixture() throws -> BackendCollectionGateway {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try AnkiCollection.createFixture(path: dir.appendingPathComponent("collection.anki2").path)
        return BackendCollectionGateway(path: dir.appendingPathComponent("collection.anki2").path)
    }

    func testSuspendThenUnsuspend() async throws {
        let gateway = try openFixture()
        let ids = try await gateway.cardIds(inDeckNamed: "Languages::Hebrew")
        let cid = try XCTUnwrap(ids.first)

        try await gateway.suspendCard(cardId: cid)
        let whileSuspended = try await gateway.searchCardIds(query: "is:suspended")
        XCTAssertTrue(whileSuspended.contains(cid), "card is suspended")

        try await gateway.unsuspendCard(cardId: cid)
        let afterUnsuspend = try await gateway.searchCardIds(query: "is:suspended")
        XCTAssertFalse(afterUnsuspend.contains(cid), "card is no longer suspended")
    }
}
