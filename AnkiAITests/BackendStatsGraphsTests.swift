import XCTest
@testable import AnkiAI

/// M2.33 — statistics graphs (read-only) reflect real review history.
final class BackendStatsGraphsTests: XCTestCase {

    private func openFixture() throws -> BackendCollectionGateway {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try AnkiCollection.createFixture(path: dir.appendingPathComponent("collection.anki2").path)
        return BackendCollectionGateway(path: dir.appendingPathComponent("collection.anki2").path)
    }

    func testGraphsReflectAReview() async throws {
        let gateway = try openFixture()
        let ids = try await gateway.cardIds(inDeckNamed: "Math")
        let cid = try XCTUnwrap(ids.first)
        try await gateway.answerCard(cardId: cid, rating: .good)

        let graphs = try await gateway.statsGraphs(search: "", days: 31)
        let totalReviews = graphs.reviews.reduce(0) { $0 + $1.count }
        XCTAssertGreaterThan(totalReviews, 0, "today's review is reflected in the reviews graph")
    }

    func testGraphsParseEmptyCollectionSafely() async throws {
        let gateway = try openFixture()
        // No reviews yet → arrays decode without error (possibly empty).
        let graphs = try await gateway.statsGraphs(search: "", days: 31)
        XCTAssertGreaterThanOrEqual(graphs.reviews.count, 0)
        XCTAssertGreaterThanOrEqual(graphs.futureDue.count, 0)
    }
}
