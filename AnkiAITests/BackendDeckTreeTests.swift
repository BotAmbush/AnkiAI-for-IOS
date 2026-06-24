import XCTest
import CryptoKit
@testable import AnkiAI

/// Phase C/D integration tests: open a REAL Anki collection through the Rust
/// backend and assert real deck names + new/learn/review counts, while proving
/// the canonical fixture is never mutated (operations run on a copy).
final class BackendDeckTreeTests: XCTestCase {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Hash every file in a directory (sorted) so SQLite side-files (-wal/-shm)
    /// are included — detects any write to the canonical fixture directory.
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

    func testCreateFixtureProducesFile() throws {
        let dir = try makeTempDir()
        let path = dir.appendingPathComponent("collection.anki2").path
        try AnkiCollection.createFixture(path: path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    func testOpenRealCollectionReturnsRealDecksAndCounts() async throws {
        let fixtureDir = try makeTempDir()
        try AnkiCollection.createFixture(path: fixtureDir.appendingPathComponent("collection.anki2").path)
        let originalHash = try dirHash(fixtureDir)

        // Operate on a COPY of the whole directory (preserves -wal/-shm).
        let copyDir = try makeTempDir()
        for f in try FileManager.default.contentsOfDirectory(at: fixtureDir, includingPropertiesForKeys: nil) {
            try FileManager.default.copyItem(at: f, to: copyDir.appendingPathComponent(f.lastPathComponent))
        }

        let gateway = BackendCollectionGateway(path: copyDir.appendingPathComponent("collection.anki2").path)
        let decks = try await gateway.deckTree()
        let names = Set(decks.map { $0.name })

        XCTAssertTrue(names.contains("Math"), "decks: \(names)")
        XCTAssertTrue(names.contains("Languages"))
        XCTAssertTrue(names.contains("Languages::Hebrew"))

        let heb = try XCTUnwrap(decks.first { $0.name == "Languages::Hebrew" })
        // Backend deck levels are 1-based for real decks (top-level = 1, subdeck = 2).
        XCTAssertEqual(heb.level, 2, "subdeck should be level 2")
        XCTAssertGreaterThan(heb.newCount, 0, "Hebrew deck should have new cards")

        let math = try XCTUnwrap(decks.first { $0.name == "Math" })
        XCTAssertGreaterThanOrEqual(math.reviewCount, 1, "fixture sets one Math card due today")
        XCTAssertGreaterThanOrEqual(math.learnCount, 1, "fixture grades one Math card into learning")
        XCTAssertGreaterThan(math.newCount + math.learnCount + math.reviewCount, 0)

        // The canonical fixture directory must be byte-identical (no writes to it).
        XCTAssertEqual(try dirHash(fixtureDir), originalHash, "opening must not mutate the original fixture")
    }

    func testReopenIsDeterministicAndOriginalUnchanged() async throws {
        let fixtureDir = try makeTempDir()
        try AnkiCollection.createFixture(path: fixtureDir.appendingPathComponent("collection.anki2").path)
        let h0 = try dirHash(fixtureDir)

        func openCopyNames() async throws -> [String] {
            let copyDir = try makeTempDir()
            for f in try FileManager.default.contentsOfDirectory(at: fixtureDir, includingPropertiesForKeys: nil) {
                try FileManager.default.copyItem(at: f, to: copyDir.appendingPathComponent(f.lastPathComponent))
            }
            let g = BackendCollectionGateway(path: copyDir.appendingPathComponent("collection.anki2").path)
            return try await g.deckTree().map { $0.name }.sorted()
        }

        let first = try await openCopyNames()
        let second = try await openCopyNames()
        XCTAssertEqual(first, second, "deck listing must be deterministic")
        XCTAssertEqual(try dirHash(fixtureDir), h0, "original fixture must remain unchanged across opens")
    }
}
