import XCTest
@testable import AnkiAI

/// M6 — broader production-path integration over a larger, richer collection
/// (many decks/subdecks, Basic + Cloze, Hebrew/MathJax/Unicode, varied scheduling
/// states). Exercises the REAL BackendCollectionGateway, not the stub.
final class BackendLargeFixtureTests: XCTestCase {

    private func openLarge(scale: Int = 120) throws -> BackendCollectionGateway {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("collection.anki2").path
        try AnkiCollection.createLargeFixture(path: path, scale: scale)
        return BackendCollectionGateway(path: path)
    }

    func testBroadIntegration() async throws {
        let gateway = try openLarge()

        // Shape: many decks + subdecks.
        let names = Set(try await gateway.deckTree().map { $0.name })
        for expected in ["Languages::Hebrew", "Science::Physics", "Math::Calculus", "Misc"] {
            XCTAssertTrue(names.contains(expected), "missing deck \(expected): \(names)")
        }

        // Volume + varied scheduling states.
        let total = try await gateway.searchCardIds(query: "").count
        XCTAssertGreaterThan(total, 100, "a few hundred cards")
        let suspended = try await gateway.searchCardIds(query: "is:suspended").count
        XCTAssertGreaterThan(suspended, 0)
        let due = try await gateway.searchCardIds(query: "is:due").count
        XCTAssertGreaterThan(due, 0)
        let clozeNotes = try await gateway.searchCardIds(query: "note:Cloze").count
        XCTAssertGreaterThan(clozeNotes, 0, "Cloze notes present")

        // Hebrew/RTL renders.
        let hebIds = try await gateway.cardIds(inDeckNamed: "Languages::Hebrew")
        let cid = try XCTUnwrap(hebIds.first)
        let rendered = try await gateway.renderCard(cardId: cid)
        XCTAssertTrue(rendered.questionHTML.contains(#"dir="rtl""#) || rendered.answerHTML.contains(#"dir="rtl""#))

        // The scheduler queue never returns a suspended card.
        let suspendedSet = Set(try await gateway.searchCardIds(query: "is:suspended"))
        try await gateway.setStudyDeck(named: "Languages::Hebrew")
        var answered = 0
        for _ in 0..<60 {
            guard let next = (try await gateway.nextDueCard()).cardId else { break }
            XCTAssertFalse(suspendedSet.contains(next), "queue returned a suspended card")
            try await gateway.answerCard(cardId: next, rating: .good)
            answered += 1
        }
        XCTAssertGreaterThan(answered, 0)

        // Real stats reflect the reviews just performed.
        let graphs = try await gateway.statsGraphs(search: "", days: 31)
        XCTAssertGreaterThan(graphs.reviews.reduce(0) { $0 + $1.count }, 0)
    }

    func testColpkgRoundTripAtScale() async throws {
        let source = try openLarge(scale: 80)
        let before = try await source.searchCardIds(query: "").count

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let pkg = dir.appendingPathComponent("backup.colpkg").path
        try await source.backup(toPath: pkg)

        let dest = BackendCollectionGateway(path: dir.appendingPathComponent("dst.anki2").path)
        try await dest.restore(fromColpkg: pkg)
        let after = try await dest.searchCardIds(query: "").count
        XCTAssertEqual(after, before, "all cards survive a colpkg round-trip at scale")
    }
}
