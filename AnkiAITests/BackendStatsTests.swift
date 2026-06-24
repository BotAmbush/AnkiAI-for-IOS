import XCTest
@testable import AnkiAI

/// M2.8 integration test: collection-wide statistics computed from backend
/// searches against the real fixture collection.
final class BackendStatsTests: XCTestCase {

    private func openedFixture() throws -> BackendCollectionGateway {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try AnkiCollection.createFixture(path: dir.appendingPathComponent("collection.anki2").path)
        return BackendCollectionGateway(path: dir.appendingPathComponent("collection.anki2").path)
    }

    func testCollectionStatsMatchFixture() async throws {
        let gateway = try openedFixture()
        let stats = try await gateway.collectionStats()

        // Fixture: 3 Hebrew (new) + 4 Math (2 new, 1 review via set_due_date,
        // 1 learning via grade). Nothing suspended or mature.
        XCTAssertEqual(stats.total, 7)
        XCTAssertEqual(stats.suspended, 0)
        XCTAssertEqual(stats.mature, 0)
        XCTAssertGreaterThanOrEqual(stats.review, 1)
        XCTAssertGreaterThanOrEqual(stats.learning, 1)
        XCTAssertGreaterThanOrEqual(stats.newCount, 4)
        // Every card is in exactly one of new/learning/review (none suspended/buried).
        XCTAssertEqual(stats.newCount + stats.learning + stats.review, stats.total)
    }
}
