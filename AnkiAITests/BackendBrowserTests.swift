import XCTest
@testable import AnkiAI

/// M2.7 integration tests: search the real collection via arbitrary Anki queries
/// (the card browser path). Read-only.
final class BackendBrowserTests: XCTestCase {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func openedFixture() throws -> BackendCollectionGateway {
        let dir = try makeTempDir()
        try AnkiCollection.createFixture(path: dir.appendingPathComponent("collection.anki2").path)
        return BackendCollectionGateway(path: dir.appendingPathComponent("collection.anki2").path)
    }

    func testEmptySearchReturnsAllCards() async throws {
        let gateway = try openedFixture()
        let all = try await gateway.searchCardIds(query: "")
        // Fixture: 3 Hebrew + 4 Math = 7 cards.
        XCTAssertEqual(all.count, 7)
    }

    func testDeckSearch() async throws {
        let gateway = try openedFixture()
        let math = try await gateway.searchCardIds(query: "deck:Math")
        XCTAssertEqual(math.count, 4)
        let hebrew = try await gateway.searchCardIds(query: #"deck:"Languages::Hebrew""#)
        XCTAssertEqual(hebrew.count, 3)
    }

    func testTagSearch() async throws {
        let gateway = try openedFixture()
        // The fixture tags two Hebrew notes with "vocab".
        let vocab = try await gateway.searchCardIds(query: "tag:vocab")
        XCTAssertEqual(vocab.count, 2)
    }

    func testFreeTextSearchFindsHebrewCard() async throws {
        let gateway = try openedFixture()
        // One Hebrew card front contains שלום.
        let hits = try await gateway.searchCardIds(query: "שלום")
        XCTAssertGreaterThanOrEqual(hits.count, 1)
    }
}
